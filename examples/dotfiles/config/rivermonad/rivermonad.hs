-- ~/.config/rivermonad/rivermonad.hs (see examples/dotfiles/README.md)
--
-- Recompile with `rivermonad --recompile` or just press mod-q.
import Rivermonad
import qualified Rivermonad.StackSet as W

import Rivermonad.Actions.CycleWS
import Rivermonad.Hooks.InsertPosition
import Rivermonad.Hooks.ManageHelpers
import Rivermonad.Layout.NoBorders
import Rivermonad.Layout.Spacing
import Rivermonad.Layout.ThreeColumns
import Rivermonad.Layout.ToggleLayouts
import Rivermonad.Util.EZConfig
import Rivermonad.Util.NamedScratchpad
import Rivermonad.Util.SpawnOnce

main :: IO ()
main = rivermonad $ myConfig `additionalKeysP` myKeys

myConfig :: XConfig
myConfig = def
  { terminal           = "foot"
  , modMask            = mod4Mask            -- Super; use mod1Mask for Alt
  , borderWidth        = 2
  , normalBorderColor  = "#313244"
  , focusedBorderColor = "#cba6f7"
  , workspaces         = ["web", "code", "term"] ++ map show [4 .. 9 :: Int]
  , layoutHook         = myLayout
  , manageHook         = myManageHook
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
      -- lock after 10 minutes without input and before suspending (https://github.com/prietus/locklet;
      -- timings in ~/.config/locklet/config.json, "idle")
      spawnOnce "locklet idle"
      -- desktop widgets (https://github.com/prietus/hasklets), above the wallpaper
      spawnOnce "hasklets"
      spawnOnce "luna --background"   -- Borg backups (https://github.com/prietus/luna)
      -- GeoClue agent: authorizes apps asking for location (where-am-i, firefox...);
      -- without it GeoClue clients time out
      spawnOnce "/usr/lib/geoclue-2.0/demos/agent"
  }

myLayout :: Layout Window
myLayout = Layout $ toggleLayouts (noBorders Full) $ smartBorders $ gapsWithEdge 6 $
  tiled ||| Mirror tiled ||| ThreeColMid 1 (3 / 100) (1 / 2)
  where
    tiled = Tall 1 (3 / 100) (3 / 5)

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
  , appId =? "dev.hasklets.Settings"         -?> doCenterFloat   -- hasklets --config
  , title =? "Picture-in-Picture"            -?> doFloat
    -- Firefox opens these as independent windows (no parent):
  , isFirefox <&&> (title =? "Library" <||> title ^? "Page Info" <||> title =? "About Mozilla Firefox")
                                             -?> doCenterFloat
  , isFirefox                                -?> doShift "web"
  ]
  where
    -- the snap reports "firefox_firefox", the .deb "firefox"
    isFirefox = appId =? "firefox_firefox" <||> appId =? "firefox"

-- | Where hidden windows go: a workspace of their own, outside the
-- configured ones, so waymobar can count them (it skips it as a workspace,
-- like the scratchpads' NSP) and M-Left/Right skip it too.
hiddenTag :: WorkspaceId
hiddenTag = "hidden"

notHidden :: WSType
notHidden = WSIs ((/= hiddenTag) . W.tag)

-- | Hide the focused window (sway's scratchpad).
hideWindow :: X ()
hideWindow = withFocused $ \w -> do
  ws <- gets windowset
  let l = W.layout (W.workspace (W.current ws))
      -- created on demand, at the end so M-Tab never lands on it
      ensure s | W.tagMember hiddenTag s = s
               | otherwise = s { W.hidden = W.hidden s ++ [W.Workspace hiddenTag l Nothing] }
  windows (W.shiftWin hiddenTag w . ensure)

-- | Bring the most recently hidden window to this workspace and focus it.
unhideWindow :: X ()
unhideWindow = do
  ws <- gets windowset
  case concat [ W.integrate' (W.stack w) | w <- W.workspaces ws, W.tag w == hiddenTag ] of
    [] -> pure ()
    w : _ -> windows $ \s -> W.focusWindow w (W.shiftWin (W.currentTag s) w s)

myKeys :: [(String, X ())]
myKeys =
  [ ("M-b",         spawn "firefox")
  , ("M-z",         sendMessage ToggleLayout)
  , ("M-`",         namedScratchpadAction scratchpads "term")
    -- hide the focused window / bring the last hidden one back (sway's
    -- scratchpad); each M-o brings the next one
  , ("M-S-o",       hideWindow)
  , ("M-o",         unhideWindow)
  , ("M-<Right>",   moveTo Next notHidden)
  , ("M-<Left>",    moveTo Prev notHidden)
  , ("M-<Tab>",     toggleWS)
  , ("M-S-f",       withFocused float)
  , ("M-=",         incSpacing 1)
  , ("M--",         incSpacing (-1))
    -- the screenshot toolbar (https://github.com/prietus/shotlet), also the
    -- button in the bar:
    -- screen, window, region, recordings, timer; again closes it
  , ("M-S-s",       spawn "shotlet")
    -- lock the screen (locklet), also the padlock in the bar's side panel
  , ("M-S-l",       spawn "locklet")
    -- screenshots (~/Pictures/Screenshots + clipboard), see ~/.local/bin/shot
  , ("<Print>",     spawn "shot")              -- whole screen
  , ("S-<Print>",   spawn "shot region")       -- select a region
  , ("C-<Print>",   spawn "shot annotate")     -- region, then annotate in swappy
    -- Print Screen through macOS/UTM (Fn+P on a Drop ALT): a Mac turns it
    -- into F13, which xkb calls XF86Tools.
  ] ++ concat
  [ [ (m ++ "<XF86Tools>", a), (m ++ "<F13>", a) ]
  | (m, a) <- [ ("", spawn "shot"), ("S-", spawn "shot region"), ("C-", spawn "shot annotate")
              , ("M-", spawn "screenrec"), ("M-S-", spawn "screenrec region") ]
  ] ++
  [ ("M-<Print>",   spawn "screenrec")
  , ("M-S-<Print>", spawn "screenrec region")
    -- emoji picker: type "tree", Enter, and 🌳 is typed in the focused window
  , ("M-i",         spawn "emoji")
  , ("<XF86AudioRaiseVolume>", spawn "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")
  , ("<XF86AudioLowerVolume>", spawn "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")
  , ("<XF86AudioMute>",        spawn "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
  ]
