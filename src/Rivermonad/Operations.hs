{-# LANGUAGE ScopedTypeVariables #-}
-- | Actions usable from key bindings, mouse bindings and hooks.
module Rivermonad.Operations
  ( windows, refresh, withFocused, focus
  , kill, killWindow
  , spawn, spawnPID
  , sendMessage, broadcastMessage, setLayout, setLayoutOf
  , float, sinkWindow, windowGeometry, setFloatGeometry, screenOfWindow
  , toggleFullscreen
  , mouseMoveWindow, mouseResizeWindow, startDrag, endDrag, updateDrag
  , screenWorkspace
  , restart, recompileAndRestart, exitSession
  , logoutGracefully, logoutGracefullyWith, checkLogout, logoutTimedOut
  , queue
  , toRationalRect, fromRationalRect
  ) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.Chan (writeChan)
import qualified Control.Exception as E
import Control.Monad (void, when, forM_)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, listToMaybe)
import qualified Data.Set as S
import System.Exit (ExitCode (..), exitSuccess)
import System.IO (hPutStrLn, stderr)
import System.Posix.Process (createSession, executeFile, exitImmediately, forkProcess, getProcessStatus)
import System.Posix.Types (ProcessID)

import Rivermonad.Core
import Rivermonad.Layout
import Rivermonad.Recompile (recompile)
import qualified Rivermonad.StackSet as W
import Rivermonad.Wayland.Protocol

-- | Modify the window set. The result is pushed to the compositor at the end
-- of the current manage sequence.
windows :: (WindowSet -> WindowSet) -> X ()
windows f = modify $ \s -> s { windowset = f (windowset s) }

-- | Re-apply the layout (it is re-applied after every manage sequence anyway).
refresh :: X ()
refresh = windows id

-- | Queue an action to run in the next manage sequence and make sure one
-- happens soon.
queue :: X () -> X ()
queue a = do
  modify $ \s -> s { pending = a : pending s }
  c <- asks conn
  wm <- asks (gWm . globals)
  io (riverWindowManagerV1ManageDirty c wm)

withFocused :: (Window -> X ()) -> X ()
withFocused f = withWindowSet $ \ws -> maybe (pure ()) f (W.peek ws)

focus :: Window -> X ()
focus w = withWindowSet $ \ws -> when (W.member w ws) (windows (W.focusWindow w))

kill :: X ()
kill = withFocused killWindow

-- | Politely ask a window to close.
killWindow :: Window -> X ()
killWindow w = do
  c <- asks conn
  io (riverWindowV1Close c w)

-- | Run a shell command, fully detached from the window manager.
spawn :: String -> X ()
spawn cmd = io $ void $ E.try @E.SomeException $ do
  pid <- forkProcess $ do
    _ <- createSession
    _ <- forkProcess (executeFile "/bin/sh" False ["-c", cmd] Nothing)
    exitImmediately ExitSuccess
  void (getProcessStatus True False pid)

-- | Run a shell command and return its pid (for "Rivermonad.Actions.SpawnOn").
-- The process is reaped in the background when it exits.
spawnPID :: String -> X (Maybe ProcessID)
spawnPID cmd = io $ do
  r <- E.try @E.SomeException $ forkProcess $ do
    _ <- createSession
    executeFile "/bin/sh" False ["-c", cmd] Nothing
  case r of
    Left _ -> pure Nothing
    Right pid -> do
      _ <- forkIO (void (E.try @E.SomeException (getProcessStatus True False pid)))
      pure (Just pid)

-- | Send a message to the layout of the current workspace.
sendMessage :: Message a => a -> X ()
sendMessage a = do
  ws <- gets windowset
  let wsp = W.workspace (W.current ws)
  r <- sendLayoutMessage (W.layout wsp) (SomeMessage a)
  mapM_ (setLayoutOf (W.tag wsp)) r

-- | Send a message to the layouts of every workspace.
broadcastMessage :: Message a => a -> X ()
broadcastMessage a = do
  wss <- gets (W.workspaces . windowset)
  mapM_ (\wsp -> handleMessage (W.layout wsp) (SomeMessage a) >>= mapM_ (setLayoutOf (W.tag wsp))) wss

