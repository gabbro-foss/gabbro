#!/usr/bin/env bash
# Render the launcher icon tree for the Linux desktop entry from the source SVG.
# Placeholder for now; when the final logo lands, replace the source SVG (or
# point GABBRO_ICON_SVG at it) and re-run -- the packaging recipes and their .desktop
# entries are unchanged, they just reference the `gabbro` icon name.
#
#   render_icons.sh <hicolor-output-dir>
#
# Produces <out>/<size>x<size>/apps/gabbro.png for each size + scalable/apps.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SRC="${GABBRO_ICON_SVG:-$REPO_ROOT/assets/images/source/ic_launcher_light.svg}"
OUT="${1:?usage: render_icons.sh <hicolor-output-dir>}"
SIZES="16 32 48 64 128 256 512"

command -v rsvg-convert >/dev/null 2>&1 || {
  echo "render_icons.sh: rsvg-convert not found (pacman -S librsvg)" >&2
  exit 1
}
[ -f "$SRC" ] || { echo "render_icons.sh: source SVG not found: $SRC" >&2; exit 1; }

for s in $SIZES; do
  mkdir -p "$OUT/${s}x${s}/apps"
  rsvg-convert -w "$s" -h "$s" "$SRC" -o "$OUT/${s}x${s}/apps/gabbro.png"
done
mkdir -p "$OUT/scalable/apps"
cp "$SRC" "$OUT/scalable/apps/gabbro.svg"

echo "Rendered gabbro icons ($SIZES + scalable) into $OUT"
