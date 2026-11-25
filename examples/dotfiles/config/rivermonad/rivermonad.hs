-- ~/.config/rivermonad/rivermonad.hs (see examples/dotfiles/README.md)
--
-- Recompile with `rivermonad --recompile` or just press mod-q.
import Rivermonad
import qualified Rivermonad.StackSet as W

import Rivermonad.Actions.CopyWindow
import Rivermonad.Actions.CycleWS
import Rivermonad.Actions.Minimize
import Rivermonad.Actions.MostRecentlyUsed
import Rivermonad.Actions.Navigation2D
import Rivermonad.Actions.SpawnOn
import Rivermonad.Actions.Submap
import Rivermonad.Actions.UpdatePointer
import Rivermonad.Actions.WindowBringer
import Rivermonad.Actions.WindowGo
import Rivermonad.Hooks.InsertPosition
import Rivermonad.Hooks.ManageHelpers
import Rivermonad.Hooks.OnPropertyChange
import Rivermonad.Hooks.RefocusLast
import Rivermonad.Hooks.WindowSwallowing
import Rivermonad.Hooks.WorkspaceHistory
import Rivermonad.Layout.BinarySpacePartition
import Rivermonad.Layout.CenteredIfSingle
import Rivermonad.Layout.LimitWindows
import qualified Rivermonad.Layout.Magnifier as Mag
import Rivermonad.Layout.Maximize
import Rivermonad.Layout.MultiToggle (Transformer (..), mkToggle)
import qualified Rivermonad.Layout.MultiToggle as MT
import Rivermonad.Layout.NoBorders
import Rivermonad.Layout.Spacing
import Rivermonad.Layout.ThreeColumns
import Rivermonad.Layout.ToggleLayouts
import Rivermonad.Layout.TwoPane
import Rivermonad.Util.EZConfig
import Rivermonad.Util.NamedActions
import Rivermonad.Util.NamedScratchpad
import Rivermonad.Util.SpawnOnce

main :: IO ()
main = rivermonad $
  -- closing a window focuses the one you used before it
  refocusLast $
  -- Firefox's picture-in-picture window may get its title after it opened:
  -- float it then too
  onTitleChange (title =? "Picture-in-Picture" --> doFloat) $
  -- mpv, imv or zathura started from a terminal take its place until closed
  swallowWindows (appId =? "foot") (appId =? "mpv" <||> appId =? "imv" <||> appId =? "org.pwmt.zathura") $
  -- the keys, with a description; M-<F1> lists them in fuzzel
  addDescrKeysP "M-<F1>" myConfig myKeys

