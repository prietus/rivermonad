-- | The default configuration, mirroring xmonad's defaults.
module Rivermonad.Config
  ( defaultConfig
  , defaultKeys
  , defaultKeysDescr
    -- * The cheat sheet
  , KeyRow
  , defaultKeysRows
  , defaultKeysMenu
  , keysMenu
  , helpKeys
  , keyName
  , defaultMouseBindings
  , defaultLayout
  ) where

import Data.Bits ((.&.), (.|.), complement)
import Data.Char (chr, toUpper)
import qualified Data.Map.Strict as M

import Rivermonad.Core
import Rivermonad.Keysym
import Rivermonad.Layout
import Rivermonad.ManageHook (idHook)
import Rivermonad.Operations
import qualified Rivermonad.StackSet as W
import Rivermonad.Util.Dmenu (menuArgs)

instance Default XConfig where
  def = defaultConfig

defaultConfig :: XConfig
defaultConfig = XConfig
  { terminal = "foot"
  , modMask = mod4Mask
  , borderWidth = 2
  , normalBorderColor = "#dddddd"
  , focusedBorderColor = "#ff0000"
  , workspaces = map show [1 .. 9 :: Int]
  , layoutHook = defaultLayout
  , manageHook = idHook
  , handleEventHook = const (pure (All True))
  , keys = defaultKeys
  , mouseBindings = defaultMouseBindings
  , startupHook = pure ()
  , logHook = pure ()
  , focusFollowsMouse = True
  , xcursorTheme = Nothing
  , allowTearing = True
  , input = def
  , shadows = Nothing
  , effects = Nothing
  , animations = Nothing
  , ipcActions = []
  }

defaultLayout :: Layout Window
defaultLayout = Layout (tiled ||| Mirror tiled ||| Full)
  where tiled = Tall 1 (3 / 100) (1 / 2)

-- | A launcher that exists on most Wayland setups.
launcher :: String
launcher = "if command -v fuzzel >/dev/null; then fuzzel;"
        ++ " elif command -v bemenu-run >/dev/null; then bemenu-run;"
        ++ " elif command -v wmenu-run >/dev/null; then wmenu-run; fi"

-- | The default keys. @mod-shift-\/@ (that is, @mod-?@) shows them in a
-- menu: see 'defaultKeysMenu'.
defaultKeys :: XConfig -> M.Map (KeyMask, KeySym) (X ())
defaultKeys conf = M.fromList [ (k, a) | (k, _, a) <- defaultKeysDescr conf ]

-- | The default keys, each with what it does.
defaultKeysDescr :: XConfig -> [((KeyMask, KeySym), String, X ())]
defaultKeysDescr conf = singleKeys conf
  ++ [ (k, d ++ " " ++ i, a) | (k, d, i, a) <- workspaceKeys conf ]
  ++ [ (k, d ++ " " ++ show (sc + 1), a) | (k, d, sc, a) <- screenKeys conf ]

singleKeys :: XConfig -> [((KeyMask, KeySym), String, X ())]
singleKeys conf@XConfig { modMask = m } =
  [ ((m .|. shiftMask, xK_Return), "Terminal (" ++ terminal conf ++ ")", spawn (terminal conf))
  , ((m, xK_p), "Launcher", spawn launcher)
  , ((m .|. shiftMask, xK_c), "Close the window", kill)
  , ((m, xK_space), "Next layout", sendMessage NextLayout)
  , ((m .|. shiftMask, xK_space), "Back to the first layout", setLayout (layoutHook conf))
  , ((m, xK_n), "Re-apply the layout", refresh)
  , ((m, xK_Tab), "Focus the next window", windows W.focusDown)
  , ((m .|. shiftMask, xK_Tab), "Focus the previous window", windows W.focusUp)
  , ((m, xK_j), "Focus the next window", windows W.focusDown)
  , ((m, xK_k), "Focus the previous window", windows W.focusUp)
  , ((m, xK_m), "Focus the master window", windows W.focusMaster)
  , ((m, xK_Return), "Swap the window with the master", windows W.swapMaster)
  , ((m .|. shiftMask, xK_j), "Swap the window with the next one", windows W.swapDown)
  , ((m .|. shiftMask, xK_k), "Swap the window with the previous one", windows W.swapUp)
  , ((m, xK_h), "Shrink the master area", sendMessage Shrink)
  , ((m, xK_l), "Expand the master area", sendMessage Expand)
  , ((m, xK_t), "Put a floating window back into tiling", withFocused sinkWindow)
  , ((m, xK_f), "Full screen (toggle)", toggleFullscreen)
  , ((m, xK_comma), "One more window in the master area", sendMessage (IncMasterN 1))
  , ((m, xK_period), "One fewer window in the master area", sendMessage (IncMasterN (-1)))
  , ((m, xK_q), "Recompile the configuration and restart", recompileAndRestart)
  , ((m .|. shiftMask, xK_q), "End the session", exitSession)
  ]
  ++ [ (k, "This cheat sheet", defaultKeysMenu) | k <- helpKeys conf ]

-- | The keys of the cheat sheet: @mod-shift-\/@, and @mod-shift-?@ for
-- whatever way the compositor reports that key.
helpKeys :: XConfig -> [(KeyMask, KeySym)]
helpKeys XConfig { modMask = m } = [(m .|. shiftMask, xK_slash), (m .|. shiftMask, xK_question)]

