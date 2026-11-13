{-# LANGUAGE OverloadedStrings #-}
-- | The protocol engine: turns river events into window set changes and
-- pushes the window set to river at the end of every manage sequence.
module Rivermonad.Engine
  ( handleEvent
  , requestRestart
  , saveRestartState
  , loadRestartState
  , restartStateFile
  , Restored (..)
  , runIPCAction
  , applyRestoredLayouts
  ) where

import qualified Control.Exception as E
import Control.Monad (forM_, unless, when, void)
import qualified Data.ByteString.Char8 as BC
import Data.Char (digitToInt, isHexDigit)
import Data.List (sortOn)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, isJust)
import Data.Monoid (Endo (..))
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Word (Word32)
import System.Directory (removeFile)
import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)

import Rivermonad.Core
import Rivermonad.Input (currentKeyboardLayout, handleInputEvent, nextKeyboardLayout, setupKeymap)
import qualified Rivermonad.JSON as J
import Rivermonad.Layout (ChangeLayout (..), JumpToLayout (..))
import Rivermonad.Operations
import Rivermonad.Shadows (drawShadows, dropShadow, handleShadowEvent, syncShadows)
import qualified Rivermonad.StackSet as W
import Rivermonad.Wayland.Protocol
import Rivermonad.Wayland.Wire

------------------------------------------------------------------------------
-- Dispatch

-- | Run the user's 'handleEventHook' first; it may veto default handling.
handleEvent :: Event -> X ()
handleEvent ev = do
  hook <- asks (handleEventHook . config)
  continue <- userCodeDef (All True) (hook ev)
  when (getAll continue || critical ev) (defaultHandler ev)
  where
    -- Skipping these would freeze or desynchronise the session.
    critical = \case
      EvWlDisplay {} -> True
      EvRiverWindowManagerV1 _ e -> case e of
        RiverWindowManagerV1ManageStart -> True
        RiverWindowManagerV1RenderStart -> True
        RiverWindowManagerV1Finished -> True
        RiverWindowManagerV1Unavailable -> True
        RiverWindowManagerV1Window _ -> True
        RiverWindowManagerV1Output _ -> True
        RiverWindowManagerV1Seat _ -> True
        _ -> False
      EvRiverWindowV1 _ RiverWindowV1Closed -> True
      EvRiverOutputV1 _ RiverOutputV1Removed -> True
      EvRiverSeatV1 _ RiverSeatV1Removed -> True
      _ -> False