myConfig :: XConfig
myConfig = def
  { terminal           = "foot"
  , modMask            = mod4Mask            -- Super; use mod1Mask for Alt
  , borderWidth        = 2
  , normalBorderColor  = "#313244"
  , focusedBorderColor = "#cba6f7"
  , workspaces         = ["web", "code", "term"] ++ map show [4 .. 9 :: Int]
  , layoutHook         = myLayout
  , manageHook         = manageSpawn <> myManageHook
    -- windows slide to their place and workspaces slide in and out
  , animations         = Just def { animDuration = 200 }
    -- rounded corners, slightly translucent inactive windows and blur.
    -- Only on river-fx (https://github.com/prietus/river-fx); on plain
    -- river they do nothing
  , effects            = Just def { fxCornerRadius = 12, fxInactiveOpacity = 0.92, fxBlur = 1 }
  , logHook            = do
      workspaceHistoryHook
      mostRecentlyUsedHook
      -- the pointer follows keyboard focus changes, only as far as needed
      updatePointer (0.5, 0.5) (1, 1)
    -- US keys plus Spanish with AltGr (the right Option key on a Mac):
    -- AltGr+n = ñ, AltGr+' then a vowel = á é í ó ú, AltGr+? = ¿, AltGr+1 = ¡
  , input              = def { keyboard = def { kbLayout = "us", kbVariant = "altgr-intl" } }
  , shadows            = Just def          -- drop shadows under floating windows
  , startupHook        = do
      spawnOnce "waymobar"
      spawnOnce "mako"
      -- wallpaper: bgmonad (~/.config/bgmonad/bgmonad.hs). ~/.config/wallpaper is
      -- a link to the image; change it with
      --   ln -sfn /path/to/image ~/.config/wallpaper
      -- and bgmonad picks it up by itself. The plain, still alternative:
      --   spawnOnce "swaybg -m fill -i ~/.config/wallpaper"
      spawnOnce "bgmonad"
      -- clipboard history (M-c picks an entry), and the night light: warmer
      -- colours after sunset, where GeoClue says you are
      -- (~/.config/gammastep/config.ini; M-S-n switches it off and on)
      spawnOnce "wl-paste --watch cliphist store"
      spawnOnce "gammastep"
      -- asks for your password when an application needs administrator rights
      -- (Disks, date and time, package installers...); without an agent they fail
      spawnOnce "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
      -- lock after 10 minutes without input and before suspending (https://github.com/prietus/locklet;
      -- timings in ~/.config/locklet/config.json, "idle")
      spawnOnce "locklet idle"
      -- mail: background sync, notifications and the bar's envelope
      -- (https://github.com/prietus/orion)
      -- (not packaged: started only if it is installed)
      spawnOnce "command -v orion >/dev/null && exec orion daemon"
      -- desktop widgets (https://github.com/prietus/hasklets), above the wallpaper
      spawnOnce "hasklets"
      -- Borg backups (https://github.com/prietus/luna; not packaged). The AUR
      -- has an unrelated "luna": start it only if it is the Borg client.
      spawnOnce "l=$(command -v luna) && grep -qa BorgBase \"$l\" && exec luna --background"
      -- GeoClue agent: authorizes apps asking for location (where-am-i, firefox...);
      -- without it GeoClue clients time out
      spawnOnce "a=/usr/lib/geoclue-2.0/demos/agent; [ -x $a ] && exec $a"
  }

myLayout :: Layout Window
myLayout = Layout $ toggleLayouts (noBorders Full) $ smartBorders $ gapsWithEdge 6 $
  -- M-<Backspace> maximises a window over the rest; M-x / M-S-x mirror /
  -- reflect; M-S-z magnifies the focused window; M-[ / M-] show fewer /
  -- more windows (no limit until you lower it)
  maximize $ mkToggle [MIRROR, REFLECTX] $ Mag.magnifierOff $ limitWindows 99 $
  tiled ||| Mirror tiled ||| ThreeColMid 1 (3 / 100) (1 / 2) ||| emptyBSP ||| TwoPane (3 / 100) (1 / 2)
  where
    -- a window alone is centred at 60% of the width instead of stretched
    tiled = centeredIfSingle 0.6 1 (Tall 1 (3 / 100) (3 / 5))

scratchpads :: NamedScratchpads
scratchpads =
  [ NS "term" "foot --app-id scratchpad" (appId =? "scratchpad")
       (customFloating (W.RationalRect 0.1 0.1 0.8 0.6)) ]

myManageHook :: ManageHook
myManageHook = insertPosition Below Newer <> namedScratchpadManageHook scratchpads <> composeOne
  -- composeOne: the first matching rule wins, so floats go before doShift.
  -- Find a window's appId/title: focus it, then
  --   rivermonad --ipc '"EventStream"' | head -2
  [ isDialog                                 -?> doCenterFloat   -- windows with a parent
  , isFixedSize                              -?> doCenterFloat   -- min size = max size
  , appId =? "xdg-desktop-portal-gtk"        -?> doCenterFloat   -- open/save dialogs (snaps, portals)
  , appId =? "pavucontrol"                   -?> doCenterFloat
  , appId =? "polkit-gnome-authentication-agent-1" -?> doCenterFloat   -- password prompts
  , appId =? "dev.hasklets.Settings"         -?> doCenterFloat   -- hasklets --config
  , title =? "Picture-in-Picture"            -?> doFloat
    -- Firefox opens these as independent windows (no parent):
  , isFirefox <&&> (title =? "Library" <||> title ^? "Page Info" <||> title =? "About Mozilla Firefox")
                                             -?> doCenterFloat
  , isFirefox                                -?> doShift "web"
  ]

-- | The snap reports "firefox_firefox", the .deb "firefox".
isFirefox :: Query Bool
isFirefox = appId =? "firefox_firefox" <||> appId =? "firefox"

myKeys :: [(String, String, X ())]
myKeys =
  [ ("M-b",         "Firefox: focus it, or start it",       runOrRaise "firefox" isFirefox)
  , ("M-a",         "Overview of the workspaces (spacelet)", spawn "spacelet")
  , ("M-g",         "Go to a window (fuzzel)",              gotoMenu)
  , ("M-S-g",       "Bring a window here (fuzzel)",         bringMenu)
  , ("M-z",         "Full screen without borders (toggle)", sendMessage ToggleLayout)
  , ("M-<Backspace>", "Maximise the window (toggle)",       withFocused (sendMessage . maximizeRestore))
  , ("M-x",         "Mirror the layout (toggle)",           sendMessage (MT.Toggle MIRROR))
  , ("M-S-x",       "Reflect the layout left-right (toggle)", sendMessage (MT.Toggle REFLECTX))
  , ("M-C-r",       "Resize mode: h/l, r rotate, s swap; Esc", resizeMode)
  , ("M-S-z",       "Magnify the focused window (toggle)",  sendMessage Mag.Toggle)
  , ("M-[",         "Show one window fewer",                decreaseLimit)
  , ("M-]",         "Show one window more",                 increaseLimit)
    -- apps started from the launcher open on the workspace it was opened on,
    -- even if you move on while they load
  , ("M-p",         "Launcher (fuzzel)",                    spawnHere "fuzzel")
  , ("M-`",         "Scratchpad terminal",                  namedScratchpadAction scratchpads "term")
  , ("M-S-o",       "Hide the window",                      withFocused minimizeWindow)
  , ("M-o",         "Bring back the last hidden window",    withLastMinimized maximizeWindowAndFocus)
  , ("M-C-o",       "Bring back a hidden window (fuzzel)",  restoreMenu)
  , ("M-v",         "Window on every workspace",            windows copyToAll)
  , ("M-S-v",       "Window only on this workspace",        killAllOtherCopies)
  , ("M1-<Tab>",    "Previous window (anywhere)",           focusPreviousWindow)
  , ("M-C-w",       "Windows by recent use (fuzzel)",       mruMenu)
  , ("M-C-<Tab>",   "Workspaces by recent use (fuzzel)",    recentWorkspacesMenu)
  , ("M-<Right>",   "Next workspace",                       nextWS)
  , ("M-<Left>",    "Previous workspace",                   prevWS)
  , ("M-<Tab>",     "Last workspace",                       toggleWS)
  , ("M-C-<Left>",  "Focus the window to the left",         windowGo L)
  , ("M-C-<Right>", "Focus the window to the right",        windowGo R)
  , ("M-C-<Up>",    "Focus the window above",               windowGo U)
  , ("M-C-<Down>",  "Focus the window below",               windowGo D)
  , ("M-C-S-<Left>",  "Swap with the window to the left",   windowSwap L)
  , ("M-C-S-<Right>", "Swap with the window to the right",  windowSwap R)
  , ("M-C-S-<Up>",    "Swap with the window above",         windowSwap U)
  , ("M-C-S-<Down>",  "Swap with the window below",         windowSwap D)
  , ("M-S-f",       "Float the window",                     withFocused float)
  , ("M-=",         "Wider gaps",                           incSpacing 1)
  , ("M--",         "Narrower gaps",                        incSpacing (-1))
    -- the screenshot toolbar (shotlet), also the button in the bar
  , ("M-S-s",       "Screenshot toolbar (shotlet)",         spawn "shotlet")
  , ("M-S-l",       "Lock the screen",                      spawn "locklet")
  , ("M-i",         "Emoji picker",                         spawn "emoji")
  , ("M-c",         "Clipboard history (fuzzel)",           spawn clipboardMenu)
  , ("M-C-c",       "Clear the clipboard history",          spawn "cliphist wipe && notify-send -a Clipboard 'Clipboard history cleared'")
  , ("M-S-n",       "Night light off / on",                 spawn "pkill -USR1 -x gammastep")
  ] ++ concat
    -- screenshots (~/Pictures/Screenshots + clipboard), see ~/.local/bin/shot.
    -- Print Screen through macOS/UTM (Fn+P on a Drop ALT) arrives as F13,
    -- which xkb calls XF86Tools.
  [ [ (m ++ "<Print>", d, a), (m ++ "<XF86Tools>", d ++ " (Mac)", a), (m ++ "<F13>", d ++ " (Mac)", a) ]
  | (m, d, a) <- [ ("",     "Screenshot: whole screen",   spawn "shot")
                 , ("S-",   "Screenshot: region",         spawn "shot region")
                 , ("C-",   "Screenshot: region, annotate", spawn "shot annotate")
                 , ("M-",   "Record the screen (again: stop)", spawn "screenrec")
                 , ("M-S-", "Record a region (again: stop)",   spawn "screenrec region") ]
  ] ++
  [ ("<XF86AudioRaiseVolume>", "Volume up",   spawn "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")
  , ("<XF86AudioLowerVolume>", "Volume down", spawn "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")
  , ("<XF86AudioMute>",        "Mute",        spawn "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
  ]

-- | M-C-r: h/l (or the arrows) make the focused area smaller/bigger, r and
-- s rotate and swap the split in the BSP layout; Esc or Enter leaves.
resizeMode :: X ()
resizeMode = modeP myConfig
  [ ("h", sendMessage Shrink), ("l", sendMessage Expand)
  , ("<Left>", sendMessage Shrink), ("<Right>", sendMessage Expand)
  , ("r", sendMessage Rotate), ("s", sendMessage Swap)
  ]

-- | Pick an earlier clipboard entry in fuzzel; it becomes the clipboard
-- again, ready to paste.
clipboardMenu :: String
clipboardMenu = "cliphist list | fuzzel --dmenu --prompt 'clipboard › ' --width 60 | cliphist decode | wl-copy"
