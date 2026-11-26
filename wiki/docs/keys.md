# Default keys

The defaults are xmonad's, with `M` = the `modMask`, which is **Super**
(`mod4Mask`) by default (xmonad uses Alt). Add or replace keys with
[`EZConfig`](modules/util/EZConfig.md).

`M-S-/` (that is, `M-?`) shows this table in a menu (fuzzel, bemenu or
wmenu, the first installed): type to filter it, and Enter runs the key
picked. It lists the defaults; describe your own keys with
[`NamedActions`](modules/util/NamedActions.md) and the same menu shows them
too, followed by the defaults they have not replaced.

| Keys | Action |
|---|---|
| `M-S-Return` | start the terminal (`terminal`) |
| `M-p` | start a launcher: fuzzel, bemenu-run or wmenu-run, the first installed |
| `M-S-c` | close the focused window |
| `M-Space` | next layout |
| `M-S-Space` | back to the first layout (`layoutHook`) |
| `M-n` | re-apply the layout |
| `M-Tab`, `M-j` | focus the next window |
| `M-S-Tab`, `M-k` | focus the previous window |
| `M-m` | focus the master window |
| `M-Return` | swap the focused window with the master |
| `M-S-j`, `M-S-k` | swap the focused window with the next / previous one |
| `M-h`, `M-l` | shrink / expand the master area |
| `M-t` | put a floating window back into tiling (all of them: [`sinkAll`](modules/actions/WithAll.md)) |
| `M-f` | full screen (toggle) |
| `M-,`, `M-.` | one more / one fewer window in the master area |
| `M-1` … `M-9` | go to workspace N |
| `M-S-1` … `M-S-9` | move the focused window to workspace N |
| `M-w`, `M-e`, `M-r` | focus screen 1, 2, 3 |
| `M-S-w`, `M-S-e`, `M-S-r` | move the focused window to screen 1, 2, 3 |
| `M-q` | recompile the configuration and restart |
| `M-S-q` | end the session (see [logging out](configuration.md#logging-out)) |
| `M-S-/` | this cheat sheet, in a menu (`defaultKeysMenu`) |

## Mouse

| Buttons | Action |
|---|---|
| `M-button1` (drag) | move the window; it becomes floating |
| `M-button2` | focus the window and make it master |
| `M-button3` (drag) | resize the window; it becomes floating |

Focus follows the mouse (`focusFollowsMouse = True`), but only when the
pointer really moves: windows sliding under a still pointer after a layout
change do not steal the focus.
