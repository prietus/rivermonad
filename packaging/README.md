# Distribution packages

| Distribution | File | Needs |
|---|---|---|
| Arch Linux | [`arch/PKGBUILD`](arch/PKGBUILD) | river ≥ 0.4 (`extra/river` is 0.5) |
| Fedora ≥ 44 | [`fedora/rivermonad.spec`](fedora/rivermonad.spec) | river ≥ 0.4 (Fedora 43 still has 0.3) |

Like xmonad, rivermonad compiles `~/.config/rivermonad/rivermonad.hs` with
ghc at run time, so the packages install the Haskell library too and
depend on ghc:

* **Arch** ships Haskell libraries as shared objects only. The PKGBUILD
  builds them that way and enables the `dynamic-config` cabal flag, which
  makes rivermonad compile the configuration with `-dynamic`.
* **Fedora** splits it like other Haskell packages: `rivermonad` (the
  binary and the session) requires `ghc-rivermonad-devel` (the library).

Both install the session: `/usr/bin/river-session`,
`/usr/share/wayland-sessions/rivermonad.desktop` ("river + rivermonad" on
the login screen) and `/usr/share/rivermonad/init`, which river-session
uses when there is no `~/.config/river/init`.

## Arch Linux

```sh
cd packaging/arch
makepkg -si
```

The PKGBUILD builds two packages:

* **rivermonad**: the window manager, its library and the session.
* **rivermonad-dotfiles** (`any`): the desktop of
  [examples/dotfiles](../examples/dotfiles/README.md). A package must not
  write in `/home`, so the files are installed in
  `/usr/share/rivermonad/dotfiles` and each user copies them to `~/.config`
  with `rivermonad-setup` (it never overwrites; `--force` replaces and keeps
  a `.bak`, `--list` only shows what it would do). The first session without
  a `~/.config/rivermonad/rivermonad.hs` shows a notification that says so.

rivermonad-dotfiles depends on the rest of the desktop, whose PKGBUILDs are
in their repositories (`packaging/arch/`): build and install
[waymobar](https://github.com/prietus/waymobar),
[bgmonad](https://github.com/prietus/bgmonad),
[hasklets](https://github.com/prietus/hasklets) and
[shotlet](https://github.com/prietus/shotlet) first, then:

```sh
makepkg -si                # both packages
rivermonad-setup           # as your user: copies the dotfiles to ~/.config
```

`makepkg -si --pkg rivermonad` builds only the window manager. The
`build` scripts of the dotfiles (they compile against a source checkout)
are left out of the package: plain ghc finds the packaged libraries.

## Fedora

The whole desktop, like `paru -S rivermonad-dotfiles` on Arch: one script
builds the RPMs of every repository (their `packaging/fedora/*.spec`) in
order and installs them.

```sh
packaging/fedora/build-desktop.sh             # --with-luna adds luna, --no-install only builds
rivermonad-setup                              # as your user: copies the dotfiles to ~/.config
ln -sfn /path/to/image ~/.config/wallpaper
```

It uses the checkouts next to this one (`../waymobar`, `../bgmonad`...)
and clones the ones that are missing. The order is
`material-symbols-rounded-fonts` (the bar's icon font, not in Fedora; its
spec is here), waymobar, bgmonad, hasklets, shotlet, locklet and
rivermonad. Like the PKGBUILD, `rivermonad.spec` builds
**rivermonad-dotfiles** (`noarch`) too, which depends on all of them.

hasklets takes longest: Fedora lacks some of the GTK 4 bindings it needs
(gi-gtk4-layer-shell, gi-pangocairo...), so its spec builds them from
Hackage as `ghc-*` subpackages.

The window manager alone:

```sh
sudo dnf install rpm-build rpmdevtools dnf-plugins-core
sudo dnf builddep packaging/fedora/rivermonad.spec
spectool -g -R packaging/fedora/rivermonad.spec
rpmbuild -bb packaging/fedora/rivermonad.spec
sudo dnf install ~/rpmbuild/RPMS/*/{,ghc-}rivermonad{,-devel}-0.6.3-*.rpm
```

The specs build in [COPR](https://copr.fedorainfracloud.org/) too (luna's
needs its vendored crates uploaded as a source).

## A new release

1. Bump `version:` in `rivermonad.cabal`, `pkgver` in the PKGBUILD and
   `Version:` in the spec (plus a `%changelog` entry).
2. Tag it: `git tag -a v0.6.3 -m "rivermonad 0.6.3" && git push --tags`.
3. Update `sha256sums` in the PKGBUILD with `updpkgsums` (it is `SKIP`
   until the tag exists).
