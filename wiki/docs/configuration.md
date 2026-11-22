# Configuration

rivermonad reads `~/.config/rivermonad/rivermonad.hs`, a Haskell program
whose `main` calls `rivermonad` with a configuration:

```haskell
import Rivermonad

main :: IO ()
main = rivermonad def { terminal = "foot" }
```

Start from [examples/rivermonad.hs](https://github.com/prietus/rivermonad/blob/main/examples/rivermonad.hs)
or, for a whole desktop, from
[examples/dotfiles](https://github.com/prietus/rivermonad/tree/main/examples/dotfiles).

## Recompiling

`Super+Q` (`recompileAndRestart`) compiles the file in the background and,
if it builds, restarts into the new binary. A restart keeps each window's
workspace, its place in the stack and the focus, every workspace's layout
state and the [persistent extensible state](modules/util/ExtensibleState.md).
If the file does not build, nothing changes; see why with:

```sh
rivermonad --recompile
```

The compiled binary is `~/.cache/rivermonad/rivermonad-<arch>-linux`.
Modules of your own can live in `~/.config/rivermonad/lib/`.

| Command | What it does |
|---|---|
| `rivermonad` | run as the window manager of a river session |
| `rivermonad --recompile` | compile the configuration (exit status 1 if it fails) |
| `rivermonad --restart` | ask the running rivermonad to restart |
| `rivermonad --status` | status lines for waybar's custom modules (see [IPC](ipc.md)) |
| `rivermonad --ipc REQUEST` | send a JSON request to the [IPC socket](ipc.md) |
| `rivermonad --version` | print the version |

### Building against a checkout

If you'd rather not install the library globally, put an executable
`~/.config/rivermonad/build` script next to the configuration; rivermonad
runs it with the output binary as `$1`. To build against a checkout in
`~/src/rivermonad` (it also works when run by hand):

```sh
#!/bin/sh
set -e
CFG="$(cd "$(dirname "$0")" && pwd)"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/rivermonad"
OUT="${1:-$CACHE/rivermonad-$(uname -m)-linux}"
mkdir -p "$(dirname "$OUT")"
cd ~/src/rivermonad
exec env -u XDG_CACHE_HOME -u XDG_CONFIG_HOME cabal -v0 exec -- \
  ghc --make -package rivermonad "$CFG/rivermonad.hs" -i"$CFG/lib" -threaded -v0 \
  -outputdir "$(dirname "$OUT")/build" -o "$OUT"
```

## The settings

| Field | Default | |
|---|---|---|
| `terminal` | `"foot"` | for `Super+Shift+Enter` |
| `modMask` | `mod4Mask` | the modifier of the default keys: Super; `mod1Mask` for Alt |
| `borderWidth` | `2` | in pixels |
| `normalBorderColor`, `focusedBorderColor` | `"#dddddd"`, `"#ff0000"` | `"#rrggbb"` or `"#rrggbbaa"` |
| `workspaces` | `["1" .. "9"]` | their names, in order |
| `layoutHook` | `Tall ||| Mirror Tall ||| Full` | see [Layouts](layouts.md) |
| `manageHook` | `idHook` | rules for new windows, see [Manage hooks](managehooks.md) |
| `handleEventHook` | nothing | sees every Wayland event first; return `All False` to skip the default handling |
| `keys` | [the defaults](keys.md) | a map from `(KeyMask, KeySym)` to an action |
| `mouseBindings` | move, raise, resize | a map from `(KeyMask, Button)` to an action on the window |
| `startupHook` | nothing | runs at start and after every restart; use `spawnOnce` |
| `logHook` | nothing | runs after every change (focus, layout, workspace) |
| `focusFollowsMouse` | `True` | |
| `xcursorTheme` | `Nothing` | `Just ("Adwaita", 24)` |
| `allowTearing` | `True` | fullscreen windows that ask for it (games) present without vsync |
| `input` | system defaults | keyboard, touchpad and mouse, see [Input devices](input.md) |
| `shadows` | `Nothing` | drop shadows under windows, see below |

## Keys

Keys take xkbcommon keysyms (`xK_*`, the same names and values as in X11),
with the unshifted key plus `shiftMask`. The easy way is
[`EZConfig`](modules/util/EZConfig.md):

```haskell
main = rivermonad $ myConfig `additionalKeysP`
  [ ("M-b", spawn "firefox")
  , ("M-S-<Return>", spawn "foot")
  , ("<XF86AudioMute>", spawn "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
  ]
```

`M-` is the `modMask`, `S-` Shift, `C-` Control, `M1-`…`M5-` the mod masks
(`M1-` is Alt). Named keys go in angle brackets: `<Return>`, `<Tab>`,
`<Left>`, `<F1>`, `<Print>`, `<XF86AudioRaiseVolume>`...

Useful actions to bind:

| Action | |
|---|---|
| `spawn "cmd"` | run a shell command, detached |
| `kill` | close the focused window |
| `windows f` | change the window set: `W.focusDown`, `W.swapMaster`, `W.greedyView "3"`, `W.shift "3"`... |
| `sendMessage m` | tell the layout something: `Shrink`, `Expand`, `IncMasterN 1`, `NextLayout`, `JumpToLayout "Full"` |
| `withFocused f` | do something with the focused window: `withFocused float`, `withFocused sinkWindow` |
| `toggleFullscreen` | |
| `nextKeyboardLayout` | switch to the next of `kbLayout`'s layouts |
| `recompileAndRestart`, `restart` | |
| `exitSession`, `logoutGracefully` | see below |

Key sequences and modes (`Super+R`, then `h`/`l`) are in
[`Submap`](modules/actions/Submap.md); a fuzzel cheat sheet of your keys
in [`NamedActions`](modules/util/NamedActions.md).

## Logging out

`exitSession` ends the session at once: river closes every client.
`logoutGracefully` asks every window to close first, as if its close button
was clicked, so applications can save or ask; the session ends when the
last one is gone, and with a display manager you are back at the login
screen. If a window is still open after 10 seconds (an unsaved-changes
dialog, say) the logout is cancelled and that window is focused
(`logoutGracefullyWith` changes the timeout).

```haskell
myKeys = [ ("M-S-q", logoutGracefully) ]
```

The same is on the [IPC socket](ipc.md) (`"Logout"`) and in waymobar's
`logoutButton`.

## Shadows

Drop shadows, drawn by rivermonad as river decorations below windows. Only
under floating windows unless `shadowTiled = True` (under tiled windows
they darken their neighbours), and never in full screen:

```haskell
  , shadows = Just def { shadowRadius = 18, shadowOffset = (0, 5)
                       , shadowColor = "#000000", shadowOpacity = 0.5 }
```

## Tearing for games

A fullscreen window that asks for it (`wp_tearing_control`) makes its
output present without vsync, for the lowest latency, and back to vsync
when it leaves. Pair it with variable refresh rate (`adaptive_sync on` in
kanshi) on hardware that has it. `allowTearing = False` turns it off.

## Monitors

Resolution, refresh rate, scale and placement are river's, not the window
manager's: use [kanshi](https://sr.ht/~emersion/kanshi/) (the session
starts it) or `wlr-randr`. rivermonad gives each monitor a workspace, as
xmonad does: `Super+W/E/R` focus screen 1, 2, 3.

## Your own code

The configuration is Haskell, so anything goes. The extension points are
xmonad's: layouts in `X` (`doLayout`, `handleMessage`),
[`LayoutModifier`](modules/layout/LayoutModifier.md),
[`ExtensibleState`](modules/util/ExtensibleState.md), the manage, log and
event hooks, and `queue` to run something in the next manage sequence.
