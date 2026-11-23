#!/bin/sh
# Build the RPMs of the whole rivermonad desktop on Fedora (>= 44) from the
# specs in packaging/fedora/ of each repository, in dependency order, and
# install them. The Fedora counterpart of `paru -S rivermonad-dotfiles`.
#
#   packaging/fedora/build-desktop.sh [--no-install] [--with-luna] [SRCDIR]
#
# SRCDIR holds the checkouts (default: the directory this rivermonad
# checkout is in); a repository that is not there is cloned from GitHub.
# The RPMs are built in ~/rpmbuild as usual. Afterwards, as your user:
#
#   rivermonad-setup
#   ln -sfn /path/to/image ~/.config/wallpaper
set -eu

install=yes
luna=no
srcdir=
for a in "$@"; do
  case "$a" in
    --no-install) install=no ;;
    --with-luna) luna=yes ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "$(basename "$0"): unknown option $a" >&2; exit 2 ;;
    *) srcdir=$a ;;
  esac
done

here="$(cd "$(dirname "$0")" && pwd)"
[ -n "$srcdir" ] || srcdir="$(cd "$here/../../.." && pwd)"

# repository:spec, in the order they have to be built. hasklets takes
# longest: it builds the GTK 4 bindings Fedora does not have.
specs='
rivermonad:material-symbols-rounded-fonts
waymobar:waymobar
bgmonad:bgmonad
hasklets:hasklets
shotlet:shotlet
locklet:locklet
rivermonad:rivermonad
'
[ "$luna" = yes ] && specs="$specs luna:luna"

log() { printf '\n==> %s\n' "$*"; }

log "Build tools"
sudo dnf install -y rpm-build rpmdevtools dnf-plugins-core git

built=$(mktemp)
trap 'rm -f "$built"' EXIT

for entry in $specs; do
  repo=${entry%%:*}
  name=${entry#*:}
  dir="$srcdir/$repo"
  if [ ! -d "$dir" ]; then
    log "Clone $repo"
    git clone "https://github.com/prietus/$repo" "$dir"
  fi
  spec="$dir/packaging/fedora/$name.spec"
  [ -f "$spec" ] || { echo "no $spec" >&2; exit 1; }

  log "$name: build dependencies"
  sudo dnf builddep -y "$spec"
  spectool -g -R "$spec"

  if [ "$name" = luna ]; then
    # luna's crates are vendored (Source1): make the tarball from Cargo.lock.
    vendor="$(rpm --eval '%{_sourcedir}')/luna-$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$dir/Cargo.toml" | head -1)-vendor.tar.xz"
    if [ ! -f "$vendor" ]; then
      log "luna: vendor the crates"
      (cd "$dir" && cargo vendor --locked vendor >/dev/null && tar cJf "$vendor" vendor && rm -rf vendor)
    fi
  fi

  log "$name: rpmbuild"
  rpmbuild -bb "$spec" 2>&1 | tee "$built.log" | grep -E '^(Wrote|error)' || true
  # tee hides rpmbuild's exit status: a failed build writes no RPMs.
  if ! grep -q '^Wrote:' "$built.log"; then
    tail -30 "$built.log" >&2
    echo "$(basename "$0"): $name did not build" >&2
    exit 1
  fi
  sed -n 's/^Wrote: //p' "$built.log" >> "$built"
done
rm -f "$built.log"

# Debug information, profiling libraries and API documentation are left
# out (they are in ~/rpmbuild/RPMS if you want them), unless an older
# version is installed: it would pin the old -devel and block the update.
rpms=
for rpm in $(grep '\.rpm$' "$built"); do
  case "$rpm" in
    *-debuginfo-*|*-debugsource-*|*-prof-*|*-doc-*)
      rpm -q --quiet "$(rpm -qp --qf '%{NAME}' "$rpm" 2>/dev/null)" || continue ;;
  esac
  rpms="$rpms $rpm"
done

if [ "$install" = no ]; then
  log "Built (not installed):"
  echo "$rpms"
  exit 0
fi

log "Install"
# shellcheck disable=SC2086
sudo dnf install -y $rpms

log "Done"
cat <<'EOF'
Now, as your user:

  rivermonad-setup                          # copies the dotfiles to ~/.config
  ln -sfn /path/to/image ~/.config/wallpaper

Then log out and choose "river + rivermonad" on the login screen.
EOF
