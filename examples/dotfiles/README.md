# A complete rivermonad desktop

The configuration of a working river + rivermonad desktop on Arch Linux:
tiling with 6 px gaps, the [waymobar](https://github.com/prietus/waymobar)
status bar as floating pills, the [bgmonad](https://github.com/prietus/bgmonad)
living wallpaper, notifications, a Spotlight-like launcher, emoji picker,
screenshots and screen recording, all in Catppuccin Mocha colours. The layout
mirrors
the home directory: `config/` is `~/.config/`, `local/bin/` is
`~/.local/bin/`.

| File | What it is |
|---|---|
| `config/rivermonad/rivermonad.hs` | the window manager: layouts, rules, keys |
| `config/rivermonad/build` | compiles it against a rivermonad checkout (`$RIVERMONAD_SRC`) |
| `config/waymobar/waymobar.hs` | the bar: workspaces, layout, title, media, network (Wi-Fi menu), weather, volume, CPU, memory, battery, tray, clock, log out |
| `config/waymobar/build` | compiles it against a waymobar checkout (`$WAYMOBAR_SRC`) |
| `config/bgmonad/bgmonad.hs` | the wallpaper: `~/.config/wallpaper` with a slow flow and a parallax between workspaces |
| `config/bgmonad/build` | compiles it against a bgmonad checkout (`$BGMONAD_SRC`) |
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

```sh
sudo pacman -S foot fuzzel mako kanshi grim slurp swappy wl-clipboard \
  wf-recorder wtype unicode-emoji libnotify gdk-pixbuf2 \
  inter-font noto-fonts-emoji xdg-desktop-portal-wlr xdg-desktop-portal-gtk
examples/dotfiles/install.sh          # never overwrites (use --force to replace, keeps .bak)
contrib/session/install.sh --system   # river-session + login screen entry
ln -sfn /path/to/image ~/.config/wallpaper
```

(The package names are Arch's; on Debian/Ubuntu they are `mako-notifier`,
`unicode-data`, `libnotify-bin`, `libgdk-pixbuf-2.0-dev`, `fonts-inter` and
`fonts-noto-color-emoji`.)

Build rivermonad, [waymobar](https://github.com/prietus/waymobar) and
[bgmonad](https://github.com/prietus/bgmonad) (their READMEs), then point the
three `build` scripts at the checkouts if they are not in `~/xmonad`,
`~/waymobar` and `~/bgmonad` (`RIVERMONAD_SRC`, `WAYMOBAR_SRC`,
`BGMONAD_SRC`). If you installed the libraries with `cabal install --lib`
instead, delete the `build` scripts: plain ghc is used then.

The wallpaper is whatever `~/.config/wallpaper` links to; point the link at
another image and bgmonad crossfades to it. For a plain, still wallpaper,
swap `spawnOnce "bgmonad"` for the swaybg line in `rivermonad.hs`.

Fonts: the bar, the launcher and the notifications use **Inter**; the bar's
icons are colour emoji (**Noto Color Emoji**) plus a few glyphs from the
**Symbols Nerd Font**: download `NerdFontsSymbolsOnly.tar.xz` from the Nerd
Fonts releases, put the `.ttf` files in `~/.local/share/fonts/` and its
`10-nerd-font-symbols.conf` in `~/.config/fontconfig/conf.d/`, then
`fc-cache -f`. The terminal uses *Ubuntu Mono derivative Powerline* (from
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
