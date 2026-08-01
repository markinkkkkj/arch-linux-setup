#!/usr/bin/env bash
# Color picker (replaces hyprpicker): click a pixel, its hex value goes to
# the clipboard. Uses only grim+slurp, both already installed: a 1x1 PPM
# capture whose last 3 bytes are the pixel's RGB.

set -euo pipefail

point="$(slurp -p)" || exit 0

rgb=($(grim -g "$point" -t ppm - | tail -c 3 | od -An -tu1))
hex="$(printf '#%02x%02x%02x' "${rgb[0]}" "${rgb[1]}" "${rgb[2]}")"

printf '%s' "$hex" | wl-copy
notify-send "Color picker" "$hex copiado" -t 2000
