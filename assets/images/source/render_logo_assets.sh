#!/usr/bin/env bash
# Render the committed logo images from the artist's SVGs (LOGO_LICENSE, not GPL).
# Re-run after any change to this folder, then commit the PNGs it writes:
#   - in-app marks (GabbroLogo.assetPath), 192 px tall: green for both
#     themes, plus a black / white high-contrast pair
#   - Android launcher icons (green mark) at every mipmap density: legacy
#     48dp icon, plus the 108dp adaptive-icon foreground (Android 8+; black
#     background in mipmap-anydpi-v26/ic_launcher.xml)
# The Linux desktop icons are rendered at release time by
# linux/packaging/render_icons.sh, from the same green mark.
#
#   bash assets/images/source/render_logo_assets.sh
set -eu

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SRC_DIR/../../.." && pwd)"
IMG="$REPO_ROOT/assets/images"
RES="$REPO_ROOT/android/app/src/main/res"
GREY="$SRC_DIR/ic_launcher_light.svg"   # dark-grey mark, transparent
GREEN="$SRC_DIR/ic_launcher_dark.svg"   # green mark, transparent

command -v rsvg-convert >/dev/null 2>&1 || {
  echo "render_logo_assets.sh: rsvg-convert not found (Arch: pacman -S librsvg; Mint: apt install librsvg2-bin)" >&2
  exit 1
}
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# High-contrast marks: the grey mark recoloured to pure black / pure white.
sed 's/fill:#3c3c38/fill:#000000/' "$GREY" > "$tmp/hc_light.svg"
sed 's/fill:#3c3c38/fill:#ffffff/' "$GREY" > "$tmp/hc_dark.svg"
grep -q 'fill:#000000' "$tmp/hc_light.svg" || {
  echo "render_logo_assets.sh: grey mark colour #3c3c38 not found in $GREY" >&2
  exit 1
}

rsvg-convert -h 192 "$GREEN" -o "$IMG/logo_192.png"
rsvg-convert -h 192 "$tmp/hc_light.svg" -o "$IMG/logo_hc_light_192.png"
rsvg-convert -h 192 "$tmp/hc_dark.svg" -o "$IMG/logo_hc_dark_192.png"

# Adaptive foreground: the mark's 72dp box centred on the 108dp layer (pad a
# quarter of the box each side), so the hexagon stays in the 66dp safe zone.
# Padding is in the image, not a dp inset: launchers rasterise small, where a
# fixed inset shrank the mark to ~30% of the tile (S23, 2026-10-29).
sed 's/viewBox="0 0 26.458333 26.458333"/viewBox="-6.6145833 -6.6145833 39.6875 39.6875"/' "$GREEN" > "$tmp/fg.svg"
grep -q 'viewBox="-6.6145833' "$tmp/fg.svg" || {
  echo "render_logo_assets.sh: expected viewBox not found in $GREEN" >&2
  exit 1
}

for d in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  dir="$RES/mipmap-${d%%:*}"
  legacy=$(awk "BEGIN{print 48*${d#*:}}")
  fg=$(awk "BEGIN{print 108*${d#*:}}")
  rsvg-convert -w "$legacy" -h "$legacy" "$GREEN" -o "$dir/ic_launcher.png"
  rsvg-convert -w "$fg" -h "$fg" "$tmp/fg.svg" -o "$dir/ic_launcher_foreground.png"
done
