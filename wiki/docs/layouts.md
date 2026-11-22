# Layouts

A layout decides where the tiled windows of a workspace go; floating
windows are placed by you. Several layouts are combined with `|||` and
`Super+Space` cycles through them. The `layoutHook` takes a `Layout`, so
wrap the combination:

```haskell
myLayout :: Layout Window
myLayout = Layout $ tiled ||| Mirror tiled ||| Full
  where
    tiled = Tall 1 (3/100) (1/2)
```

## Built in

| Layout | |
|---|---|
| `Tall nmaster delta ratio` | `nmaster` windows in a master column on the left, the rest stacked on the right; `delta` is the step of `Shrink`/`Expand`, `ratio` the master's share of the width |
| `Mirror l` | any layout turned 90°: `Mirror tiled` puts the master on top |
| `Full` | only the focused window, over the whole area |

They understand these messages, sent with `sendMessage`:

| Message | Default key | |
|---|---|---|
| `Shrink`, `Expand` | `M-h`, `M-l` | the master area smaller / bigger |
| `IncMasterN n` | `M-,`, `M-.` | more / fewer windows in the master area |
| `NextLayout` | `M-Space` | the next layout of a `|||` |
| `JumpToLayout "Full"` | | a layout by its name |

## From the modules

| Module | Layouts and modifiers |
|---|---|
| [ThreeColumns](modules/layout/ThreeColumns.md) | `ThreeCol`, `ThreeColMid`: three columns, the master on the left or in the middle |
| [Grid](modules/layout/Grid.md) | `Grid`: a grid of equal cells |
| [ResizableTile](modules/layout/ResizableTile.md) | `ResizableTall`: also resize windows vertically in their column |
| [BinarySpacePartition](modules/layout/BinarySpacePartition.md) | `emptyBSP`: each window splits the focused one, like bspwm |
| [TwoPane](modules/layout/TwoPane.md) | `TwoPane`: the master and the focused window side by side |
| [CenteredMaster](modules/layout/CenteredMaster.md) | `centerMaster`: the master floats in the middle over the others |
| [Spacing](modules/layout/Spacing.md) | `gapsWithEdge 6`, `spacingWithEdge 4`, `smartGaps`...: gaps between windows |
| [NoBorders](modules/layout/NoBorders.md) | `noBorders`, `smartBorders`: no border when it tells nothing |
| [ToggleLayouts](modules/layout/ToggleLayouts.md) | `toggleLayouts (noBorders Full) l`: one key in and out of full screen |
| [PerWorkspace](modules/layout/PerWorkspace.md) | `onWorkspace "web" Full l`: other layouts on some workspaces |
| [CenteredIfSingle](modules/layout/CenteredIfSingle.md) | `centeredIfSingle 0.6 1 l`: a lone window centred, not stretched |
| [Maximize](modules/layout/Maximize.md) | `maximize l`: one window over the others, on a key |
| [Magnifier](modules/layout/Magnifier.md) | `magnifier l`: the focused window drawn bigger |
| [LimitWindows](modules/layout/LimitWindows.md) | `limitWindows 3 l`: show at most n windows |
| [MultiToggle](modules/layout/MultiToggle.md) | `mkToggle [FULL, MIRROR, NOBORDERS, REFLECTX] l`: switch transformations on and off |

A typical combination:

```haskell
myLayout = Layout $ toggleLayouts (noBorders Full) $ smartBorders $ gapsWithEdge 6 $
  tiled ||| Mirror tiled ||| ThreeColMid 1 (3/100) (1/2) ||| emptyBSP
  where
    tiled = centeredIfSingle 0.6 1 (Tall 1 (3/100) (3/5))
```

Modifiers apply to everything inside them, so their order matters: here
the gaps are around every layout, and `M-z` (`sendMessage ToggleLayout`)
jumps out of all of them to full screen without borders.

## Writing your own

A layout is a type with a `LayoutClass` instance: `pureLayout` (or
`doLayout`, in `X`) turns a rectangle and a stack of windows into a
rectangle per window, and `pureMessage` (or `handleMessage`) reacts to
messages. It must have `Show` and `Read` instances, so it survives
restarts.

```haskell
-- every window gets an equal column
data Columns a = Columns deriving (Show, Read)

instance LayoutClass Columns a where
  pureLayout _ (Rectangle x y w h) s = zip ws [ Rectangle (x + i * cw) y cw h | i <- [0 ..] ]
    where
      ws = W.integrate s
      cw = w `div` length ws
  description _ = "Columns"
```

To change what an existing layout does, a
[`LayoutModifier`](modules/layout/LayoutModifier.md) is usually less work.
