# The desktop

rivermonad is only the window manager. These programs, written in the same
spirit (most of them in Haskell and configured in Haskell), make a whole
desktop with it. On Arch, `rivermonad-dotfiles` installs them all with a
ready configuration ([Installation](install.md#arch-linux)).

![hasklets, waymobar and bgmonad on a rivermonad desktop](img/hasklets.png)

## waymobar, the bar

[waymobar](https://github.com/prietus/waymobar) is a native bar written and
configured in Haskell, with rivermonad widgets built in (workspaces,
layout, window title) read from the [IPC socket](ipc.md): pills, popovers,
a Wi-Fi menu, the weather, media, a tray, a calendar, a side panel, hot
corners, mako's notifications (with "do not disturb" and the recent ones)
and an on-screen display for volume, brightness and keyboard layout.

```haskell
  , startupHook = spawnOnce "waymobar"
```

### waybar instead

- **Native modules:** `contrib/waybar/` has a patch for waybar 0.15.0 adding
  `rivermonad/workspaces` (clickable), `rivermonad/window` and
  `rivermonad/layout`.
- **Unpatched waybar:** `withStatusBar def myConfig` makes rivermonad
  publish a status line, and `rivermonad --status` prints it as JSON lines
  for a `custom` module:

```jsonc
"modules-left": ["custom/rivermonad"],
"custom/rivermonad": {
  "exec": "rivermonad --status",
  "return-type": "json",
  "escape": false
}
```

Customise it with a `PP` like xmonad's (`ppCurrent`, `ppHidden`,
`ppTitle`, `ppOrder`...); the text uses Pango markup. See
[StatusBar](modules/hooks/StatusBar.md).

## bgmonad, the wallpaper

[bgmonad](https://github.com/prietus/bgmonad) is a living wallpaper: the
picture flows slowly and, through the IPC socket, it can change per
workspace, slide as you change workspace, and blur, dim or slow down
behind windows. Any other wallpaper program (swaybg...) works too.

```haskell
      spawnOnce "bgmonad"
```

## hasklets, desktop widgets

[hasklets](https://github.com/prietus/hasklets): weather, CPU, memory and
network, a media player, disks, processes and a calendar, on the desktop
above the wallpaper and below the windows (GTK 4 and cairo).

## shotlet, screenshots and recordings

[shotlet](https://github.com/prietus/shotlet) is a screenshot and screen
recording toolbar modelled on macOS's (⌘⇧5): the screen, a window or a
selection, recordings, a timer, and a thumbnail you can click to annotate
or drag into another program. Window mode asks rivermonad where the windows
are (the IPC request `"Windows"`).

```haskell
  , ("M-S-s", spawn "shotlet")
```

## locklet, the lock screen

[locklet](https://github.com/prietus/locklet) locks the screen over the
blurred bgmonad wallpaper and locks on its own after a while without input.

## A polkit agent

Applications that need administrator rights (Disks, date and time, package
installers) ask for your password through a polkit agent; without one they
fail without saying why. The dotfiles start `polkit-gnome`:

```haskell
      spawnOnce "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
```

## Clipboard history and night light

The dotfiles keep a clipboard history with
[cliphist](https://github.com/sentriz/cliphist) (`Super+C` picks an earlier
entry in fuzzel and copies it again) and warm the colours after sunset with
[gammastep](https://gitlab.com/chinstrap/gammastep), located by GeoClue
(`Super+Shift+N` switches it off and on). river supports the protocols
both need; the night light needs an output that supports gamma, which real
hardware does and virtio-gpu virtual machines do not.

## Everything else

Anything that works on wlroots compositors works: fuzzel (launcher), mako
(notifications), kanshi (monitors), grim and slurp (screenshots),
wf-recorder, xdg-desktop-portal-wlr and -gtk (screen sharing, file pickers).
The author's whole configuration, with keys, a bar and all of the above, is
in [examples/dotfiles](https://github.com/prietus/rivermonad/tree/main/examples/dotfiles).
