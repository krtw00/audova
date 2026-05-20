#!/bin/bash
# Audova アイコン (AUD-12) の iconset + icns を生成する。
# scripts/generate_icon.swift で large/small PNG を描き、
# 16/32/64 は簡略版 (small)、128 以上は詳細版 (large) を割り当てて iconutil で .icns 化する。
#
# 実行: bash scripts/build_icns.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift scripts/generate_icon.swift

RES="Sources/Audova/Resources"
ICONSET="$RES/Audova.iconset"
L="/tmp/audova_icon_large.png"
S="/tmp/audova_icon_small.png"

# 小サイズ = 簡略版
sips -z 16 16   "$S" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32   "$S" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32   "$S" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64   "$S" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
# 大サイズ = 詳細版
sips -z 128 128 "$L" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256 "$L" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$L" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512 "$L" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$L" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$L" "$ICONSET/icon_512x512@2x.png"

# Apple 標準外の残骸 (旧 iconset の名残) を除去
rm -f "$ICONSET/icon_64x64.png" "$ICONSET/icon_64x64@2x.png" "$ICONSET/icon_1024x1024.png"

iconutil -c icns "$ICONSET" -o "$RES/Audova.icns"
echo "done: $RES/Audova.icns"
