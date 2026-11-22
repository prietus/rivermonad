# Installation

rivermonad needs **river ≥ 0.4** (0.5 for everything, e.g.
`updatePointer`) and **ghc**: like xmonad, it compiles your configuration
file at run time, so the Haskell library is installed too.

## Arch Linux

The packages are in the AUR. `rivermonad` is the window manager alone;
`rivermonad-dotfiles` is a complete desktop (bar, living wallpaper, widgets,
launcher, screenshots) and depends on the other programs, so build them in
this order:

1. [waymobar](https://aur.archlinux.org/packages/waymobar), the bar
2. [bgmonad](https://aur.archlinux.org/packages/bgmonad), the wallpaper
3. [hasklets](https://aur.archlinux.org/packages/hasklets), the desktop widgets
   (the first build compiles the GTK bindings and takes a while)
4. [shotlet](https://aur.archlinux.org/packages/shotlet), the screenshot and recording toolbar
5. [rivermonad](https://aur.archlinux.org/packages/rivermonad) and
   [rivermonad-dotfiles](https://aur.archlinux.org/packages/rivermonad-dotfiles),
   built together from the same PKGBUILD

```sh
for p in waymobar bgmonad hasklets shotlet rivermonad; do
  git clone https://aur.archlinux.org/$p.git
  (cd $p && makepkg -si)
done
```

An AUR helper works the order out by itself: `paru -S rivermonad-dotfiles`
(or `yay -S ...`). For the window manager alone, `paru -S rivermonad`.

A package does not write in your home, so the desktop's configuration is
installed in `/usr/share/rivermonad/dotfiles`. Copy it to `~/.config` as
your user:

```sh
rivermonad-setup           # never overwrites; --force replaces and keeps a .bak, --list only shows
ln -sfn /path/to/image ~/.config/wallpaper
```

Then log out and choose **river + rivermonad** on the login screen. If you
log in before running `rivermonad-setup`, rivermonad starts with its
defaults (`Super+Shift+Enter` opens a terminal) and a notification
reminds you of the command.

!!! note "Shared Haskell libraries"
    Arch ships Haskell libraries as shared objects only, so the package
    builds rivermonad with the `dynamic-config` flag: your configuration is
    compiled with `-dynamic`.

## Fedora ≥ 44

Build the RPMs from `packaging/fedora/rivermonad.spec` (Fedora 43 still has
river 0.3). Like other Haskell packages it is split in two: `rivermonad`
(the binary and the session) requires `ghc-rivermonad-devel` (the library).
See [packaging/README.md](https://github.com/prietus/rivermonad/blob/main/packaging/README.md).

## From source

```sh
sudo pacman -S ghc cabal-install libxkbcommon   # or apt install ghc cabal-install libxkbcommon-dev, or ghcup
git clone https://github.com/prietus/rivermonad
cd rivermonad
cabal update
cabal install --lib rivermonad        # so ghc can compile your config
cabal install exe:rivermonad
```

river must be installed separately (`pacman -S river`; or build it, it
needs zig and wlroots).

If you'd rather not install the library in your global GHC environment,
see [building against a checkout](configuration.md#building-against-a-checkout).

## Starting it

To try it without leaving your session, run river nested inside your
current compositor, or from a TTY:

```sh
river -c rivermonad
```

For a real session listed on the login screen, with a river `init`,
[kanshi](https://sr.ht/~emersion/kanshi/) for monitors and fixes for
virtual machines, install the session files (the packages already do):

```sh
contrib/session/install.sh            # for your user
contrib/session/install.sh --system   # also list it in GDM (uses sudo)
```

Then pick **river + rivermonad** on the login screen (GDM: the gear
button, before typing the password), or run `river-session` from a TTY.

| File | Installed to | What it does |
|---|---|---|
| `river-session` | `~/.local/bin/` | sets up the environment and starts river |
| `init` | `~/.config/river/init` | started by river: kanshi, then rivermonad (restarted if it crashes) |
| `rivermonad.desktop` | `~/.local/share/wayland-sessions/`, `/usr/share/wayland-sessions/` | the entry on the login screen |

The session takes care of a few things for you:

- `PATH` includes `~/.local/bin` first, since the session does not read
  `~/.bashrc`.
- `XDG_CURRENT_DESKTOP=river` is exported to D-Bus and systemd, so
  [portals](faq.md#screen-sharing-and-file-pickers) (screen sharing, file
  pickers) work.
- In virtual machines with virtio-gpu it asks wlroots for a software
  cursor (see the [FAQ](faq.md#virtual-machines)).

Everything else, the bar, notifications, the wallpaper, is started from
your `rivermonad.hs` with `spawnOnce`: see [Getting started](tutorial.md).
