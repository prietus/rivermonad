# Manage hooks

The manage hook runs once for every new window, before it is shown, and
decides where it goes: a workspace, floating, full screen. It is a
`ManageHook`, a `Query` about the window that returns a change to the
window set.

```haskell
myManageHook :: ManageHook
myManageHook = composeAll
  [ appId =? "pavucontrol" --> doCenterFloat
  , appId =? "firefox"     --> doShift "web"
  , isDialog               --> doFloat
  ]
```

and `manageHook = myManageHook` in the configuration.

## Finding out about a window

| Query | |
|---|---|
| `appId` | the Wayland app id (`foot`, `firefox`, `org.gnome.Nautilus`); `className` is an alias, for xmonad configs |
| `title` | the window title |
| `identifier` | river's stable identifier of the window |
| `parentWindow` | the window it belongs to, for dialogs |
| `isDialog` | it has a parent window |
| `isFixedSize` | its minimum and maximum sizes are the same |

Focus a window and run `rivermonad --ipc '"EventStream"' | head -2` to see
its `app_id` and `title`.

## Combining

| | |
|---|---|
| `q =? "x"` | the query equals |
| `q1 <&&> q2`, `q1 <||> q2` | and, or |
| `cond --> hook` | apply the hook if the condition holds |
| `composeAll [...]` | all the rules that match apply |

From [ManageHelpers](modules/hooks/ManageHelpers.md):

| | |
|---|---|
| `composeOne [...]` with `-?>` | only the first matching rule applies (floats before `doShift`, say) |
| `q /=? x`, `q ^? x`, `q ~? x`, `q $? x` | not equal, starts with, contains, ends with |
| `doRectFloat (W.RationalRect x y w h)` | floating at a position and size, as fractions of the screen |
| `doFullFloat` | floating over the whole screen |
| `transience` | a dialog goes to its parent's workspace |

## Doing

| Hook | |
|---|---|
| `doShift "web"` | to a workspace |
| `doFloat` | floating at the size it asked for, centred |
| `doCenterFloat` | the same, centred on the screen |
| `doSink` | tiled, even if it would float |
| `doFullscreen` | full screen |
| `idHook` | nothing |
| `doF f` | any change to the window set |

Dialogs (windows with a parent) and fixed-size windows float centred
without any rule.

## Where new windows enter

By default a new window goes above the focused one and takes the focus.
[InsertPosition](modules/hooks/InsertPosition.md) changes it:

```haskell
manageHook = insertPosition Below Newer <> myManageHook
```

## Windows that change later

Some programs set their title or app id after the window opened, too late
for the manage hook. [OnPropertyChange](modules/hooks/OnPropertyChange.md)
runs a hook again when they do:

```haskell
main = rivermonad $ onTitleChange (title =? "Spotify" --> doShift "9") myConfig
```

## More from the modules

- [NamedScratchpad](modules/util/NamedScratchpad.md):
  `namedScratchpadManageHook` places scratchpad windows.
- [SpawnOn](modules/actions/SpawnOn.md): `manageSpawn` opens programs on
  the workspace they were started from.
- [WindowSwallowing](modules/hooks/WindowSwallowing.md): a program
  started from a terminal takes its place.
