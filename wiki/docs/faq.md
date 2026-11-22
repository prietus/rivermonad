# FAQ

## Is rivermonad a compositor?

No. river is the compositor: it draws, handles input devices, Xwayland
and the Wayland protocols. rivermonad is river's window manager: it
decides where windows go, which one has the focus and what the keys do,
through the `river-window-management-v1` protocol. If rivermonad crashes
or restarts, the windows stay.

## Which river version?

0.4 or newer; 0.5 for everything (`updatePointer` warps the pointer with
version 3 of the protocol).

## My configuration does not compile

`rivermonad --recompile` shows ghc's errors. `Super+Q` only restarts if
the file builds, so a typo never leaves you without a window manager. If
ghc cannot find the `Rivermonad` modules, the library is not installed
where ghc looks (`cabal install --lib rivermonad`, or a
[build script](configuration.md#building-against-a-checkout)).

## How do I find a window's app id?

Focus it and run `rivermonad --ipc '"EventStream"' | head -2`: the state
has its `app_id` and `title`.

## Screen sharing and file pickers

They go through xdg-desktop-portal, which picks its backends by
`XDG_CURRENT_DESKTOP`. The session's `init` sets it to `river` and passes
it to D-Bus; `~/.config/xdg-desktop-portal/river-portals.conf` then sends
screen sharing and screenshots to `xdg-desktop-portal-wlr` and the rest
(file pickers, settings) to `xdg-desktop-portal-gtk`. Do not set
`XDG_CURRENT_DESKTOP=GNOME` for the whole session.

## Can I open GNOME Settings, Online Accounts...?

GNOME Settings refuses to run outside GNOME. For one process only:

```sh
XDG_CURRENT_DESKTOP=GNOME gnome-control-center online-accounts
```

## Urgency hints, "window demands attention"

Not possible today: river 0.5 ignores `xdg-activation` requests and does
not pass them to the window manager, so there is no `UrgencyHook`. Desktop
notifications (mako) still reach you from any workspace; foot can turn the
terminal bell into a notification with `notify=yes` in `[bell]`.

## HDR

river creates the color-management protocol, so applications can describe
HDR content, but it does not switch outputs into HDR mode: on river 0.5
content is shown in SDR.

## Hot corners

The window manager only learns where the pointer is when windows change,
not while it moves, so hot corners live in the bar:
[waymobar's `hotCorners`](https://github.com/prietus/waymobar#hot-corners).

## An Alt-Tab that cycles while Alt is held

river reports the keys that are bound, not when a modifier is released, so
[`MostRecentlyUsed`](modules/actions/MostRecentlyUsed.md) swaps between the
last two windows on each press and offers the rest in a menu.

## Virtual machines

In QEMU/UTM with virtio-gpu (virgl):

- the hardware cursor is drawn upside down and clicks miss:
  `river-session` turns on a software cursor (`WLR_NO_HARDWARE_CURSORS=1`)
  when it detects virtio-gpu;
- Firefox may draw text in the wrong colours or not at all with GPU
  rendering: set `gfx.webrender.software` to `true` in `about:config`;
- no VRR or HDR. Leave a fixed `mode` out of kanshi profiles if the VM
  window changes size: kanshi drops a whole profile when one setting
  fails.

## CPU use

rivermonad itself uses almost nothing (around 0.1% of a core when idle).
An animated wallpaper costs more, mostly in river, which composes every
frame: bgmonad's `busyFps` slows it down while windows cover it.
