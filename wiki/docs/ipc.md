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

### `{"Action": A}`

Replies `{"Ok":"Handled"}` and runs the action:

| A | |
|---|---|
| `{"FocusWorkspace":"3"}` | show the workspace (xmonad's `view`: on another output, focus that output) |
| `{"ViewWorkspace":"3"}` | show it on the focused output (xmonad's `greedyView`) |
| `"NextLayout"` | |
| `{"JumpToLayout":"Full"}` | |
| `"FocusUp"`, `"FocusDown"` | |
| `"NextKeyboardLayout"` | |
| `"Restart"` | restart rivermonad (as `rivermonad --restart`) |
| `"Logout"` | close every window gracefully, then end the session ([logging out](configuration.md#logging-out)) |

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