setLayout :: Layout Window -> X ()
setLayout l = do
  t <- gets (W.currentTag . windowset)
  setLayoutOf t l

-- | Replace the layout of a given workspace.
setLayoutOf :: WorkspaceId -> Layout Window -> X ()
setLayoutOf t l = windows $ W.mapWorkspace (\wsp -> if W.tag wsp == t then wsp { W.layout = l } else wsp)

------------------------------------------------------------------------------
-- Geometry helpers

toRationalRect :: Rectangle -> Rectangle -> W.RationalRect
toRationalRect (Rectangle sx sy sw sh) (Rectangle x y w h) =
  W.RationalRect (fromIntegral (x - sx) / fromIntegral (max 1 sw))
                 (fromIntegral (y - sy) / fromIntegral (max 1 sh))
                 (fromIntegral w / fromIntegral (max 1 sw))
                 (fromIntegral h / fromIntegral (max 1 sh))

fromRationalRect :: Rectangle -> W.RationalRect -> Rectangle
fromRationalRect (Rectangle sx sy sw sh) (W.RationalRect rx ry rw rh) =
  Rectangle (sx + floor (fromIntegral sw * rx)) (sy + floor (fromIntegral sh * ry))
            (floor (fromIntegral sw * rw)) (floor (fromIntegral sh * rh))

-- | The screen showing the workspace of a window (or the current screen).
screenOfWindow :: Window -> WindowSet -> ScreenDetail
screenOfWindow w ws = fromMaybe (W.screenDetail (W.current ws)) $ do
  t <- W.findTag w ws
  listToMaybe [ W.screenDetail s | s <- W.screens ws, W.tag (W.workspace s) == t ]

-- | Last known geometry of a window (borders included).
windowGeometry :: Window -> X (Maybe Rectangle)
windowGeometry w = do
  ws <- gets windowset
  infos <- gets windowInfo
  cfg <- asks config
  let bw = borderWidth cfg
      scr = sdRect (screenOfWindow w ws)
  pure $ case M.lookup w (W.floating ws) of
    Just rr -> Just (fromRationalRect scr rr)
    Nothing | Just g <- M.lookup w infos >>= wiGeom -> Just g
    Nothing -> do
      -- Never placed yet: centre a window of its current size.
      (dw, dh) <- M.lookup w infos >>= wiDims
      let fw = dw + 2 * bw
          fh = dh + 2 * bw
      pure (Rectangle (rect_x scr + (rect_width scr - fw) `div` 2)
                      (rect_y scr + (rect_height scr - fh) `div` 2) fw fh)

setFloatGeometry :: Window -> Rectangle -> X ()
setFloatGeometry w r = windows $ \ws -> W.float w (toRationalRect (sdRect (screenOfWindow w ws)) r) ws

-- | Make a window float at its current geometry.
float :: Window -> X ()
float w = do
  g <- windowGeometry w
  case g of
    Just r  -> setFloatGeometry w r
    Nothing -> do
      windows (W.float w (W.RationalRect (1 / 4) (1 / 4) (1 / 2) (1 / 2)))
      modify $ \s -> s { needsCenter = S.insert w (needsCenter s) }

sinkWindow :: Window -> X ()
sinkWindow = windows . W.sink

toggleFullscreen :: X ()
toggleFullscreen = withFocused $ \w -> modify $ \s ->
  s { fullscreen = if S.member w (fullscreen s) then S.delete w (fullscreen s) else S.insert w (fullscreen s) }

------------------------------------------------------------------------------
-- Interactive move / resize (pointer operations)

mouseMoveWindow, mouseResizeWindow :: Window -> X ()
mouseMoveWindow = startDrag DragMove
mouseResizeWindow = startDrag DragResize

-- | Start an interactive operation on the seat that triggered the binding.
startDrag :: DragKind -> Window -> X ()
startDrag kind w = do
  busy <- gets drag
  seat <- gets (listToMaybe . M.keys . seats)
  case (busy, seat) of
    (Nothing, Just s) -> do
      float w
      g <- windowGeometry w
      forM_ g $ \r -> do
        c <- asks conn
        io (riverSeatV1OpStartPointer c s)
        modify $ \st -> st { drag = Just (Drag kind w r (0, 0) s) }
        focus w
    _ -> pure ()

