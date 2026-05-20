#!/bin/bash
# Audova を .app 化して /Applications にインストールする (AUD-9)。
#
# Apple Developer Program 不要・$0。 自分の Mac でビルドした成果物を直接コピーするため
# 検疫 (quarantine) フラグが付かず、 署名/notarize 無しでもそのまま起動できる。
#
# 更新方法: コードを直したらこのスクリプトを再実行するだけ。
#   bash scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
SRC=Sources/Audova
BUILD=".build/$CONFIG"
APP=".build/Audova.app"        # staging (= .build は gitignore 済み)
DEST=/Applications/Audova.app

echo "==> release ビルド"
swift build -c "$CONFIG"

echo "==> .app 組み立て: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

# 実行ファイル / Info.plist / アイコン
cp "$BUILD/Audova"              "$APP/Contents/MacOS/Audova"
cp "$SRC/Info.plist"            "$APP/Contents/Info.plist"
cp "$SRC/Resources/Audova.icns" "$APP/Contents/Resources/Audova.icns"

# AppKit 標準メニューの日本語化は Bundle.main 直下の lproj を見る (AUD-11)
ditto "$SRC/Resources/ja.lproj" "$APP/Contents/Resources/ja.lproj"

# SwiftPM リソースバンドル (Bundle.module 用)
ditto "$BUILD/Audova_Audova.bundle" "$APP/Contents/Resources/Audova_Audova.bundle"
[ -d "$BUILD/GRDB_GRDB.bundle" ] && ditto "$BUILD/GRDB_GRDB.bundle" "$APP/Contents/Resources/GRDB_GRDB.bundle"

# SFBAudioEngine の vendored framework を同梱 (@rpath で解決)
for fw in "$BUILD"/*.framework; do
    ditto "$fw" "$APP/Contents/Frameworks/$(basename "$fw")"
done
# 実行ファイルから ../Frameworks を探せるよう rpath を追加
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Audova" 2>/dev/null || true

# ad-hoc 署名 (arm64 は署名必須。 自己使用なので ad-hoc で十分)
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

echo "==> インストール: $DEST"
rm -rf "$DEST"
ditto "$APP" "$DEST"

echo "done. 起動: open '$DEST'"
