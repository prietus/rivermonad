{-# LANGUAGE OverloadedStrings #-}
-- | Program entry points: connecting to river, the main loop, restarts and
-- the launcher that compiles and runs the user configuration.
module Rivermonad.Main
  ( rivermonad
  , launch
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan
import qualified Control.Exception as E
import Control.Monad (forM_, forever, void, when)
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import Data.Binary.Get (runGetOrFail)
import qualified Data.Map.Strict as M
import Data.List (isSuffixOf)
import Data.Maybe (catMaybes)
import qualified Data.Set as S
import Data.Version (showVersion)
import Data.Word (Word32)
import System.Directory (doesFileExist, removeFile)
import System.Environment (getArgs, getExecutablePath, lookupEnv)
import System.Exit (exitFailure, exitSuccess, exitWith, ExitCode (..))
import System.FilePath ((</>))
import System.IO (hPutStrLn, hSetBuffering, stdout, stderr, BufferMode (..))
import System.Posix.Process (executeFile, getProcessID)
import System.Posix.Signals (Handler (..), installHandler, sigINT, sigTERM, sigUSR1, signalProcess)

import Paths_rivermonad (version)
import Rivermonad.Core
import Rivermonad.Config (defaultConfig)
import Rivermonad.Engine
import Rivermonad.Recompile
import Rivermonad.Shadows (shadowRgb)
import Rivermonad.Status (runStatusClient)
import Rivermonad.IPC (publishActionsIPC, publishIPC, publishWindowsIPC, runIPCClient, startIPCServer)
import Rivermonad.Operations (queue)
import qualified Rivermonad.StackSet as W
import Rivermonad.Wayland.Protocol
import Rivermonad.Wayland.Wire

-- | Entry point for the installed @rivermonad@ binary: if the user has a
-- @~/.config/rivermonad/rivermonad.hs@, compile it if needed and exec it,
-- otherwise run with the default configuration.
launch :: IO ()
launch = do
  args <- getArgs
  d <- getDirs
  haveCfg <- doesFileExist (cfgSource d)
  self <- getExecutablePath
  let passthrough = any (`elem` args) ["--version", "--help", "--restart", "--status", "--ipc"]
  if haveCfg && self /= cfgBinary d && not passthrough && args /= ["--recompile"]
    then do
      _ <- recompile False
      haveBin <- doesFileExist (cfgBinary d)
      if haveBin
        then executeFile (cfgBinary d) False args Nothing
        else rivermonad defaultConfig
    else rivermonad defaultConfig

-- | Run the window manager with the given configuration. This is what a
-- user's @main@ calls.
rivermonad :: XConfig -> IO ()
rivermonad cfg = do
  args <- getArgs
  case args of
    ["--version"] -> putStrLn ("rivermonad " ++ showVersion version)
    ["--recompile"] -> do
      ok <- recompile True
      exitWith (if ok then ExitSuccess else ExitFailure 1)
    ["--restart"] -> signalRunning
    ["--status"] -> runStatusClient
    ["--ipc", req] -> runIPCClient req
    ["--help"] -> putStr usage
    [] -> runWM cfg
    _ -> hPutStr' usage >> exitFailure
  where hPutStr' = hPutStrLn stderr

usage :: String
usage = unlines
  [ "Usage: rivermonad [OPTION]"
  , "  (no option)    run as the window manager of a river session"
  , "  --recompile    recompile ~/.config/rivermonad/rivermonad.hs"
  , "  --restart      ask the running rivermonad to restart"
  , "  --status       print status lines (JSON) for waybar's custom modules"
  , "  --ipc REQUEST  send a JSON request to the IPC socket, e.g."
  , "                 --ipc '\"EventStream\"'  or  --ipc '{\"Action\":{\"FocusWorkspace\":\"2\"}}'"
  , "  --version      print the version"
  ]

pidFile :: IO FilePath
pidFile = do
  dir <- maybe "/tmp" id <$> lookupEnv "XDG_RUNTIME_DIR"
  disp <- maybe "wayland-0" id <$> lookupEnv "WAYLAND_DISPLAY"
  pure (dir </> ("rivermonad-" ++ map (\c -> if c == '/' then '_' else c) disp ++ ".pid"))

signalRunning :: IO ()
signalRunning = do
  f <- pidFile
  r <- E.try (readFile f >>= \s -> length s `seq` pure s) :: IO (Either E.IOException String)
  case r of
    Right s | [(pid, _)] <- reads s -> signalProcess sigUSR1 (fromIntegral (pid :: Int))
    _ -> hPutStrLn stderr "rivermonad: no running instance found" >> exitFailure

------------------------------------------------------------------------------

runWM :: XConfig -> IO ()
runWM cfg = do
  hSetBuffering stdout LineBuffering
  c <- connect
  registry <- wlDisplayGetRegistry c displayObject
  cb <- wlDisplaySync c displayObject
  flush c
  globalsList <- collectGlobals c cb []
  let find name = case [ (n, v) | (n, i, v) <- globalsList, i == name ] of
        (x : _) -> Just x
        [] -> Nothing
      bindG name maxV = case find name of
        Just (n, v) -> do
          let v' = min v maxV
          o <- wlRegistryBind c registry n name v'
          pure (Just (o, v'))
        Nothing -> pure Nothing
  mwm <- bindG riverWindowManagerV1Interface riverWindowManagerV1Version
  mxkb <- bindG riverXkbBindingsV1Interface riverXkbBindingsV1Version
  mls <- bindG riverLayerShellV1Interface riverLayerShellV1Version
  mim <- bindG riverInputManagerV1Interface riverInputManagerV1Version
  mxc <- bindG riverXkbConfigV1Interface riverXkbConfigV1Version
  mli <- bindG riverLibinputConfigV1Interface riverLibinputConfigV1Version
  mcomp <- bindG wlCompositorInterface wlCompositorVersion
  mshm <- bindG wlShmInterface wlShmVersion
  mfx <- bindG riverFxV1Interface riverFxV1Version
  (wm, wmv) <- maybe (die' "river_window_manager_v1 not advertised: is this river >= 0.4?") pure mwm
  (xkb, _) <- maybe (die' "river_xkb_bindings_v1 not advertised") pure mxkb
  flush c

  ch <- newChan
  _ <- forkIO $ (forever (readEvents c >>= writeChan ch . InEvents))
         `E.catch` \(e :: E.SomeException) -> writeChan ch (InDisconnected (show e))
  forM_ [sigTERM, sigINT] $ \s -> installHandler s (Catch (writeChan ch InQuit)) Nothing
  _ <- installHandler sigUSR1 (Catch (writeChan ch InRestart)) Nothing
  pf <- pidFile
  getProcessID >>= \pid -> void (E.try (writeFile pf (show pid)) :: IO (Either E.IOException ()))

  restored <- loadRestartState
  ipcSrv <- startIPCServer ch
  forM_ ipcSrv $ \srv -> publishActionsIPC srv (map fst (ipcActions cfg))
  let g = Globals { gRegistry = registry, gWm = wm, gWmVersion = fromIntegral wmv, gXkb = xkb, gLayerShell = fst <$> mls
                  , gInputManager = fst <$> mim, gXkbConfig = fst <$> mxc, gLibinput = fst <$> mli
                  , gCompositor = fst <$> mcomp, gShm = fst <$> mshm
                  , gFx = fst <$> mfx, gFxVersion = maybe 0 (fromIntegral . snd) mfx }
      fxWord x = round (max 0 (min 1 x) * 4294967295 :: Double) :: Word32
  -- river-fx: effects of layer surfaces, by namespace
  case (gFx g, effects cfg) of
    (Just fxo, Just ec) | gFxVersion g >= 3 -> forM_ (fxLayers ec) $ \le -> do
      let (sr, sx, sy, cr, cg, cb, ca) = case leShadow le of
            Just sc -> let (r', g', b') = shadowRgb sc
                           a = max 0 (min 1 (shadowOpacity sc))
                           (dx, dy) = shadowOffset sc
                       in (max 0 (shadowRadius sc), dx, dy, r' * a, g' * a, b' * a, a)
            Nothing -> (0, 0, 0, 0, 0, 0, 0)
      riverFxV1SetLayerEffects c fxo (BC.pack (leNamespace le)) (fromIntegral (max 0 (leCornerRadius le)))
        (fxWord (leBlur le)) (fromIntegral sr) (fromIntegral sx) (fromIntegral sy)
        (fxWord cr) (fxWord cg) (fxWord cb) (fxWord ca)
      when (gFxVersion g >= 5 && leFade le > 0) $
        riverFxV1SetLayerFade c fxo (BC.pack (leNamespace le)) (fromIntegral (leFade le))
    _ -> pure ()
  case (gFx g, effects cfg) of
    (Just fxo, Just ec) | gFxVersion g >= 5, fxPopupBlur ec > 0 ->
      riverFxV1SetPopupBlur c fxo (fxWord (fxPopupBlur ec)) (fromIntegral (max 0 (fxPopupCornerRadius ec)))
    _ -> pure ()
  case (gFx g, effects cfg >>= fxBlurParams) of
    (Just fxo, Just bp) | gFxVersion g >= 4 ->
      riverFxV1SetBlurParameters c fxo (fromIntegral (max 1 (bpPasses bp))) (fromIntegral (max 1 (bpRadius bp)))
        (bpNoise bp) (bpBrightness bp) (bpContrast bp) (bpSaturation bp)
    _ -> pure ()
  let xconf = XConf { config = cfg, conn = c, globals = g, inputs = ch
                    , ipcPublish = maybe (const (pure ())) publishIPC ipcSrv
                    , ipcPublishWindows = maybe (const (pure ())) publishWindowsIPC ipcSrv }
      ws0 = applyRestoredLayouts (layoutHook cfg) (rsLayouts restored)
              (W.new (layoutHook cfg) (workspaces cfg) [SD nullObject (Rectangle 0 0 0 0)])
      st0 = XState
        { windowset = ws0, windowInfo = M.empty, outputs = M.empty, seats = M.empty
        , keyActions = M.empty, pointerActions = M.empty, pending = [], newWindows = []
        , outputsDirty = False, haveScreens = False, fullscreen = S.empty, needsCenter = S.empty, shownWindows = S.empty
        , anims = M.empty, shownPos = M.empty, shownTags = M.empty, animTick = False
        , drag = Nothing, sessionLocked = False, started = False
        , restoreState = rsWindows restored, restarting = False, restoreView = rsView restored
        , restoreOrder = rsOrder restored
        , borderWidths = M.empty
        , extensibleState = M.fromList [ (k, Left v) | (k, v) <- rsExt restored ]
        , registryGlobals = M.fromList [ (n, (i, v)) | (n, i, v) <- globalsList ]
        , loggingOut = Nothing, layerDefault = Nothing
        , inputDevices = M.empty, xkbKeyboards = M.empty, libinputDevices = M.empty
        , keymapState = NoKeymap, shadowMap = M.empty, retiredBuffers = S.empty }

  debug <- maybe False (`notElem` ["", "0"]) <$> lookupEnv "RIVERMONAD_DEBUG"
  r <- E.try (runX xconf st0 (mainLoop debug c ch))
  case r of
    Left RestartNow -> do
      void (E.try (removeFile pf) :: IO (Either E.IOException ()))
      closeConn c
      self <- currentExecutable
      executeFile self False [] Nothing
    Right _ -> pure ()
  where
    die' msg = hPutStrLn stderr ("rivermonad: " ++ msg) >> exitFailure

-- | Path of our own binary. After a recompile the running file has been
-- replaced, and Linux reports the old inode as "<path> (deleted)": exec the
-- new file at the same path instead.
currentExecutable :: IO FilePath
currentExecutable = do
  p <- getExecutablePath
  let suffix = " (deleted)"
  pure $ if suffix `isSuffixOf` p then take (length p - length suffix) p else p

-- | Read events until the sync callback fires, collecting the globals.
collectGlobals :: Conn -> ObjectId -> [(Word32, BC.ByteString, Word32)] -> IO [(Word32, BC.ByteString, Word32)]
collectGlobals c cb acc = do
  evs <- readEvents c
  let acc' = acc ++ [ (n, i, v) | EvWlRegistry _ (WlRegistryGlobal n i v) <- evs ]
      done = not (null [ () | EvWlCallback o _ <- evs, o == cb ])
  forM_ [ () | EvWlDisplay _ (WlDisplayError {}) <- evs ] $ \_ -> do
    hPutStrLn stderr "rivermonad: protocol error during startup"
    exitFailure
  if done then forgetObject c cb >> pure acc' else collectGlobals c cb acc'

-- | Read raw messages and decode those addressed to objects we know.
readEvents :: Conn -> IO [Event]
readEvents c = do
  msgs <- readMessages c
  fmap catMaybes $ mapM decodeOne msgs
  where
    decodeOne (RawMessage o op body) = do
      mi <- lookupInterface c o
      case mi >>= \i -> decodeEvent i o op of
        Nothing -> pure Nothing
        Just g -> case runGetOrFail g (BL.fromStrict body) of
          Left (_, _, err) -> do
            hPutStrLn stderr ("rivermonad: cannot decode event " ++ show op ++ " on " ++ show o ++ ": " ++ err)
            pure Nothing
          Right (_, _, (ev, news)) -> do
            mapM_ (uncurry (registerObject c)) news
            pure (Just ev)

-- | With @RIVERMONAD_DEBUG=1@ every event is logged to stderr.
mainLoop :: Bool -> Conn -> Chan Input -> X ()
mainLoop debug c ch = forever $ do
  inp <- io (readChan ch)
  case inp of
    InEvents evs -> forM_ evs $ \e -> do
      when debug $ io (hPutStrLn stderr ("<- " ++ show e))
      catchX (handleEvent e) (pure ())
    InDisconnected why -> io $ do
      hPutStrLn stderr ("rivermonad: lost connection to the compositor: " ++ why)
      exitFailure
    InRestart -> requestRestart
    InAction a -> queue (runIPCAction a)
    InQuit -> io exitSuccess
    InRun x -> queue x
  io (flush c)
