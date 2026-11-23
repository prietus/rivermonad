# IPC

rivermonad listens on a Unix socket for newline-delimited JSON, modelled on
niri's. Bars, scripts and tools read the state from it and send actions.

The socket is `$XDG_RUNTIME_DIR/rivermonad-$WAYLAND_DISPLAY.sock`, also
exported to the programs rivermonad starts as `RIVERMONAD_SOCKET`. From a
shell, `rivermonad --ipc REQUEST` sends one request and prints the replies:

```sh
rivermonad --ipc '"EventStream"'
rivermonad --ipc '{"Action":{"FocusWorkspace":"2"}}'
rivermonad --ipc '"Windows"'
```

## Requests

| Request | Reply |
|---|---|
| `"EventStream"` | the state now and on every change |
| `{"Action": A}` | runs an action |
| `"Actions"` | the names `{"Run": name}` accepts |
| `"Windows"` | the windows on screen with their geometry |

### `"EventStream"`

Replies `{"Ok":"Handled"}`, then one `{"State":{...}}` line every time
the state changes (and the current state at once):

```json
{"State":{
  "workspaces":[
    {"name":"web","idx":1,"output":"DP-1","focused":true,"visible":true,
     "windows":2,"layout":"Spacing Tall","extra":false},
    ...],
  "focused_output":"DP-1",
  "title":"README.md - nvim",
  "app_id":"foot",
  "keyboard_layout":"English (US)"}}
```

| Field | |
|---|---|
| `workspaces[].name`, `idx` | its name and its position (1-based, the configured ones first) |
| `workspaces[].output` | the output showing it, or `null` |
| `workspaces[].focused` | the focused workspace of the focused output |
| `workspaces[].visible` | shown on some output |
| `workspaces[].windows` | how many windows it has |
| `workspaces[].layout` | the layout's description |
| `workspaces[].extra` | not in the configured workspaces (the scratchpads' `NSP`, minimised windows' `hidden`): bars usually skip these |
| `focused_output` | the focused output's connector name |
| `title`, `app_id` | of the focused window, or `null` |
| `keyboard_layout` | the active xkb layout's name |
| `windows[]` | every window, workspace by workspace in stack order: `id`, `app_id`, `title`, `workspace`, `focused`, `floating`, `hidden` (minimised or a waiting scratchpad); for task bars |

### `{"Action": A}`

Replies `{"Ok":"Handled"}` and runs the action (or `{"Err":...}` if it is
not understood).

**Workspaces**

| A | |
|---|---|
| `{"FocusWorkspace":"3"}` | show the workspace (xmonad's `view`: on another output, focus that output) |
| `{"ViewWorkspace":"3"}` | show it on the focused output (xmonad's `greedyView`) |
| `"NextWorkspace"`, `"PrevWorkspace"` | the next / previous configured workspace (hidden ones skipped) |
| `"ToggleWorkspace"` | back to the workspace you were on before |
| `{"MoveToWorkspace":"3"}` | move the focused window there |

**The focused window and the layout**

| A | |
|---|---|
| `"FocusUp"`, `"FocusDown"`, `"FocusMaster"` | |
| `"SwapMaster"` | swap the focused window with the master |
| `"Close"` | close it |
| `"ToggleFloating"`, `"ToggleFullscreen"` | |
| `"NextLayout"`, `{"JumpToLayout":"Full"}` | |
| `"Shrink"`, `"Expand"`, `{"IncMaster":1}` | the master area smaller / bigger, more or fewer windows in it |

**Windows by criteria**, like sway's `[app_id=...]`. A criteria object has
at least one of `app_id` (exact), `title` (a part of it) and `id` (river's
identifier, as in the `"Windows"` reply); all the ones given must match.

| A | |
|---|---|
| `{"FocusWindow":{"app_id":"firefox"}}` | focus the next matching window, going to its workspace (a minimised one comes to the current workspace instead); repeat to cycle |
| `{"CloseWindow":{"title":"Picture-in-Picture"}}` | close every matching window |
| `{"MoveWindow":{"app_id":"mpv","workspace":"9"}}` | move every matching window to a workspace |

**Anything else**

| A | |
|---|---|
| `{"Spawn":"foot"}` | run a shell command |
| `{"Run":"M-g"}` | run an action of the configuration by name (see below) |
| `"NextKeyboardLayout"` | |
| `"Restart"` | restart rivermonad (as `rivermonad --restart`) |
| `"Logout"` | close every window gracefully, then end the session ([logging out](configuration.md#logging-out)) |

### Named actions: `"Actions"` and `{"Run": name}`

Any action of your configuration can be run from scripts by a name. List
them in `ipcActions`:

```haskell
  , ipcActions = [ ("bring-menu", bringMenu), ("resize-mode", resizeMode) ]
```

[`NamedActions`](modules/util/NamedActions.md)' `addDescrKeysP` adds every
described key by itself, under its key and under its description, so with
it every key of your cheat sheet is also an IPC action:

```sh
rivermonad --ipc '"Actions"'                     # {"Actions":["M-b","Firefox: focus it, or start it",...]}
rivermonad --ipc '{"Action":{"Run":"M-g"}}'
```

### Touchpad gestures

river does not give the window manager touchpad gestures, but tools that
read them from libinput can drive rivermonad through the IPC. With
[libinput-gestures](https://github.com/bulletmark/libinput-gestures)
(`~/.config/libinput-gestures.conf`; your user must be in the `input`
group):

```
gesture swipe left  3 rivermonad --ipc '{"Action":"NextWorkspace"}'
gesture swipe right 3 rivermonad --ipc '{"Action":"PrevWorkspace"}'
gesture swipe up    3 rivermonad --ipc '{"Action":{"Run":"M-g"}}'
gesture pinch in    2 rivermonad --ipc '{"Action":"ToggleFullscreen"}'
```

### `"Windows"`

One `{"Windows":[...]}` line: the windows on screen, topmost first, with
their geometry in the compositor's logical coordinates, borders included
(the coordinates grim and slurp use). For screenshot tools and the like.

```json
{"Windows":[
  {"id":"…","app_id":"foot","title":"~","workspace":"term","output":"DP-1",
   "x":6,"y":40,"width":1270,"height":1394,
   "focused":true,"floating":false,"fullscreen":false}]}
```

## Status lines for waybar

`rivermonad --status` prints the line of a configuration built with
`withStatusBar` (see [StatusBar](modules/hooks/StatusBar.md)) as JSON for
waybar's `custom` modules, once per change.
