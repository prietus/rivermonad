# rivermonad

**An xmonad-style tiling window manager for Wayland.** It is to xmonad what
sway is to i3: the same model and the same kind of Haskell configuration
file, on a Wayland compositor.

![rivermonad demo: tiling, layouts, floating, workspaces, emoji picker, screenshot, launcher and scratchpad](img/demo.gif)

rivermonad is **not** a compositor. It runs as the window manager process of
[river](https://codeberg.org/river/river) ≥ 0.4, which splits the compositor
(rendering, input, protocols, Xwayland) from the window manager, connected by
the stable `river-window-management-v1` protocol. Because of this split:

- if rivermonad crashes or restarts, your windows survive;
- rivermonad contains no wlroots, C or FFI code for Wayland: the wire
  protocol is implemented in pure Haskell and the bindings are generated
  from river's XML files.

## What you get

- **xmonad's model**: a `StackSet` with workspaces, several monitors and a
  floating layer, layouts (`Tall`, `Mirror`, `Full`, `|||`), manage hooks,
  log hooks, event hooks, `ExtensibleState` and layout modifiers, with an
  API that follows xmonad's.
- **A Haskell configuration**: `~/.config/rivermonad/rivermonad.hs`,
  recompiled with ghc. `Super+Q` recompiles and restarts without losing a
  window, its place in the stack or the layout state.
- **[Ports of xmonad-contrib](modules/index.md)**: `EZConfig`,
  `NamedScratchpad`, `CycleWS`, `WindowGo`, `WindowBringer`,
  `Navigation2D`, `WindowSwallowing`, `BinarySpacePartition`,
  `MultiToggle`, `Submap`, `NamedActions` and many more.
- **Wayland niceties**: keyboard, touchpad and mouse settings in the
  config, compositor-drawn borders and drop shadows, tearing for games,
  layer-shell bars and launchers, and an [IPC socket](ipc.md) for bars and
  scripts.
- **[A whole desktop](desktop.md)** written in the same spirit: the
  [waymobar](https://github.com/prietus/waymobar) bar, the
  [bgmonad](https://github.com/prietus/bgmonad) living wallpaper, the
  [hasklets](https://github.com/prietus/hasklets) desktop widgets and the
  [shotlet](https://github.com/prietus/shotlet) screenshot toolbar.

![rivermonad screenshot: nvim, fastfetch and a music player tiled in the Tall layout under waymobar](img/screenshot.png)

## Where to start

<div class="grid cards" markdown>

- **[Installation](install.md)**: packages for Arch Linux and Fedora, or
  from source.
- **[Getting started](tutorial.md)**: your first `rivermonad.hs`, step by
  step.
- **[Configuration](configuration.md)**: every setting, keys, layouts and
  hooks.
- **[Modules](modules/index.md)**: the contrib modules, one page each.
- **[Coming from xmonad](xmonad.md)**: what changes in your `xmonad.hs`.
- **[FAQ](faq.md)**: what river can and cannot do, virtual machines.

</div>

The source is on [GitHub](https://github.com/prietus/rivermonad), BSD-3-Clause.