-- mod-[1..9]: switch to workspace N; mod-shift-[1..9]: move window to it
workspaceKeys :: XConfig -> [((KeyMask, KeySym), String, String, X ())]
workspaceKeys conf@XConfig { modMask = m } =
  [ ((m .|. mask, k), d, i, windows (f i))
  | (i, k) <- zip (workspaces conf) [xK_1, xK_2, xK_3, xK_4, xK_5, xK_6, xK_7, xK_8, xK_9]
  , (f, d, mask) <- [(W.greedyView, "Go to workspace", 0), (W.shift, "Move the window to workspace", shiftMask)] ]

-- mod-{w,e,r}: focus screen 1, 2, 3; mod-shift-{w,e,r}: move window there
screenKeys :: XConfig -> [((KeyMask, KeySym), String, Int, X ())]
screenKeys XConfig { modMask = m } =
  [ ((m .|. mask, key), d, sc, screenWorkspace (fromIntegral sc) >>= maybe (pure ()) (windows . f))
  | (key, sc) <- zip [xK_w, xK_e, xK_r] [0 ..]
  , (f, d, mask) <- [(W.view, "Focus screen", 0), (W.shift, "Move the window to screen", shiftMask)] ]

---------------------------------------------------------------------------
-- The cheat sheet

-- | A line of the cheat sheet: the keys, what they do, and the action run
-- when the line is picked.
type KeyRow = (String, String, X ())

-- | The default keys as lines of the cheat sheet, without the ones given
-- (those a configuration has replaced). The workspace and screen keys are
-- summed up in one line each.
defaultKeysRows :: XConfig -> [(KeyMask, KeySym)] -> [KeyRow]
defaultKeysRows conf@XConfig { modMask = m } hidden =
  [ (keyName conf k, d, a) | (k, d, a) <- merge (singleKeys conf), k `notElem` hidden ]
  ++ [ (name mask ++ range, d ++ " N", pure ())
     | range <- take 1 [ keyName conf (0, lo) ++ "…" ++ keyName conf (0, hi)
                       | ((_, lo), _, _, _) <- take 1 ws, ((_, hi), _, _, _) <- take 1 (reverse ws) ]
     , (d, mask) <- [("Go to workspace", 0), ("Move the window to workspace", shiftMask)] ]
  ++ [ (name mask ++ "w/e/r", d ++ " 1/2/3", pure ())
     | (d, mask) <- [("Focus screen", 0), ("Move the window to screen", shiftMask)] ]
  where
    ws = workspaceKeys conf
    name mask = keyName conf (m .|. mask, 0)
    -- "mod-shift-/" and "mod-shift-?" are the same key: one line
    merge ks = [ x | x@(k, _, _) <- ks, k `notElem` drop 1 (helpKeys conf) ]

-- | Show the default keys in a menu (fuzzel, bemenu or wmenu, the first
-- installed); typing filters them and Enter runs the one picked. Bound to
-- @mod-shift-\/@ by default. It lists the /defaults/: for a sheet that
-- also has your own keys, see "Rivermonad.Util.NamedActions".
defaultKeysMenu :: X ()
defaultKeysMenu = asks config >>= \conf -> keysMenu (defaultKeysRows conf [])

-- | Show lines of keys in a menu and run the action of the one picked.
keysMenu :: [KeyRow] -> X ()
keysMenu rows = menuArgs "sh" ["-c", script] (map fst entries) $ \c ->
  maybe (pure ()) id (lookup c entries)
  where
    kw = maximum (0 : [ length k | (k, _, _) <- rows ])
    entries = [ (k ++ replicate (kw - length k + 3) ' ' ++ d, a) | (k, d, a) <- rows ]
    width = show (max 40 (maximum (0 : map (length . fst) entries) + 4))
    lns = show (max 1 (min 30 (length entries)))
    script = "if command -v fuzzel >/dev/null; then exec fuzzel --dmenu --no-sort --prompt 'keys › ' --width " ++ width ++ " --lines " ++ lns ++ ";"
          ++ " elif command -v bemenu >/dev/null; then exec bemenu -i -p keys -l " ++ lns ++ ";"
          ++ " elif command -v wmenu >/dev/null; then exec wmenu -i -p keys -l " ++ lns ++ "; fi"

-- | A key as people say it: @Super+Shift+Return@. A key of 0 gives just
-- the modifiers, ending in @+@.
keyName :: XConfig -> (KeyMask, KeySym) -> String
keyName conf (mask, sym) = concatMap (++ "+") mods ++ key
  where
    m = modMask conf
    rest = if m /= 0 && mask .&. m == m then mask .&. complement m else mask
    mods = [ n | m /= 0, mask .&. m == m, n <- [modName m] ]
        ++ [ n | (b, n) <- [ (mod4Mask, "Super"), (controlMask, "Ctrl"), (mod1Mask, "Alt")
                           , (mod3Mask, "Mod3"), (mod5Mask, "AltGr"), (shiftMask, "Shift") ]
               , rest .&. b /= 0 ]
    modName x | x == mod4Mask = "Super"
              | x == mod1Mask = "Alt"
              | x == controlMask = "Ctrl"
              | otherwise = "Mod"
    key | sym == 0 = ""
        | sym == xK_space = "Space"
        | sym > 0x20 && sym < 0x7f = [chr (fromIntegral sym)]
        | otherwise = case [ n | (n, s) <- keysymNames, s == sym ] of
            ((c : cs) : _) -> toUpper c : cs
            _ -> "?"

defaultMouseBindings :: XConfig -> M.Map (KeyMask, Button) (Window -> X ())
defaultMouseBindings XConfig { modMask = m } = M.fromList
  [ ((m, button1), mouseMoveWindow)
  , ((m, button2), \w -> focus w >> windows W.shiftMaster)
  , ((m, button3), mouseResizeWindow)
  ]
