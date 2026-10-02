#!/bin/bash
# Regenerate LocumView web branding assets from the sources in packaging/branding (changelog #20).
# Needs ImageMagick 7 (`magick`) and python3. Outputs:
#   build/brand-kit/              shareable kit (SVG/PNG/favicon/wallpapers + COLORS-AND-USAGE.md), not committed
#   k8s/locumview/keycloak/theme/ Keycloak login theme images (wordmark, background, favicon)
#   packaging/guacamole-branding/src/images/ + k8s/locumview/guacamole/locumview-branding.jar
set -euo pipefail
cd "$(dirname "$0")/../.."
B=packaging/branding; W=$B/web; K=build/brand-kit; T=k8s/locumview/keycloak/theme; G=packaging/guacamole-branding/src/images
rm -rf "$K"; mkdir -p "$K"/{svg,png,wallpapers}
# PNG date/time chunks would make every build differ; leave them out so builds are byte-reproducible.
r() { magick -background none -density 1200 "$1" -resize "$2" -define png:exclude-chunks=date,time "$3"; }

# Vector variants of the mark and wordmark.
cp $B/locumview-logo.svg "$K/svg/locumview-mark-white.svg"
sed 's/#FFFFFF/#5EEAD4/g' $B/locumview-logo.svg > "$K/svg/locumview-mark-teal.svg"
sed 's/#FFFFFF/#0E141C/g' $B/locumview-logo.svg > "$K/svg/locumview-mark-navy.svg"
cp $B/locumview-gdm-logo.svg "$K/svg/locumview-wordmark-on-dark.svg"
sed 's/#FFFFFF/#0E141C/g; s/#5EEAD4/#0F9D8A/g' $B/locumview-gdm-logo.svg > "$K/svg/locumview-wordmark-on-light.svg"
cp $W/locumview-app-icon.svg "$K/svg/"; cp $W/COLORS-AND-USAGE.md "$K/"

# Rasters.
for s in 512 256 128 64; do for c in white teal navy; do r "$K/svg/locumview-mark-$c.svg" ${s}x$s "$K/png/locumview-mark-$c-$s.png"; done; done
for s in 512 192 180 32 16; do r $W/locumview-app-icon.svg ${s}x$s "$K/png/locumview-app-icon-$s.png"; done
magick -background none -density 1200 $W/locumview-app-icon.svg -define icon:auto-resize=48,32,16 "$K/png/favicon.ico"
for w in 1288 644; do r "$K/svg/locumview-wordmark-on-dark.svg" ${w}x "$K/png/locumview-wordmark-on-dark-${w}w.png"
                     r "$K/svg/locumview-wordmark-on-light.svg" ${w}x "$K/png/locumview-wordmark-on-light-${w}w.png"; done
for w in nested-dark nested-light terminal-dark ridgeline-dark aurora-dark still-lake-dark; do
  magick -density 72 $B/wallpapers/$w.svg -resize 1920x1080 "$K/wallpapers/locumview-$w-1920.jpg"; done

# Login background: the Nested wallpaper without its bottom-left mark (cropped awkwardly by `cover`).
python3 - "$B/wallpapers/nested-dark.svg" "$K/login-bg.svg" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
s, n1 = re.subn(r'\s*<g transform="translate\(70 970\)">.*?</g>', '', s, flags=re.S)
s, n2 = re.subn(r'\s*<path d="M117\.2 995[^>]*/>', '', s)
assert (n1, n2) == (1, 1), (n1, n2)
open(sys.argv[2], "w").write(s)
PY
magick "$K/login-bg.svg" -resize 1920x1080 -quality 82 "$K/locumview-login-bg.jpg"

# Keycloak theme and Guacamole extension inputs.
cp "$K/svg/locumview-wordmark-on-dark.svg" $T/locumview-wordmark.svg
cp "$K/locumview-login-bg.jpg" $T/locumview-bg.jpg
cp "$K/png/favicon.ico" $T/favicon.ico
cp "$K/svg/locumview-wordmark-on-dark.svg" $G/locumview-wordmark.svg
cp "$K/png/locumview-app-icon-192.png" $G/locumview-icon-192.png
cp "$K/png/locumview-app-icon-32.png" $G/locumview-icon-32.png
cp "$K/locumview-login-bg.jpg" $G/locumview-bg.jpg
python3 packaging/guacamole-branding/build.py
echo "assets rebuilt; kit in $K"
