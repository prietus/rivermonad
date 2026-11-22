# Getting started

This walks you from nothing to a comfortable `rivermonad.hs`, in the spirit
of xmonad's tutorial. It assumes rivermonad is [installed](install.md) and
that you can log in to a **river + rivermonad** session.

## 1. The defaults

With no configuration file, rivermonad uses xmonad's defaults with **Super**
as the modifier: `Super+Shift+Enter` opens a terminal (`foot`),
`Super+P` a launcher (fuzzel, bemenu or wmenu, whichever exists),
`Super+J`/`Super+K` move the focus, `Super+Space` changes layout and
`Super+1…9` change workspace. The whole list is in [Default keys](keys.md).

## 2. A first configuration

Create `~/.config/rivermonad/rivermonad.hs`:

```haskell
import Rivermonad

main :: IO ()
main = rivermonad def
  { terminal    = "foot"
  , modMask     = mod4Mask     -- Super; mod1Mask for Alt
  , borderWidth = 2
  , focusedBorderColor = "#cba6f7"
  }
```

Press `Super+Q`. rivermonad compiles the file with ghc and, if it builds,
restarts into it, keeping every window where it was. If it does not build,
nothing changes and the error is in the output of

```sh
rivermonad --recompile
```

`def` is the default configuration; the record update changes only what you
write. Every field is described in [Configuration](configuration.md).

## 3. Your own keys

[`EZConfig`](modules/util/EZConfig.md) adds keys written as strings:
`M-` is your modifier, `S-` Shift, `C-` Control, `M1-` Alt, and special
keys go in angle brackets.

```haskell
import Rivermonad
import Rivermonad.Util.EZConfig

main :: IO ()
main = rivermonad $ myConfig `additionalKeysP` myKeys

myConfig :: XConfig
myConfig = def { terminal = "foot", modMask = mod4Mask }

myKeys :: [(String, X ())]
myKeys =
  [ ("M-b",     spawn "firefox")
  , ("<Print>", spawn "grim -g \"$(slurp)\" - | wl-copy")
  , ("<XF86AudioRaiseVolume>", spawn "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")
  , ("<XF86AudioLowerVolume>", spawn "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")
  ]
```

## 4. Layouts

A layout decides where tiled windows go. Combine several with `|||` and
cycle through them with `Super+Space`. Wrap them in modifiers for gaps or
no borders:

```haskell
import Rivermonad.Layout.NoBorders
import Rivermonad.Layout.Spacing
import Rivermonad.Layout.ThreeColumns

myLayout :: Layout Window
myLayout = Layout $ smartBorders $ gapsWithEdge 6 $
  tiled ||| Mirror tiled ||| ThreeColMid 1 (3/100) (1/2) ||| Full
  where
    tiled = Tall 1 (3/100) (3/5)   -- one master window, 3% steps, master takes 60%
```

and in the configuration, `layoutHook = myLayout`. Note the `Layout (...)`
around the combination, the one difference from xmonad here. More in
[Layouts](layouts.md).

## 5. Rules for windows

The manage hook runs once for every new window: send Firefox to the `web`
workspace, float dialogs and some programs.

```haskell
import Rivermonad.Hooks.ManageHelpers

myManageHook :: ManageHook
myManageHook = composeOne
  [ isDialog                -?> doCenterFloat
  , appId =? "pavucontrol"  -?> doCenterFloat
  , appId =? "firefox"      -?> doShift "web"
  ]
```

with `workspaces = ["web", "code", "term"] ++ map show [4 .. 9]` and
`manageHook = myManageHook`. To find a window's `appId` and `title`, focus
it and run `rivermonad --ipc '"EventStream"' | head -2`. More in
[Manage hooks](managehooks.md).

## 6. Starting programs

The bar, notifications and the wallpaper start from the `startupHook`.
[`spawnOnce`](modules/util/SpawnOnce.md) starts them once per session,
not again on every `Super+Q`:

```haskell
import Rivermonad.Util.SpawnOnce

  , startupHook = do
      spawnOnce "waymobar"
      spawnOnce "mako"
      spawnOnce "bgmonad"
```

## 7. Keyboard and touchpad

Layouts, key repeat, tap to click and the rest go in `input`:

```haskell
  , input = def
      { keyboard = def { kbLayout = "us,es", kbOptions = "grp:alt_shift_toggle,caps:escape"
                       , kbRepeat = Just (40, 250) }
      , touchpad = def { tapToClick = Just True, naturalScroll = Just True }
      }
```

See [Input devices](input.md).

## 8. Going further

- Browse the [modules](modules/index.md): scratchpads, `runOrRaise`,
  window menus, swallowing, more layouts.
- Set up [the whole desktop](desktop.md): bar, wallpaper, widgets,
  screenshots.
- The configuration the author uses, with all of this, is in
  [examples/dotfiles](https://github.com/prietus/rivermonad/tree/main/examples/dotfiles).