updateDrag :: (Int, Int) -> X ()
updateDrag (dx, dy) = do
  d <- gets drag
  forM_ d $ \dr -> do
    let Rectangle x y w h = dragStart dr
        r = case dragKind dr of
          DragMove   -> Rectangle (x + dx) (y + dy) w h
          DragResize -> Rectangle x y (max 50 (w + dx)) (max 50 (h + dy))
    modify $ \s -> s { drag = Just dr { dragDelta = (dx, dy) } }
    setFloatGeometry (dragWindow dr) r

endDrag :: X ()
endDrag = do
  d <- gets drag
  forM_ d $ \dr -> do
    c <- asks conn
    io (riverSeatV1OpEnd c (dragSeat dr))
    modify $ \s -> s { drag = Nothing }

------------------------------------------------------------------------------
-- Screens, session

screenWorkspace :: ScreenId -> X (Maybe WorkspaceId)
screenWorkspace sc = withWindowSet (pure . W.lookupWorkspace sc)

-- | Restart the window manager process. Windows stay open: river keeps them
-- alive while no window manager is connected.
restart :: X ()
restart = modify $ \s -> s { restarting = True }

-- | Recompile the user configuration in the background and restart if it
-- built successfully (the classic mod-q).
recompileAndRestart :: X ()
recompileAndRestart = do
  ch <- asks inputs
  void $ io $ forkIO $ do
    ok <- recompile False
    when ok (writeChan ch InRestart)

-- | Log out without losing work: ask every window to close (as if its close
-- button was clicked, so applications can save or ask), and end the
-- session once none is left. If some window is still open after 10
-- seconds (an unsaved-changes dialog, say), the logout is cancelled and
-- that window is focused, instead of killing it.
--
-- With a display manager (GDM, SDDM...) this goes back to the login screen.
logoutGracefully :: X ()
logoutGracefully = logoutGracefullyWith 10

-- | 'logoutGracefully' with another timeout, in seconds.
logoutGracefullyWith :: Int -> X ()
logoutGracefullyWith secs = do
  ws <- gets (M.keys . windowInfo)
  if null ws
    then exitSession
    else do
      n <- gets (maybe 1 (+ 1) . loggingOut)
      modify $ \s -> s { loggingOut = Just n }
      mapM_ killWindow ws
      ch <- asks inputs
      void $ io $ forkIO $ do
        threadDelay (secs * 1000000)
        writeChan ch (InAction (IPCLogoutCheck n))

-- | Called after every manage sequence: end the session once a graceful
-- logout has seen every window close.
checkLogout :: X ()
checkLogout = do
  lo <- gets loggingOut
  ws <- gets windowInfo
  when (lo /= Nothing && M.null ws) $ do
    modify $ \s -> s { loggingOut = Nothing }
    exitSession

-- | The logout timer of attempt @n@ ran out: cancel it if windows remain.
logoutTimedOut :: Int -> X ()
logoutTimedOut n = do
  lo <- gets loggingOut
  when (lo == Just n) $ do
    modify $ \s -> s { loggingOut = Nothing }
    infos <- gets windowInfo
    forM_ (listToMaybe (M.keys infos)) focus
    let names = [ if null (wiTitle i) then wiAppId i else wiTitle i | i <- M.elems infos ]
        msg = "Logout cancelled: " ++ show (length names) ++ " window(s) still open"
              ++ concatMap ("\n• " ++) (take 5 names)
    io (hPutStrLn stderr ("rivermonad: " ++ msg))
    spawn ("notify-send -a rivermonad 'Logout cancelled' " ++ shellQuote (drop 18 msg))
  where
    shellQuote s = "'" ++ concatMap (\c -> if c == '\'' then "'\\''" else [c]) s ++ "'"

-- | End the whole Wayland session (river exits, every client is closed).
exitSession :: X ()
exitSession = do
  g <- asks globals
  c <- asks conn
  if gWmVersion g >= 4
    then io (riverWindowManagerV1ExitSession c (gWm g))
    else io exitSuccess
