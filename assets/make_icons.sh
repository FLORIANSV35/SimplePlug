#!/bin/bash
# Génère AppIcon.icns (macOS) et icon-windows.png (Windows, sans marge) à partir de icon-1024.png.
# Usage : swift assets/make_icon.swift assets/icon-1024.png && assets/make_icons.sh
set -euo pipefail
cd "$(dirname "$0")"

SET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$SET"
for s in 16 32 128 256 512; do
    sips -z $s $s icon-1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) icon-1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o AppIcon.icns

# Windows : le carré arrondi occupe toute l'icône (pas de marge transparente de 100 px).
python3 - <<'PY'
from PIL import Image
im = Image.open("icon-1024.png").convert("RGBA").crop((100, 100, 924, 924)).resize((512, 512), Image.LANCZOS)
im.save("icon-windows.png")
PY
echo "OK → AppIcon.icns, icon-windows.png"
