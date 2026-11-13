#!/bin/sh
# Copy these dotfiles into your home: config/* -> ~/.config/, local/bin/* ->
# ~/.local/bin/. Files that already exist are kept (pass --force to replace
# them; the old file is saved with a .bak suffix).
set -e
here="$(cd "$(dirname "$0")" && pwd)"
force=no
[ "$1" = "--force" ] && force=yes

copy() {   # copy SRC DEST
  if [ -e "$2" ] && [ "$force" = no ]; then
    echo "kept      $2"
    return
  fi
  mkdir -p "$(dirname "$2")"
  [ -e "$2" ] && cp -p "$2" "$2.bak"
  cp -p "$1" "$2"
  echo "installed $2"
}

cd "$here/config"
find . -type f | sort | while read -r f; do
  copy "$here/config/${f#./}" "${XDG_CONFIG_HOME:-$HOME/.config}/${f#./}"
done
cd "$here/local/bin"
for f in *; do
  copy "$here/local/bin/$f" "$HOME/.local/bin/$f"
done

if [ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/wallpaper" ]; then
  echo
  echo "Pick a wallpaper (bgmonad, started by rivermonad.hs, shows it):"
  echo "  ln -sfn /usr/share/backgrounds/<image> ~/.config/wallpaper"
fi
