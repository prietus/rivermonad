# A complete rivermonad desktop

The configuration of a working river + rivermonad desktop on Arch Linux:
tiling with 6 px gaps, the [waymobar](https://github.com/prietus/waymobar)
status bar as floating pills, the [bgmonad](https://github.com/prietus/bgmonad)
living wallpaper, the [hasklets](https://github.com/prietus/hasklets) desktop
widgets, the [shotlet](https://github.com/prietus/shotlet) screenshot and
recording toolbar, notifications, a Spotlight-like launcher and an emoji
picker, all in Catppuccin Mocha colours. The layout
mirrors the home directory: `config/` is `~/.config/`, `local/bin/` is
`~/.local/bin/`.

| File | What it is |
|---|---|
| `config/rivermonad/rivermonad.hs` | the window manager: layouts, rules, keys |
| `config/rivermonad/build` | compiles it against a rivermonad checkout (`$RIVERMONAD_SRC`) |
| `config/waymobar/waymobar.hs` | the bar: workspaces, layout, title, media, network (Wi-Fi menu), weather, volume, CPU, memory, battery, shotlet button, tray, clock with the calendar's agenda, log out; Material Symbols icons |
| `config/waymobar/build` | compiles it against a waymobar checkout (`$WAYMOBAR_SRC`) |
| `config/bgmonad/bgmonad.hs` | the wallpaper: `~/.config/wallpaper` with a slow flow and a parallax between workspaces |
| `config/bgmonad/build` | compiles it against a bgmonad checkout (`$BGMONAD_SRC`) |
| `config/hasklets/config.json` | the desktop widgets: weather, CPU/memory/network, media player, disks, processes, calendar |
| `config/river/init` | session start: environment, portals, kanshi, rivermonad |
| `config/kanshi/config` | monitor resolution, scale and VRR |
| `config/mako/config` | notifications |
| `config/fuzzel/fuzzel.ini` | Spotlight-style launcher (also used by the emoji picker) |
| `config/foot/foot.ini` | terminal: font, zoom keys, Catppuccin Mocha colours (Nord ones commented out) |
| `config/xdg-desktop-portal/river-portals.conf` | portals: screen sharing via wlr, the rest via GTK |
| `config/xdg-desktop-portal-wlr/config` | how screen sharing picks the screen (slurp) |
| `config/waybar/` | the alternative bar, if you use waybar with the rivermonad modules |
| `local/bin/shot` | screenshots: full, region, annotate (grim, slurp, swappy) |
| `local/bin/screenrec` | screen recording on/off (wf-recorder) |
| `local/bin/emoji` | emoji picker: type a name, Enter, it is typed in the focused window |

## Install

On Arch Linux there is a package (see [packaging](../../packaging/README.md)):
`rivermonad-dotfiles` depends on everything below, and `rivermonad-setup`
copies these files into your home. By hand, from a checkout:

```sh
sudo pacman -S foot fuzzel mako kanshi grim slurp swappy wl-clipboard \
  wf-recorder wtype unicode-emoji libnotify gdk-pixbuf2 \
  inter-font noto-fonts-emoji xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
  gtk4 gtk4-layer-shell gobject-introspection curl python-gobject
examples/dotfiles/install.sh          # never overwrites (use --force to replace, keeps .bak)
contrib/session/install.sh --system   # river-session + login screen entry
ln -sfn /path/to/image ~/.config/wallpaper
```

(The package names are Arch's; on Debian/Ubuntu they are `mako-notifier`,
`unicode-data`, `libnotify-bin`, `libgdk-pixbuf-2.0-dev`, `fonts-inter` and
`fonts-noto-color-emoji`; the last line is what hasklets and shotlet need.)

Build rivermonad, [waymobar](https://github.com/prietus/waymobar) and
[bgmonad](https://github.com/prietus/bgmonad) (their READMEs), then point the
three `build` scripts at the checkouts if they are not in `~/xmonad`,
`~/waymobar` and `~/bgmonad` (`RIVERMONAD_SRC`, `WAYMOBAR_SRC`,
`BGMONAD_SRC`). If you installed the libraries with `cabal install --lib`
instead, delete the `build` scripts: plain ghc is used then.

[hasklets](https://github.com/prietus/hasklets) is a plain program: `cabal
install --installdir ~/.local/bin` in its checkout. Set your own place in
`config/hasklets/config.json` (`weather`), or right-click a widget for the
settings window; without hasklets, remove `spawnOnce "hasklets"` from
`rivermonad.hs`.

[shotlet](https://github.com/prietus/shotlet) is one Python file: clone it
and link it into `~/.local/bin` (its README). `Super+Shift+S` and the button
in the bar open it; the `Print` keys keep using the plain `shot` and
`screenrec` scripts, and either can stop a recording started by the other.

The agenda under the clock is empty until you add your calendar accounts
to `myCalendar` in `waymobar.hs`. Passwords stay out of these files: they go
in a separate file (`~/.config/waymobar/icloud-password`, `chmod 600`), and
hasklets keeps its own in `~/.config/hasklets/accounts.json`. Neither is
ever copied by `install.sh`, which only installs the files it lists.

The wallpaper is whatever `~/.config/wallpaper` links to; point the link at
another image and bgmonad crossfades to it. For a plain, still wallpaper,
swap `spawnOnce "bgmonad"` for the swaybg line in `rivermonad.hs`.

Fonts: the bar, the launcher and the notifications use **Inter**; the bar's
icons are **Material Symbols** (the variable font, Rounded cut:
`ttf-material-symbols-variable` on Arch, or the `.ttf` from
[google/material-design-icons](https://github.com/google/material-design-icons)
in `~/.local/share/fonts/`, then `fc-cache -f`); **Noto Color Emoji** is for
the emoji picker. The terminal uses *Ubuntu Mono derivative Powerline* (from
[powerline/fonts](https://github.com/powerline/fonts)); change `font=` in
`foot.ini` if you don't have it.

## Keys

| Keys | Action |
|---|---|
| `Super+Shift+Enter` | terminal |
| `Super+P` | launcher |
| `Super+I` | emoji picker |
| `Super+J` / `Super+K`, `Super+Enter` | focus next / previous, swap with master |
| `Super+H` / `Super+L` | shrink / grow the master area |
| `Super+Space`, `Super+Z` | next layout, toggle full screen without borders |
| `Super+=` / `Super+-` | wider / narrower gaps |
| `Super+1…9`, `Super+Shift+1…9` | go to / move to workspace (`Super+←/→` cycle, `Super+Tab` previous) |
| `` Super+` `` | scratchpad terminal |
| `Super+drag`, `Super+right drag`, `Super+T` | move, resize (makes it float), back to tiling |
| `Super+Shift+S` | shotlet: the screenshot and recording toolbar |
| `Print`, `Shift+Print`, `Ctrl+Print` | screenshot: screen, region, region + annotate |
| `F13` instead of `Print` | the same from a Mac keyboard through UTM, where Print Screen arrives as F13 |
| `Super+Print`, `Super+Shift+Print` | record screen / region (again to stop) |
| `Super+Q`, `Super+Shift+Q` | recompile and restart rivermonad, end the session |

## Notes for virtual machines

This setup runs in a UTM/QEMU VM on Apple silicon. Three things there come
from the virtual GPU (virtio-gpu, virgl over Metal), not from river:

* the hardware cursor is drawn upside down and clicks miss: `river-session`
  in `contrib/session` turns on a software cursor;
* Firefox shows no text with GPU rendering: set `gfx.webrender.software` to
  `true`;
* no VRR or HDR: the kanshi profile for real hardware is left commented out,
  because a setting the output rejects makes kanshi drop the whole profile.
