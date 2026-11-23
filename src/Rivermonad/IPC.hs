-- | IPC socket, modelled after niri's: newline-delimited JSON requests.
--
-- * @"EventStream"@: reply @{"Ok":"Handled"}@, then one
--   @{"State":{...}}@ line whenever the state changes (see
--   'Rivermonad.Engine.publishState' for the fields).
-- * @{"Action":A}@: reply @{"Ok":"Handled"}@ and run A, where A is one of
--   @{"FocusWorkspace":"3"}@, @{"ViewWorkspace":"3"}@, @"NextLayout"@,
--   @{"JumpToLayout":"Full"}@, @"FocusUp"@, @"FocusDown"@, @"Restart"@,
--   @"Logout"@ (close every window, then end the session),
--   @"NextKeyboardLayout"@.
-- * @"Windows"@: reply with one @{"Windows":[...]}@ line, the windows on
--   screen with their geometry, topmost first (see
--   'Rivermonad.Engine.publishState'); for screenshot tools and the like.
--
-- The socket is @$XDG_RUNTIME_DIR/rivermonad-$WAYLAND_DISPLAY.sock@ and is
-- exported to children as @RIVERMONAD_SOCKET@.
module Rivermonad.IPC
  ( IPCServer
  , ipcSocketPath
  , startIPCServer
  , publishIPC
  , publishWindowsIPC
  , publishActionsIPC
  , runIPCClient
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan (Chan, writeChan)
import Control.Concurrent.MVar
import qualified Control.Exception as E
import Control.Monad (filterM, forever, unless, void)
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import Data.IORef
import Data.Maybe (fromMaybe)
import qualified Network.Socket as NS
import qualified Network.Socket.ByteString as NSB
import System.Directory (doesPathExist, removeFile)
import System.Environment (lookupEnv, setEnv)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (hFlush, hPutStrLn, stderr, stdout)

import Rivermonad.Core (IPCAction (..), Input (..), WindowCriteria (..))
import qualified Rivermonad.JSON as J

data IPCServer = IPCServer
  { srvSubs :: MVar [NS.Socket]
  , srvLast :: IORef B.ByteString
  , srvWindows :: IORef B.ByteString
  , srvActions :: IORef [String]
  }

-- | The socket of the rivermonad managing /this/ Wayland display, if it
-- exists; @RIVERMONAD_SOCKET@ only as a fallback. The variable alone is not
-- trusted: in a session nested inside another rivermonad it is inherited
-- from the outer one.
ipcSocketPath :: IO FilePath
ipcSocketPath = do
  own <- defaultPath
  ownExists <- doesPathExist own
  env <- lookupEnv "RIVERMONAD_SOCKET"
  pure $ case env of
    Just p | not ownExists, not (null p) -> p
    _ -> own

defaultPath :: IO FilePath
defaultPath = do
  dir <- fromMaybe "/tmp" <$> lookupEnv "XDG_RUNTIME_DIR"
  disp <- fromMaybe "wayland-0" <$> lookupEnv "WAYLAND_DISPLAY"
  pure (dir </> ("rivermonad-" ++ map (\c -> if c == '/' then '_' else c) disp ++ ".sock"))

startIPCServer :: Chan Input -> IO (Maybe IPCServer)
startIPCServer ch = do
  r <- E.try $ do
    path <- defaultPath
    _ <- E.try (removeFile path) :: IO (Either E.IOException ())
    sock <- NS.socket NS.AF_UNIX NS.Stream NS.defaultProtocol
    NS.withFdSocket sock NS.setCloseOnExecIfNeeded
    NS.bind sock (NS.SockAddrUnix path)
    NS.listen sock 16
    setEnv "RIVERMONAD_SOCKET" path
    srv <- IPCServer <$> newMVar [] <*> newIORef B.empty <*> newIORef (BC.pack "{\"Windows\":[]}") <*> newIORef []
    void $ forkIO $ forever $ do
      (client, _) <- NS.accept sock
      NS.withFdSocket client NS.setCloseOnExecIfNeeded
      void (forkIO (handleClient srv ch client))
    pure srv
  case r of
    Right srv -> pure (Just srv)
    Left e -> do
      hPutStrLn stderr ("rivermonad: IPC disabled: " ++ show (e :: E.SomeException))
      pure Nothing

handleClient :: IPCServer -> Chan Input -> NS.Socket -> IO ()
handleClient srv ch s = do
  line <- readLine s B.empty
  case line >>= J.parseUtf8 of
    Just (J.JStr "EventStream") ->
      -- Register under the lock so no state line is lost or duplicated.
      modifyMVar_ (srvSubs srv) $ \subs -> do
        lastLine <- readIORef (srvLast srv)
        ok <- sendLine s (J.renderUtf8 (J.obj [("Ok", J.str "Handled")]))
        ok' <- if ok && not (B.null lastLine) then sendRaw s lastLine else pure ok
        pure (if ok' then s : subs else subs)
    Just (J.JStr "Windows") -> do
      void (sendLine s =<< readIORef (srvWindows srv))
      NS.close s
    Just (J.JStr "Actions") -> do
      names <- readIORef (srvActions srv)
      void (sendLine s (J.renderUtf8 (J.obj [("Actions", J.JArr (map J.str names))])))
      NS.close s
    Just (J.JObj [("Action", a)]) | Just (IPCRun n) <- parseAction a -> do
      names <- readIORef (srvActions srv)
      if n `elem` names
        then writeChan ch (InAction (IPCRun n)) >> void (sendLine s (J.renderUtf8 (J.obj [("Ok", J.str "Handled")])))
        else void (sendLine s (J.renderUtf8 (J.obj [("Err", J.str ("no action called " ++ show n))])))
      NS.close s
    Just (J.JObj [("Action", a)]) | Just act <- parseAction a -> do
      writeChan ch (InAction act)
      void (sendLine s (J.renderUtf8 (J.obj [("Ok", J.str "Handled")])))
      NS.close s
    _ -> do
      void (sendLine s (J.renderUtf8 (J.obj [("Err", J.str "unknown request")])))
      NS.close s

parseAction :: J.JValue -> Maybe IPCAction
parseAction v = case v of
  J.JStr "NextLayout" -> Just IPCNextLayout
  J.JStr "FocusUp" -> Just IPCFocusUp
  J.JStr "FocusDown" -> Just IPCFocusDown
  J.JStr "Restart" -> Just IPCRestart
  J.JStr "NextKeyboardLayout" -> Just IPCNextKeyboardLayout
  J.JStr "Logout" -> Just IPCLogout
  J.JObj [("FocusWorkspace", J.JStr t)] -> Just (IPCFocusWorkspace t)
  J.JObj [("ViewWorkspace", J.JStr t)] -> Just (IPCGreedyViewWorkspace t)
  J.JObj [("JumpToLayout", J.JStr l)] -> Just (IPCJumpToLayout l)
  J.JStr "NextWorkspace" -> Just IPCNextWorkspace
  J.JStr "PrevWorkspace" -> Just IPCPrevWorkspace
  J.JStr "ToggleWorkspace" -> Just IPCToggleWorkspace
  J.JObj [("MoveToWorkspace", J.JStr t)] -> Just (IPCMoveToWorkspace t)
  J.JStr "Close" -> Just IPCClose
  J.JStr "ToggleFloating" -> Just IPCToggleFloating
  J.JStr "ToggleFullscreen" -> Just IPCToggleFullscreen
  J.JStr "FocusMaster" -> Just IPCFocusMaster
  J.JStr "SwapMaster" -> Just IPCSwapMaster
  J.JStr "Shrink" -> Just IPCShrink
  J.JStr "Expand" -> Just IPCExpand
  J.JObj [("IncMaster", J.JNum n)] -> Just (IPCIncMaster (round n))
  J.JObj [("FocusWindow", c)] -> IPCFocusWindow <$> criteria c
  J.JObj [("CloseWindow", c)] -> IPCCloseWindow <$> criteria c
  J.JObj [("MoveWindow", J.JObj fs)]
    | Just (J.JStr t) <- lookup "workspace" fs ->
        (`IPCMoveWindow` t) <$> criteria (J.JObj (filter ((/= "workspace") . fst) fs))
  J.JObj [("Spawn", J.JStr cmd)] -> Just (IPCSpawn cmd)
  J.JObj [("Run", J.JStr n)] -> Just (IPCRun n)
  _ -> Nothing

-- | @{"app_id":"foot","title":"vim","id":"..."}@: at least one of them.
criteria :: J.JValue -> Maybe WindowCriteria
criteria (J.JObj fs)
  | all ((`elem` ["app_id", "title", "id"]) . fst) fs
  , c@(WindowCriteria a t i) <- WindowCriteria (str "app_id") (str "title") (str "id")
  , a /= Nothing || t /= Nothing || i /= Nothing = Just c
  where
    str k = case lookup k fs of
      Just (J.JStr v) -> Just v
      _ -> Nothing
criteria _ = Nothing

-- | The names scripts can run with @{"Action":{"Run":NAME}}@, for the
-- @"Actions"@ request.
publishActionsIPC :: IPCServer -> [String] -> IO ()
publishActionsIPC srv = writeIORef (srvActions srv)

-- | Send a state line to every subscriber, if it changed.
publishIPC :: IPCServer -> B.ByteString -> IO ()
publishIPC srv body = do
  let line = body <> BC.pack "\n"
  prev <- readIORef (srvLast srv)
  unless (line == prev) $ modifyMVar_ (srvSubs srv) $ \subs -> do
    writeIORef (srvLast srv) line
    filterM (`sendRaw` line) subs

-- | Remember the reply to the next @"Windows"@ requests.
publishWindowsIPC :: IPCServer -> B.ByteString -> IO ()
publishWindowsIPC srv = writeIORef (srvWindows srv)

sendLine :: NS.Socket -> B.ByteString -> IO Bool
sendLine s b = sendRaw s (b <> BC.pack "\n")

sendRaw :: NS.Socket -> B.ByteString -> IO Bool
sendRaw s b = do
  r <- E.try (NSB.sendAll s b) :: IO (Either E.IOException ())
  case r of
    Right () -> pure True
    Left _ -> NS.close s >> pure False

-- | Read up to the first newline (at most 64 KiB).
readLine :: NS.Socket -> B.ByteString -> IO (Maybe B.ByteString)
readLine s acc
  | B.length acc > 65536 = pure Nothing
  | otherwise = case BC.elemIndex '\n' acc of
      Just i -> pure (Just (B.take i acc))
      Nothing -> do
        r <- E.try (NSB.recv s 4096) :: IO (Either E.IOException B.ByteString)
        case r of
          Right chunk | not (B.null chunk) -> readLine s (acc <> chunk)
          _ -> pure (if B.null acc then Nothing else Just acc)

-- | @rivermonad --ipc REQUEST@: send one request and print the replies
-- (an event stream keeps printing until interrupted).
runIPCClient :: String -> IO ()
runIPCClient req = do
  path <- ipcSocketPath
  r <- E.try $ E.bracket (NS.socket NS.AF_UNIX NS.Stream NS.defaultProtocol) NS.close $ \s -> do
    NS.connect s (NS.SockAddrUnix path)
    NSB.sendAll s (BC.pack (req ++ "\n"))
    let loop = do
          chunk <- NSB.recv s 4096
          unless (B.null chunk) $ do
            B.putStr chunk
            hFlush stdout
            loop
    loop
  case r of
    Right () -> pure ()
    Left e -> do
      hPutStrLn stderr ("rivermonad: cannot reach " ++ path ++ ": " ++ show (e :: E.IOException))
      exitFailure
