#!/bin/sh
# Copy these dotfiles into your home: config/* -> ~/.config/, local/bin/* ->
# ~/.local/bin/. Files that already exist are kept (pass --force to replace
# them; the old file is saved with a .bak suffix).
#
# The rivermonad-dotfiles package installs this script as rivermonad-setup
# and the dotfiles in /usr/share/rivermonad/dotfiles.
#
# Only the files listed below are copied, never "whatever is in the
# directory": passwords and accounts (waymobar's icloud-password, hasklets'
# accounts.json) are not dotfiles and must not end up here.
set -e

files='
config/rivermonad/rivermonad.hs
config/rivermonad/build
config/waymobar/waymobar.hs
config/waymobar/build
config/bgmonad/bgmonad.hs
config/bgmonad/build
config/hasklets/config.json
config/river/init
config/kanshi/config
config/mako/config
config/fuzzel/fuzzel.ini
config/foot/foot.ini
config/gammastep/config.ini
config/xdg-desktop-portal/river-portals.conf
config/xdg-desktop-portal-wlr/config
config/waybar/config.jsonc
config/waybar/style.css
local/bin/shot
local/bin/screenrec
local/bin/emoji
'

usage() {
  echo "usage: $(basename "$0") [--force] [--list]"
  echo "  --force  replace existing files (the old one is kept as FILE.bak)"
  echo "  --list   show what would be installed and where, change nothing"
}

force=no
list=no
for a in "$@"; do
  case "$a" in
    --force) force=yes ;;
    --list) list=yes ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

# The dotfiles are next to this script in a checkout, in /usr/share when
# it is installed as rivermonad-setup.
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
src=
for dir in "$here" "$here/../share/rivermonad/dotfiles" /usr/share/rivermonad/dotfiles; do
  if [ -d "$dir/config" ]; then
    src="$(cd "$dir" && pwd)"
    break
  fi
done
if [ -z "$src" ]; then
  echo "$(basename "$0"): the dotfiles are not in $here nor in /usr/share/rivermonad/dotfiles" >&2
  exit 1
fi

config="${XDG_CONFIG_HOME:-$HOME/.config}"

dest() {   # dest FILE: where a file of the list goes
  case "$1" in
    config/*) echo "$config/${1#config/}" ;;
    local/bin/*) echo "$HOME/.local/bin/${1#local/bin/}" ;;
  esac
}

copy() {   # copy SRC DEST
  if [ "$list" = yes ]; then
    if [ -e "$2" ]; then echo "exists    $2"; else echo "new       $2"; fi
    return
  fi
  if [ -e "$2" ] && [ "$force" = no ]; then
    echo "kept      $2"
    return
  fi
  mkdir -p "$(dirname "$2")"
  [ -e "$2" ] && cp -p "$2" "$2.bak"
  cp -p "$1" "$2"
  echo "installed $2"
}

for f in $files; do
  # The build scripts compile against a source checkout: the packages
  # leave them out, plain ghc finds the installed libraries.
  [ -e "$src/$f" ] || continue
  copy "$src/$f" "$(dest "$f")"
done

# Dark GTK and libadwaita applications, to go with the dark desktop. Only
# if they are still at the defaults: a choice of yours is kept.
dark() {   # dark KEY VALUE DEFAULT
  command -v gsettings >/dev/null || return 0
  cur="$(gsettings get org.gnome.desktop.interface "$1" 2>/dev/null)" || return 0
  if [ "$cur" = "$3" ]; then
    if [ "$list" = yes ]; then
      echo "setting   $1 $2 (now $cur)"
    else
      gsettings set org.gnome.desktop.interface "$1" "$2" && echo "set       $1 $2"
    fi
  fi
}
dark color-scheme prefer-dark "'default'"
dark gtk-theme Adwaita-dark "'Adwaita'"

[ "$list" = yes ] && exit 0

if [ ! -e "$config/wallpaper" ]; then
  echo
  echo "Pick a wallpaper (bgmonad, started by rivermonad.hs, shows it):"
  echo "  ln -sfn /path/to/image $config/wallpaper"
fi
echo
echo "Log out and choose \"river + rivermonad\" on the login screen, or press"
echo "Super+Q in a running session to compile and load the new configuration."
