-- | The default configuration, mirroring xmonad's defaults.
module Rivermonad.Config
  ( defaultConfig
  , defaultKeys
  , defaultMouseBindings
  , defaultLayout
  ) where

import Data.Bits ((.|.))
import qualified Data.Map.Strict as M

import Rivermonad.Core
import Rivermonad.Keysym
import Rivermonad.Layout
import Rivermonad.ManageHook (idHook)
import Rivermonad.Operations
import qualified Rivermonad.StackSet as W

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

defaultKeys :: XConfig -> M.Map (KeyMask, KeySym) (X ())
defaultKeys conf@XConfig { modMask = m } = M.fromList $
  [ ((m .|. shiftMask, xK_Return), spawn (terminal conf))
  , ((m, xK_p), spawn launcher)
  , ((m .|. shiftMask, xK_c), kill)
  , ((m, xK_space), sendMessage NextLayout)
  , ((m .|. shiftMask, xK_space), setLayout (layoutHook conf))
  , ((m, xK_n), refresh)
  , ((m, xK_Tab), windows W.focusDown)
  , ((m .|. shiftMask, xK_Tab), windows W.focusUp)
  , ((m, xK_j), windows W.focusDown)
  , ((m, xK_k), windows W.focusUp)
  , ((m, xK_m), windows W.focusMaster)
  , ((m, xK_Return), windows W.swapMaster)
  , ((m .|. shiftMask, xK_j), windows W.swapDown)
  , ((m .|. shiftMask, xK_k), windows W.swapUp)
  , ((m, xK_h), sendMessage Shrink)
  , ((m, xK_l), sendMessage Expand)
  , ((m, xK_t), withFocused sinkWindow)
  , ((m, xK_f), toggleFullscreen)
  , ((m, xK_comma), sendMessage (IncMasterN 1))
  , ((m, xK_period), sendMessage (IncMasterN (-1)))
  , ((m .|. shiftMask, xK_q), exitSession)
  , ((m, xK_q), recompileAndRestart)
  ]
  ++
  -- mod-[1..9]: switch to workspace N; mod-shift-[1..9]: move window to it
  [ ((m .|. mask, k), windows (f i))
  | (i, k) <- zip (workspaces conf) [xK_1, xK_2, xK_3, xK_4, xK_5, xK_6, xK_7, xK_8, xK_9]
  , (f, mask) <- [(W.greedyView, 0), (W.shift, shiftMask)] ]
  ++
  -- mod-{w,e,r}: focus screen 1, 2, 3; mod-shift-{w,e,r}: move window there
  [ ((m .|. mask, key), screenWorkspace sc >>= maybe (pure ()) (windows . f))
  | (key, sc) <- zip [xK_w, xK_e, xK_r] [0 ..]
  , (f, mask) <- [(W.view, 0), (W.shift, shiftMask)] ]

defaultMouseBindings :: XConfig -> M.Map (KeyMask, Button) (Window -> X ())
defaultMouseBindings XConfig { modMask = m } = M.fromList
  [ ((m, button1), mouseMoveWindow)
  , ((m, button2), \w -> focus w >> windows W.shiftMaster)
  , ((m, button3), mouseResizeWindow)
  ]
