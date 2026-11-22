# Coming from xmonad

rivermonad keeps xmonad's model and API, so most of an `xmonad.hs` carries
over with a few renames.

| xmonad | rivermonad |
|---|---|
| `import XMonad` | `import Rivermonad` |
| `import qualified XMonad.StackSet as W` | `import qualified Rivermonad.StackSet as W` |
| `import XMonad.Util.EZConfig` | `import Rivermonad.Util.EZConfig` (and so on for every contrib module) |
| `main = xmonad def {...}` | `main = rivermonad def {...}` |
| `layoutHook = a ||| b` | `layoutHook = Layout (a ||| b)` |
| `className =? "Firefox"` | `appId =? "firefox"` (`className` is an alias of `appId`) |
| `modMask = mod1Mask` (the default) | the default is `mod4Mask`, Super |
| `dmenu_run` | `fuzzel`, `bemenu-run`, `wmenu-run` |
| `xmobar`, `dzen2` | [waymobar](https://github.com/prietus/waymobar), or waybar ([IPC](ipc.md)) |
| `XMonad.Prompt`, `GridSelect` | fuzzel menus: [`Dmenu`](modules/util/Dmenu.md), [`WindowBringer`](modules/actions/WindowBringer.md) |
| `~/.xmonad/xmonad.hs` | `~/.config/rivermonad/rivermonad.hs` |
| `xmonad --recompile`, `--restart` | `rivermonad --recompile`, `--restart` |

## What is different

- **xmonad-contrib does not compile against rivermonad** (it depends on
  X11). The [modules](modules/index.md) are ports, with the same names and
  mostly the same API. Modules that draw their own windows in X11
  (`Prompt`, `GridSelect`, `Tabbed`, decorations) are not ported; menus go
  through fuzzel.
- **Menus do not block.** In xmonad a dmenu call stops the window manager
  until you choose; in rivermonad the menu runs in the background and the
  choice is handed to a function: `menu options (\choice -> ...)`.
- **Floating windows** have no position of their own on Wayland, so new
  floating windows are centred at the size they ask for.
- **Restarts** recognise windows by river's stable identifier, so windows
  keep their workspace, place and focus.
- **Status bars** read the [IPC socket](ipc.md) instead of a pipe or X
  properties. `withStatusBar` and `PP` exist for a waybar `custom` module.
- **Monitors, keyboard repeat and the cursor** are configured differently:
  monitors with kanshi; keyboard and mice in the config's
  [`input`](input.md).
- **Things river does not offer** (yet): urgency hints, window opacity,
  HDR output, and noticing when a modifier key is released (an Alt-Tab that
  cycles while Alt is held). See the [FAQ](faq.md).