defaultHandler :: Event -> X ()
defaultHandler ev = case ev of
  EvWlDisplay _ (WlDisplayError o code msg) -> io $ do
    hPutStrLn stderr ("rivermonad: protocol error on " ++ show o ++ " (code "
                      ++ show code ++ "): " ++ BC.unpack msg)
    exitFailure
  EvWlDisplay _ (WlDisplayDeleteId i) -> withConn (\c -> forgetObject c (ObjectId i))
  EvWlRegistry _ (WlRegistryGlobal n iface v) ->
    modify $ \s -> s { registryGlobals = M.insert n (iface, v) (registryGlobals s) }
  EvWlRegistry _ (WlRegistryGlobalRemove n) ->
    modify $ \s -> s { registryGlobals = M.delete n (registryGlobals s) }
  EvWlOutput o (WlOutputName n) ->
    modify $ \s -> s { outputs = M.map (\oi -> if fmap fst (oiWlOutput oi) == Just o
                                                then oi { oiName = Just (utf8 n) } else oi) (outputs s) }
  EvWlOutput {} -> pure ()
  EvWlCallback o _ -> withConn (\c -> forgetObject c o)
  EvRiverWindowManagerV1 _ e -> onManager e
  EvRiverWindowV1 w e -> onWindow w e
  EvRiverOutputV1 o e -> onOutput o e
  EvRiverSeatV1 s e -> onSeat s e
  EvRiverXkbBindingV1 b RiverXkbBindingV1Pressed -> do
    act <- gets (M.lookup b . keyActions)
    forM_ act queue'
  EvRiverXkbBindingV1 {} -> pure ()
  EvRiverPointerBindingV1 b RiverPointerBindingV1Pressed -> do
    act <- gets (M.lookup b . pointerActions)
    forM_ act $ \(seat, f) -> do
      pw <- gets (\st -> M.lookup seat (seats st) >>= siPointerWindow)
      forM_ pw (queue' . f)
  EvRiverPointerBindingV1 {} -> pure ()
  EvRiverXkbBindingsSeatV1 {} -> pure ()
  EvRiverLayerShellOutputV1 lo (RiverLayerShellOutputV1NonExclusiveArea x y w h) ->
    modify $ \st -> st
      { outputs = M.map (\oi -> if oiLayerShell oi == Just lo
                                  then oi { oiUsable = Just (Rectangle (fi x) (fi y) (fi w) (fi h)) }
                                  else oi) (outputs st)
      , outputsDirty = True }
  EvRiverLayerShellSeatV1 ls e -> do
    let focused = case e of
          RiverLayerShellSeatV1FocusNone -> False
          _ -> True
    modifySeats (\si -> if siLayerSeat si == Just ls
                          then si { siLayerFocus = focused
                                  -- force focus to be re-sent once the layer surface lets go
                                  , siFocused = if focused then siFocused si else Nothing }
                          else si)
  ev' -> do
    mine <- handleShadowEvent ev'
    unless mine (void (handleInputEvent ev'))
    -- Layout switches don't start a manage sequence: publish them now so
    -- bars follow (publishState only sends when something changed).
    case ev' of
      EvRiverXkbKeyboardV1 {} -> catchX publishState (pure ())
      _ -> pure ()

-- | Queue without sending manage_dirty: every event we queue from is
-- already followed by a manage_start.
queue' :: X () -> X ()
queue' a = modify $ \s -> s { pending = a : pending s }

-- | Wayland strings are UTF-8.
utf8 :: BC.ByteString -> String
utf8 = T.unpack . TE.decodeUtf8Lenient

withConn :: (Conn -> IO a) -> X a
withConn f = asks conn >>= io . f

fi :: (Integral a, Num b) => a -> b
fi = fromIntegral

modifySeats :: (SeatInfo -> SeatInfo) -> X ()
modifySeats f = modify $ \st -> st { seats = M.map f (seats st) }

modifyInfo :: Window -> (WindowInfo -> WindowInfo) -> X ()
modifyInfo w f = modify $ \st -> st { windowInfo = M.adjust f w (windowInfo st) }

------------------------------------------------------------------------------
-- river_window_manager_v1

onManager :: RiverWindowManagerV1Event -> X ()
onManager e = case e of
  RiverWindowManagerV1Unavailable -> io $ do
    hPutStrLn stderr "rivermonad: window management unavailable (is another window manager running?)"
    exitFailure
  RiverWindowManagerV1Finished -> do
    r <- gets restarting
    g <- asks globals
    withConn $ \c -> do
      riverWindowManagerV1Destroy c (gWm g)
      flush c
    io (if r then E.throwIO RestartNow else exitSuccess)
  RiverWindowManagerV1ManageStart -> onManageStart
  RiverWindowManagerV1RenderStart -> onRenderStart
  RiverWindowManagerV1SessionLocked -> modify $ \s -> s { sessionLocked = True }
  RiverWindowManagerV1SessionUnlocked -> modify $ \s -> s { sessionLocked = False }
  RiverWindowManagerV1Window w -> do
    node <- withConn (\c -> riverWindowV1GetNode c w)
    modify $ \s -> s { windowInfo = M.insert w (emptyWindowInfo node) (windowInfo s)
                     , newWindows = w : newWindows s }
  RiverWindowManagerV1Output o -> do
    ls <- asks (gLayerShell . globals)
    lso <- case ls of
      Just l -> Just <$> withConn (\c -> riverLayerShellV1GetOutput c l o)
      Nothing -> pure Nothing
    modify $ \s -> s { outputs = M.insert o (OutputInfo Nothing Nothing Nothing lso Nothing Nothing False) (outputs s)
                     , outputsDirty = True }
  RiverWindowManagerV1Seat s -> setupSeat s

------------------------------------------------------------------------------
-- river_window_v1

onWindow :: Window -> RiverWindowV1Event -> X ()
onWindow w e = case e of
  RiverWindowV1Closed -> windowClosed w
  RiverWindowV1DimensionsHint a b c d ->
    modifyInfo w (\i -> i { wiMinSize = (fi a, fi b), wiMaxSize = (fi c, fi d) })
  RiverWindowV1Dimensions width height ->
    modifyInfo w (\i -> i { wiDims = Just (fi width, fi height) })
  RiverWindowV1AppId s -> modifyInfo w (\i -> i { wiAppId = utf8 s })
  RiverWindowV1Title s -> modifyInfo w (\i -> i { wiTitle = utf8 s })
  RiverWindowV1Identifier s -> modifyInfo w (\i -> i { wiIdentifier = utf8 s })
  RiverWindowV1Parent p ->
    modifyInfo w (\i -> i { wiParent = if p == nullObject then Nothing else Just p })
  RiverWindowV1DecorationHint h -> modifyInfo w (\i -> i { wiDecoration = fi h })
  RiverWindowV1PresentationHint h ->
    modifyInfo w (\i -> i { wiAsync = h == riverOutputV1PresentationModeAsync })
  RiverWindowV1FullscreenRequested _ ->
    modify $ \s -> s { fullscreen = S.insert w (fullscreen s) }
  RiverWindowV1ExitFullscreenRequested ->
    modify $ \s -> s { fullscreen = S.delete w (fullscreen s) }
  -- Client side decorations asking to be dragged: only for floating windows.
  RiverWindowV1PointerMoveRequested _ -> queue' (whenFloating w (startDrag DragMove w))
  RiverWindowV1PointerResizeRequested _ _ -> queue' (whenFloating w (startDrag DragResize w))
  _ -> pure ()

whenFloating :: Window -> X () -> X ()
whenFloating w a = do
  f <- gets (M.member w . W.floating . windowset)
  when f a

windowClosed :: Window -> X ()
windowClosed w = do
  info <- gets (M.lookup w . windowInfo)
  dropShadow w
  withConn $ \c -> do
    forM_ info $ \i -> riverNodeV1Destroy c (wiNode i)
    riverWindowV1Destroy c w
  d <- gets drag
  when (fmap dragWindow d == Just w) (queue' endDrag)
  modify $ \s -> s
    { windowInfo = M.delete w (windowInfo s)
    , windowset = W.delete w (windowset s)
    , fullscreen = S.delete w (fullscreen s)
    , needsCenter = S.delete w (needsCenter s)
    , newWindows = filter (/= w) (newWindows s)
    , seats = M.map (\si -> si { siPointerWindow = if siPointerWindow si == Just w then Nothing else siPointerWindow si
                               , siFocused = if siFocused si == Just (Just w) then Nothing else siFocused si })
                    (seats s)
    }

------------------------------------------------------------------------------
-- river_output_v1

onOutput :: ObjectId -> RiverOutputV1Event -> X ()
onOutput o e = case e of
  RiverOutputV1Removed -> do
    oi <- gets (M.lookup o . outputs)
    withConn $ \c -> do
      forM_ (oi >>= oiLayerShell) (riverLayerShellOutputV1Destroy c)
      forM_ (oi >>= oiWlOutput) $ \(wo, v) ->
        if v >= 3 then wlOutputRelease c wo else forgetObject c wo
      riverOutputV1Destroy c o
    modify $ \s -> s { outputs = M.delete o (outputs s), outputsDirty = True
                     , layerDefault = if layerDefault s == Just o then Nothing else layerDefault s }
  -- Bind the matching wl_output to learn the connector name (for bars).
  RiverOutputV1WlOutput name -> do
    gl <- gets (M.lookup name . registryGlobals)
    reg <- asks (gRegistry . globals)
    forM_ gl $ \(iface, v) -> when (iface == wlOutputInterface) $ do
      let v' = min v 4
      wo <- withConn (\c -> wlRegistryBind c reg name wlOutputInterface v')
      modify $ \s -> s { outputs = M.adjust (\i -> i { oiWlOutput = Just (wo, v') }) o (outputs s) }
  RiverOutputV1Position x y -> upd (\i -> i { oiPos = Just (fi x, fi y) })
  RiverOutputV1Dimensions w h -> upd (\i -> i { oiDims = Just (fi w, fi h) })
  _ -> pure ()
  where
    upd f = modify $ \s -> s { outputs = M.adjust f o (outputs s), outputsDirty = True }

-- | Rebuild the screens of the window set from river's outputs.
reconcileOutputs :: X ()
reconcileOutputs = do
  outs <- gets outputs
  let sds = sortOn (\sd -> let r = sdRect sd in (rect_x r, rect_y r))
              [ SD o (fromMaybe full (oiUsable oi))
              | (o, oi) <- M.toList outs
              , Just (x, y) <- [oiPos oi]
              , Just (w, h) <- [oiDims oi]
              , let full = Rectangle x y w h ]
  had <- gets haveScreens
  ws <- gets windowset
  case sds of
    [] -> modify $ \s -> s { haveScreens = False, outputsDirty = False }
    _ -> do
      let old = map (sdOutput . W.screenDetail) (W.screens ws)
          ws'
            | had && S.fromList old == S.fromList (map sdOutput sds) =
                -- Same outputs, maybe resized/moved/new bars: update in place.
                let byOut = M.fromList [ (sdOutput sd, sd) | sd <- sds ]
                    upd scr = scr { W.screenDetail = M.findWithDefault (W.screenDetail scr) (sdOutput (W.screenDetail scr)) byOut }
                in ws { W.current = upd (W.current ws), W.visible = map upd (W.visible ws) }
            | otherwise = rescreen sds ws
      modify $ \s -> s { windowset = ws', haveScreens = True, outputsDirty = False }
      rv <- gets restoreView
      forM_ rv $ \t -> do
        windows (W.view t)
        modify $ \s -> s { restoreView = Nothing }

rescreen :: [ScreenDetail] -> WindowSet -> WindowSet
rescreen sds ws =
  let cur = W.currentTag ws
      allWs = map W.workspace (W.screens ws) ++ W.hidden ws
      n = min (length sds) (length allWs)
      (shown, rest) = splitAt n allWs
  in case zipWith3 W.Screen shown [0 ..] (take n sds) of
       (a : as) -> W.view cur ws { W.current = a, W.visible = as, W.hidden = rest }
       [] -> ws

------------------------------------------------------------------------------
-- river_seat_v1

setupSeat :: ObjectId -> X ()
setupSeat s = do
  cfg <- asks config
  g <- asks globals
  c <- asks conn
  ks <- io $ mapM (\((m, k), act) -> (\b -> (b, act)) <$> riverXkbBindingsV1GetXkbBinding c (gXkb g) s k m)
                  (M.toList (keys cfg cfg))
  ps <- io $ mapM (\((m, btn), act) -> (\b -> (b, (s, act))) <$> riverSeatV1GetPointerBinding c s btn m)
                  (M.toList (mouseBindings cfg cfg))
  lseat <- io $ mapM (\l -> riverLayerShellV1GetSeat c l s) (gLayerShell g)
  modify $ \st -> st
    { keyActions = M.union (M.fromList ks) (keyActions st)
    , pointerActions = M.union (M.fromList ps) (pointerActions st)
    , seats = M.insert s SeatInfo
        { siBindings = map fst ks ++ map fst ps
        , siEnabled = False
        , siPointerWindow = Nothing
        , siPointerPos = Nothing
        , siPosAtLayout = Nothing
        , siFocused = Nothing
        , siLayerSeat = lseat
        , siLayerFocus = False
        } (seats st)
    }

onSeat :: ObjectId -> RiverSeatV1Event -> X ()
onSeat s e = case e of
  RiverSeatV1Removed -> do
    si <- gets (M.lookup s . seats)
    ka <- gets keyActions
    withConn $ \c -> do
      forM_ si $ \i -> do
        forM_ (siBindings i) $ \b ->
          if M.member b ka then riverXkbBindingV1Destroy c b else riverPointerBindingV1Destroy c b
        forM_ (siLayerSeat i) (riverLayerShellSeatV1Destroy c)
      riverSeatV1Destroy c s
    let bs = maybe S.empty (S.fromList . siBindings) si
    modify $ \st -> st
      { seats = M.delete s (seats st)
      , keyActions = M.withoutKeys (keyActions st) bs
      , pointerActions = M.withoutKeys (pointerActions st) bs }
  RiverSeatV1PointerEnter w -> do
    upd (\i -> i { siPointerWindow = Just w })
    ffm <- asks (focusFollowsMouse . config)
    when ffm $ queue' $ do
      -- Only follow the pointer if it really moved: windows sliding under a
      -- still pointer (after a layout change) must not steal the focus.
      -- No reference position yet (startup, restart) means no real movement.
      moved <- gets (maybe False (\i -> isJust (siPosAtLayout i) && siPointerPos i /= siPosAtLayout i)
                       . M.lookup s . seats)
      dragging <- gets (isJust . drag)
      when (moved && not dragging) (focus w)
  RiverSeatV1PointerLeave -> upd (\i -> i { siPointerWindow = Nothing })
  RiverSeatV1WindowInteraction w -> queue' (focus w)
  RiverSeatV1PointerPosition x y -> upd (\i -> i { siPointerPos = Just (fi x, fi y) })
  RiverSeatV1OpDelta dx dy -> updateDrag (fi dx, fi dy)
  RiverSeatV1OpRelease -> queue' endDrag
  _ -> pure ()
  where
    upd f = modify $ \st -> st { seats = M.adjust f s (seats st) }

------------------------------------------------------------------------------
-- Manage sequence

-- | Whatever happens while reacting, the sequence is always finished: an
-- unfinished sequence would freeze the whole session.
onManageStart :: X ()
onManageStart = do
  catchX manageBody (pure ())
  g <- asks globals
  withConn (\c -> riverWindowManagerV1ManageFinish c (gWm g))
  catchX publishState (pure ())
  r <- gets restarting
  when r $ do
    saveRestartState
    withConn (\c -> riverWindowManagerV1Stop c (gWm g))

manageBody :: X ()
manageBody = do
  dirty <- gets outputsDirty
  when dirty reconcileOutputs
  enableSeats
  st <- gets started
  unless st $ do
    modify $ \s -> s { started = True }
    setupKeymap
    hook <- asks (startupHook . config)
    void (userCode hook)
  new <- gets (reverse . newWindows)
  modify $ \s -> s { newWindows = [] }
  mapM_ manageWindow new
  reorderRestored
  runPending
  checkLogout
  lh <- asks (logHook . config)
  void (userCode lh)
  applyManage

runPending :: X ()
runPending = do
  ps <- gets (reverse . pending)
  modify $ \s -> s { pending = [] }
  unless (null ps) $ do
    mapM_ userCode ps
    runPending

enableSeats :: X ()
enableSeats = do
  ss <- gets seats
  ka <- gets keyActions
  c <- asks conn
  cur <- asks (xcursorTheme . config)
  v <- asks (gWmVersion . globals)
  forM_ (M.toList ss) $ \(s, si) -> unless (siEnabled si) $ do
    io $ forM_ (siBindings si) $ \b ->
      if M.member b ka then riverXkbBindingV1Enable c b else riverPointerBindingV1Enable c b
    when (v >= 2) $ forM_ cur $ \(name, size) ->
      io (riverSeatV1SetXcursorTheme c s (BC.pack name) (fi size))
  modify $ \st -> st { seats = M.map (\si -> si { siEnabled = True }) (seats st) }

-- | Run a new window through the restart state or the manage hook.
manageWindow :: Window -> X ()
manageWindow w = do
  minfo <- gets (M.lookup w . windowInfo)
  forM_ minfo $ \info -> do
    c <- asks conn
    -- No title bars: ask for server side decorations (we only draw borders)
    -- unless the client cannot live without its own.
    let ssd = wiDecoration info /= 0
    io $ do
      if ssd then riverWindowV1UseSsd c w else riverWindowV1UseCsd c w
      riverWindowV1SetCapabilities c w riverWindowV1CapabilitiesFullscreen
    modifyInfo w (\i -> i { wiManaged = True, wiDecoSent = Just ssd })
    restore <- gets (M.lookup (wiIdentifier info) . restoreState)
    case restore of
      Just (t, mr) -> do
        modify $ \s -> s { restoreState = M.delete (wiIdentifier info) (restoreState s) }
        windows $ \ws ->
          let ws0 = W.insertUp w ws
              -- Workspaces created at runtime (e.g. the scratchpad one) come back too.
              ws' = if W.tagMember t ws0 then ws0
                    else ws0 { W.hidden = W.hidden ws0 ++ [W.Workspace t (W.layout (W.workspace (W.current ws0))) Nothing] }
              ws'' = W.shiftWin t w ws'
          in maybe ws'' (\(a, b, cc, d) -> W.float w (W.RationalRect a b cc d) ws'') mr
      Nothing -> do
        let (mw, mh) = wiMinSize info
            (xw, xh) = wiMaxSize info
            fixed = xw > 0 && xh > 0 && mw == xw && mh == xh
            shouldFloat = isJust (wiParent info) || fixed
        when shouldFloat $
          modify $ \s -> s { needsCenter = S.insert w (needsCenter s) }
        let f | shouldFloat = W.float w (W.RationalRect (1 / 4) (1 / 4) (1 / 2) (1 / 2)) . W.insertUp w
              | otherwise = W.insertUp w
        mh' <- asks (manageHook . config)
        g <- appEndo <$> userCodeDef (Endo id) (runQuery mh' w)
        windows (g . f)

-- | After a restart, windows come back in river's order; put each workspace
-- back in the saved order with the saved focus. Unknown windows go last.
reorderRestored :: X ()
reorderRestored = do
  order <- gets restoreOrder
  unless (M.null order) $ do
    infos <- gets windowInfo
    let key w = M.lookup w infos >>= \i -> M.lookup (wiIdentifier i) order
        fix wsp = case W.stack wsp of
          Nothing -> wsp
          Just st ->
            let sorted = sortOn (\w -> maybe (maxBound :: Int) fst (key w)) (W.integrate st)
                foc = case [ w | w <- sorted, Just (_, True) <- [key w] ] of
                  (f : _) -> f
                  [] -> W.focus st
                (before, after) = break (== foc) sorted
            in wsp { W.stack = Just (W.Stack foc (reverse before) (drop 1 after)) }
    windows (W.mapWorkspace fix)
    pendingRestore <- gets restoreState
    when (M.null pendingRestore) $ modify $ \s -> s { restoreOrder = M.empty }

-- | Push the window set to the compositor. Must run inside a manage sequence.
applyManage :: X ()
applyManage = do
  have <- gets haveScreens
  -- Layout modifiers (e.g. noBorders) set these again while laying out.
  modify $ \s -> s { borderWidths = M.empty }
  when have $ do
    c <- asks conn
    cfg <- asks config
    ws <- gets windowset
    fs <- gets fullscreen
    centre <- gets needsCenter
    let flt = W.floating ws
        focused = W.peek ws
        normalC = parseColor (normalBorderColor cfg)
        focusC = parseColor (focusedBorderColor cfg)

        place sd w r tiled = do
          minfo <- gets (M.lookup w . windowInfo)
          override <- gets (M.lookup w . borderWidths)
          let bw = fromMaybe (borderWidth cfg) override
          forM_ minfo $ \i -> do
            let fsOut = if S.member w fs then Just (sdOutput sd) else Nothing
                Rectangle rx ry rw rh = r
                cw = max 1 (rw - 2 * bw)
                ch = max 1 (rh - 2 * bw)
                -- New floats pick their own size; they get centred at render time.
                size = if S.member w centre && not tiled then (0, 0) else (cw, ch)
                edges = if tiled then 15 else 0
            i' <- case fsOut of
              Just o -> do
                when (wiFullscreen i /= Just o) $ io $ do
                  riverWindowV1Fullscreen c w o
                  riverWindowV1InformFullscreen c w
                pure i { wiFullscreen = Just o }
              Nothing -> do
                let wasFs = isJust (wiFullscreen i)
                when wasFs $ io $ do
                  riverWindowV1ExitFullscreen c w
                  riverWindowV1InformNotFullscreen c w
                let prev = if wasFs then Nothing else wiProposed i
                when (prev /= Just size) $
                  io (riverWindowV1ProposeDimensions c w (fi (fst size)) (fi (snd size)))
                when (wiTiled i /= Just edges) $
                  io (riverWindowV1SetTiled c w (fi edges))
                unless (S.member w centre && not tiled) $
                  io (riverNodeV1SetPosition c (wiNode i) (fi (rx + bw)) (fi (ry + bw)))
                pure i { wiFullscreen = Nothing, wiProposed = Just size, wiTiled = Just edges }
            let (r', g', b', a') = if Just w == focused then focusC else normalC
            io $ do
              riverWindowV1SetBorders c w (if bw > 0 then 15 else 0) (fi (max 0 bw)) r' g' b' a'
              riverWindowV1Show c w
            modifyInfo w (const i' { wiGeom = if isJust fsOut then wiGeom i else Just r })

    visibleWins <- fmap concat $ mapM (\scr -> do
      let sd = W.screenDetail scr
          wsp = W.workspace scr
          allW = W.integrate' (W.stack wsp)
          floats = [ (w, fromRationalRect (sdRect sd) rr) | w <- allW, Just rr <- [M.lookup w flt] ]
          tiledWs = wsp { W.stack = W.stack wsp >>= W.filter (`M.notMember` flt) }
      (tiled, ml') <- userCodeDef ([], Nothing) (runLayout tiledWs (sdRect sd))
      forM_ ml' $ \l' -> setLayoutOf (W.tag wsp) l'
      let
          -- Tiled windows the layout chose not to show (e.g. under Full) are hidden.
          shownTiled = S.fromList (map fst tiled)
      forM_ tiled $ \(w, r) -> place sd w r True
      forM_ floats $ \(w, r) -> place sd w r False
      -- Stacking: tiled, floats (focused float last), fullscreen on top.
      let order = map fst tiled
                  ++ filter (/= fromMaybe nullObject focused) (map fst floats)
                  ++ [ f | Just f <- [focused], f `elem` map fst floats ]
          order' = filter (`S.notMember` fs) order ++ filter (`S.member` fs) order
      infos <- gets windowInfo
      io $ forM_ order' $ \w -> forM_ (M.lookup w infos) (riverNodeV1PlaceTop c . wiNode)
      let hiddenHere = [ w | w <- allW, M.notMember w flt, S.notMember w shownTiled ]
      io $ mapM_ (riverWindowV1Hide c) hiddenHere
      pure (filter (`notElem` hiddenHere) allW)) (W.screens ws)

    -- Windows on hidden workspaces.
    let visSet = S.fromList visibleWins
    io $ forM_ (concatMap (W.integrate' . W.stack) (W.hidden ws)) $ \w ->
      unless (S.member w visSet) (riverWindowV1Hide c w)

    -- Layer surfaces that don't pick an output (notifications, launchers,
    -- bars started without one) open on the focused screen.
    let curOut = sdOutput (W.screenDetail (W.current ws))
    lso <- gets (\st -> M.lookup curOut (outputs st) >>= oiLayerShell)
    prevDefault <- gets layerDefault
    forM_ lso $ \l -> when (prevDefault /= Just curOut) $ do
      io (riverLayerShellOutputV1SetDefault c l)
      modify $ \st -> st { layerDefault = Just curOut }

    -- Keyboard focus.
    ss <- gets seats
    forM_ (M.toList ss) $ \(s, si) ->
      unless (siLayerFocus si || siFocused si == Just focused) $ do
        io $ maybe (riverSeatV1ClearFocus c s) (riverSeatV1FocusWindow c s) focused
        modify $ \st -> st { seats = M.adjust (\x -> x { siFocused = Just focused }) s (seats st) }

  -- Remember where the pointer was when this layout was applied.
  modifySeats (\si -> si { siPosAtLayout = siPointerPos si })
  updatePresentation
  catchX syncShadows (pure ())

-- | Tearing: an output presents asynchronously (no vsync) only while a
-- window that asked for it is fullscreen on it and shown; everything else
-- is vsync. Rendering state, so valid in manage and render sequences.
updatePresentation :: X ()
updatePresentation = do
  allowed <- asks (allowTearing . config)
  v <- asks (gWmVersion . globals)
  when (v >= 4) $ do
    c <- asks conn
    ws <- gets windowset
    infos <- gets windowInfo
    have <- gets haveScreens
    let shown = S.fromList [ w | have, scr <- W.screens ws, w <- W.integrate' (W.stack (W.workspace scr)) ]
        wantsAsync o = allowed && or
          [ True | (w, i) <- M.toList infos, S.member w shown, wiAsync i, wiFullscreen i == Just o ]
    outs <- gets outputs
    forM_ (M.toList outs) $ \(o, oi) -> do
      let want = wantsAsync o
      when (want /= oiAsync oi) $ do
        io $ riverOutputV1SetPresentationMode c o
          (if want then riverOutputV1PresentationModeAsync else riverOutputV1PresentationModeVsync)
        modify $ \st -> st { outputs = M.adjust (\x -> x { oiAsync = want }) o (outputs st) }

------------------------------------------------------------------------------
-- Render sequence

onRenderStart :: X ()
onRenderStart = do
  catchX renderBody (pure ())
  catchX drawShadows (pure ())
  g <- asks globals
  withConn (\c -> riverWindowManagerV1RenderFinish c (gWm g))

renderBody :: X ()
renderBody = do
  -- A presentation hint arrives right before a render sequence.
  updatePresentation
  c <- asks conn
  bw <- asks (borderWidth . config)
  centre <- gets needsCenter
  infos <- gets windowInfo
  ws <- gets windowset
  forM_ (S.toList centre) $ \w -> case M.lookup w infos of
    Just i | Just (dw, dh) <- wiDims i, M.member w (W.floating ws) -> do
      let Rectangle sx sy sw sh = sdRect (screenOfWindow w ws)
          -- A window that picked a size bigger than the screen (a GTK file
          -- chooser on a small or scaled output) is shrunk to fit.
          fw = min sw (dw + 2 * bw)
          fh = min sh (dh + 2 * bw)
          x = sx + (sw - fw) `div` 2
          y = sy + (sh - fh) `div` 2
          fits = fw == dw + 2 * bw && fh == dh + 2 * bw
      setFloatGeometry w (Rectangle x y fw fh)
      io (riverNodeV1SetPosition c (wiNode i) (fi (x + bw)) (fi (y + bw)))
      modify $ \s -> s { needsCenter = S.delete w (needsCenter s) }
      -- Its proposal was (0,0). The next manage sequence proposes the size
      -- of the float: nothing to send if the window fits, the shrunk size
      -- (in a manage sequence asked for right now) if it does not.
      modifyInfo w (\i' -> i' { wiProposed = Just (dw, dh) })
      unless fits $ do
        wm <- asks (gWm . globals)
        io (riverWindowManagerV1ManageDirty c wm)
    Just _ | not (M.member w (W.floating ws)) ->
      modify $ \s -> s { needsCenter = S.delete w (needsCenter s) }
    _ -> pure ()

------------------------------------------------------------------------------
-- Colours

-- | Parse "#rrggbb" / "#rrggbbaa" into premultiplied 32-bit RGBA components.
parseColor :: String -> (Word32, Word32, Word32, Word32)
parseColor ('#' : hex)
  | all isHexDigit hex, length hex `elem` [6, 8] =
      let byte i = digitToInt (hex !! i) * 16 + digitToInt (hex !! (i + 1))
          a = if length hex == 8 then byte 6 else 255
          pm v = fromIntegral (v * a `div` 255) * 0x01010101
      in (pm (byte 0), pm (byte 2), pm (byte 4), fromIntegral a * 0x01010101)
parseColor _ = (0xffffffff, 0, 0, 0xffffffff)

------------------------------------------------------------------------------
-- Restart

-- | Ask for a restart at the end of the next manage sequence.
requestRestart :: X ()
requestRestart = do
  modify $ \s -> s { restarting = True }
  g <- asks globals
  withConn (\c -> riverWindowManagerV1ManageDirty c (gWm g))

restartStateFile :: IO FilePath
restartStateFile = do
  dir <- fromMaybe "/tmp" <$> lookupEnv "XDG_RUNTIME_DIR"
  disp <- fromMaybe "wayland-0" <$> lookupEnv "WAYLAND_DISPLAY"
  pure (dir </> ("rivermonad-" ++ map (\ch -> if ch == '/' then '_' else ch) disp ++ ".state"))

type FloatS = Maybe (Rational, Rational, Rational, Rational)

-- | What survives a restart: the current workspace, each window's workspace
-- and floating geometry (by river identifier), every workspace's layout and
-- the persistent extensible state.
type SavedState = (WorkspaceId, [(String, WorkspaceId, FloatS, Int, Bool)], [(WorkspaceId, String)], [(String, String)])

data Restored = Restored
  { rsView    :: Maybe WorkspaceId
  , rsWindows :: M.Map String (WorkspaceId, FloatS)
  , rsOrder   :: M.Map String (Int, Bool)
  , rsLayouts :: [(WorkspaceId, String)]
  , rsExt     :: [(String, String)]
  }

saveRestartState :: X ()
saveRestartState = do
  ws <- gets windowset
  infos <- gets windowInfo
  ext <- gets extensibleState
  let entries =
        [ ( wiIdentifier i, W.tag wsp
          , fmap (\(W.RationalRect a b c d) -> (a, b, c, d)) (M.lookup w (W.floating ws))
          , pos, Just w == fmap W.focus (W.stack wsp) )
        | wsp <- W.workspaces ws
        , (pos, w) <- zip [0 ..] (W.integrate' (W.stack wsp))
        , Just i <- [M.lookup w infos]
        , not (null (wiIdentifier i)) ]
      layouts = [ (W.tag wsp, show (W.layout wsp)) | wsp <- W.workspaces ws ]
      exts = [ (k, v) | (k, e) <- M.toList ext
                      , Just v <- [case e of
                                     Left str -> Just str
                                     Right (PersistentExtension x) -> Just (show x)
                                     Right (StateExtension _) -> Nothing] ]
      saved = (W.currentTag ws, entries, layouts, exts) :: SavedState
  path <- io restartStateFile
  io $ void (E.try (writeFile path (show saved)) :: IO (Either E.IOException ()))

loadRestartState :: IO Restored
loadRestartState = do
  path <- restartStateFile
  r <- E.try (readFile path >>= \s -> length s `seq` pure s) :: IO (Either E.IOException String)
  _ <- E.try (removeFile path) :: IO (Either E.IOException ())
  pure $ case r of
    Right s | [(saved, "")] <- reads s ->
      let (cur, es, ls, xs) = saved :: SavedState
      in Restored (Just cur) (M.fromList [ (ident, (t, mr)) | (ident, t, mr, _, _) <- es ])
                  (M.fromList [ (ident, (p, f)) | (ident, _, _, p, f) <- es ]) ls xs
    _ -> Restored Nothing M.empty M.empty [] []

-- | Re-apply saved layouts (parsed with the configured layout as template;
-- if the configuration changed and they no longer parse, keep the default).
applyRestoredLayouts :: Layout Window -> [(WorkspaceId, String)] -> WindowSet -> WindowSet
applyRestoredLayouts template saved = W.mapWorkspace $ \wsp ->
  case lookup (W.tag wsp) saved >>= parse of
    Just l -> wsp { W.layout = l }
    Nothing -> wsp
  where
    parse str = case readsLayout template str of
      [(l, rest)] | all (== ' ') rest -> Just l
      _ -> Nothing

------------------------------------------------------------------------------
-- IPC

-- | Run an action requested on the IPC socket (inside a manage sequence).
runIPCAction :: IPCAction -> X ()
runIPCAction a = case a of
  IPCFocusWorkspace t -> windows (W.view t)
  IPCGreedyViewWorkspace t -> windows (W.greedyView t)
  IPCNextLayout -> sendMessage NextLayout
  IPCJumpToLayout n -> sendMessage (JumpToLayout n)
  IPCFocusUp -> windows W.focusUp
  IPCFocusDown -> windows W.focusDown
  IPCRestart -> requestRestart
  IPCNextKeyboardLayout -> nextKeyboardLayout
  IPCLogout -> logoutGracefully
  IPCLogoutCheck n -> logoutTimedOut n

-- | Publish the state to IPC subscribers (they only get it when it changes).
--
-- @{"State":{"workspaces":[...],"focused_output":...,"title":...,"app_id":...}}@
-- Each workspace: name, idx (1-based, configuration order first), output
-- (connector name or null), focused, visible, windows, layout, extra (not
-- in the configured workspaces, e.g. the scratchpad one).
publishState :: X ()
publishState = do
  ws <- gets windowset
  infos <- gets windowInfo
  outs <- gets outputs
  tags <- asks (workspaces . config)
  publish <- asks ipcPublish
  have <- gets haveScreens
  kbl <- currentKeyboardLayout
  let outName sd = M.lookup (sdOutput sd) outs >>= oiName
      shownOn = M.fromList [ (W.tag (W.workspace s), outName (W.screenDetail s)) | have, s <- W.screens ws ]
      extras = [ W.tag w | w <- W.workspaces ws, W.tag w `notElem` tags ]
      ordered = tags ++ extras
      byTag = M.fromList [ (W.tag w, w) | w <- W.workspaces ws ]
      wsJson i t = do
        w <- M.lookup t byTag
        pure $ J.obj
          [ ("name", J.str t)
          , ("idx", J.JNum (fromIntegral (i :: Int)))
          , ("output", maybe J.JNull J.str (M.lookup t shownOn >>= id))
          , ("focused", J.JBool (have && t == W.currentTag ws))
          , ("visible", J.JBool (M.member t shownOn))
          , ("windows", J.JNum (fromIntegral (length (W.integrate' (W.stack w)))))
          , ("layout", J.str (description (W.layout w)))
          , ("extra", J.JBool (t `notElem` tags)) ]
      focusedInfo = W.peek ws >>= \w -> M.lookup w infos
      state = J.obj [ ("State", J.obj
        [ ("workspaces", J.JArr [ j | (i, t) <- zip [1 ..] ordered, Just j <- [wsJson i t] ])
        , ("focused_output", maybe J.JNull J.str (if have then outName (W.screenDetail (W.current ws)) else Nothing))
        , ("title", maybe J.JNull (J.str . wiTitle) focusedInfo)
        , ("app_id", maybe J.JNull (J.str . wiAppId) focusedInfo)
        , ("keyboard_layout", maybe J.JNull J.str kbl) ]) ]
  io (publish (J.renderUtf8 state))
