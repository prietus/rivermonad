#!/bin/sh
# Build the rivermonad site (https://rivermonad.priet.us) from wiki/ and,
# with --upload, publish it.
#
#   tools/wiki/publish.sh            build into wiki/site and check it
#   tools/wiki/publish.sh --serve    preview at http://127.0.0.1:8000 while editing
#   tools/wiki/publish.sh --upload   build, then rsync to the server
#
# MkDocs Material is installed in a virtualenv under ~/.cache the first time.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export NO_MKDOCS_2_WARNING=1
VENV="${XDG_CACHE_HOME:-$HOME/.cache}/rivermonad-wiki/venv"
DEST="${RIVERMONAD_WIKI_DEST:-teraflops@mail.priet.us:/srv/sites/rivermonad-site/site/}"

if [ ! -x "$VENV/bin/mkdocs" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q mkdocs-material
fi

cd "$ROOT"
python3 tools/wiki/gen-modules.py
mkdir -p wiki/docs/img
cp docs/screenshot.png docs/hasklets.png docs/demo.gif wiki/docs/img/

case "$1" in
  --serve) exec "$VENV/bin/mkdocs" serve -f wiki/mkdocs.gen.yml ;;
esac

"$VENV/bin/mkdocs" build --strict -q -f wiki/mkdocs.gen.yml -d site
echo "built wiki/site"

if [ "$1" = "--upload" ]; then
  rsync -rlt --delete --chmod=D755,F644 wiki/site/ "$DEST"
  echo "uploaded to $DEST"
fi
