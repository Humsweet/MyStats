#!/bin/bash
# Regenerate assets/icon/AppIcon.icns from gen_icon.py.
#
# Only needed when the icon design changes -- the .icns is committed, so
# scripts/build_app.sh does not depend on rsvg-convert being installed.
#
# Requires: rsvg-convert (brew install librsvg), iconutil (ships with macOS).
set -e

cd "$(dirname "$0")"

command -v rsvg-convert >/dev/null || {
    echo "rsvg-convert not found. Install it with: brew install librsvg" >&2
    exit 1
}

ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# name-in-iconset : pixel size. Each size is rendered from SVG at its native
# resolution rather than downscaled, so gen_icon.py's per-size stroke weights
# actually take effect.
render() {
    rsvg-convert -w "$2" -h "$2" <(python3 gen_icon.py "$2") -o "$ICONSET/$1.png"
}

render icon_16x16       16
render icon_16x16@2x    32
render icon_32x32       32
render icon_32x32@2x    64
render icon_128x128    128
render icon_128x128@2x 256
render icon_256x256    256
render icon_256x256@2x 512
render icon_512x512    512
render icon_512x512@2x 1024

iconutil -c icns "$ICONSET" -o AppIcon.icns
rm -rf "$ICONSET"

# A README/GitHub copy. Rendered in --display mode so it shows the rounded,
# shadowed plate the system draws, rather than the square full-bleed source.
rsvg-convert -w 512 -h 512 <(python3 gen_icon.py 1024 --display) -o AppIcon-display.png

echo "Wrote $(pwd)/AppIcon.icns ($(du -h AppIcon.icns | cut -f1)) and AppIcon-display.png"
