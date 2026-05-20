#!/bin/bash
# Audova を Developer ID 署名 + notarize して配布用 zip を作る (AUD-9)。
#
# 前提 (一回だけセットアップ):
#   1. keychain に "Developer ID Application" 証明書がある
#        security find-identity -v -p codesigning   # で確認
#   2. notarytool 認証プロファイルが登録済み
#        xcrun notarytool store-credentials "audova-notary" \
#          --apple-id <id> --team-id <TeamID> --password <app固有パスワード>
#
# 使い方: bash scripts/release.sh
#   プロファイル名を変えたいとき: NOTARY_PROFILE=foo bash scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
SRC=Sources/Audova
BUILD=".build/$CONFIG"
DIST="dist"
APP="$DIST/Audova.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-audova-notary}"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Info.plist")
ZIP="$DIST/Audova-v${VERSION}-macos-arm64.zip"
SUBMIT_ZIP="$DIST/.notarize-submit.zip"

# --- 署名 ID 自動検出 ---
IDENTITY=$(security find-identity -v -p codesigning \
  | awk -F'"' '/Developer ID Application/{print $2; exit}')
if [ -z "$IDENTITY" ]; then
    echo "ERROR: 'Developer ID Application' 証明書が keychain に見つかりません。" >&2
    echo "       security find-identity -v -p codesigning で確認してください。" >&2
    exit 1
fi
echo "==> 署名 ID: $IDENTITY"

echo "==> release ビルド"
swift build -c "$CONFIG"

echo "==> .app 組み立て: $APP"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BUILD/Audova"              "$APP/Contents/MacOS/Audova"
cp "$SRC/Info.plist"            "$APP/Contents/Info.plist"
cp "$SRC/Resources/Audova.icns" "$APP/Contents/Resources/Audova.icns"
ditto "$SRC/Resources/ja.lproj" "$APP/Contents/Resources/ja.lproj"
ditto "$BUILD/Audova_Audova.bundle" "$APP/Contents/Resources/Audova_Audova.bundle"
[ -d "$BUILD/GRDB_GRDB.bundle" ] && ditto "$BUILD/GRDB_GRDB.bundle" "$APP/Contents/Resources/GRDB_GRDB.bundle"

for fw in "$BUILD"/*.framework; do
    ditto "$fw" "$APP/Contents/Frameworks/$(basename "$fw")"
done
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Audova" 2>/dev/null || true

# --- 署名: 内側の framework を先に、最後に .app 本体 (notarize では --deep を使わない) ---
SIGN_OPTS=(--force --options runtime --timestamp --sign "$IDENTITY")
echo "==> framework 署名"
for fw in "$APP/Contents/Frameworks"/*.framework; do
    codesign "${SIGN_OPTS[@]}" "$fw"
done
echo "==> 本体署名"
codesign "${SIGN_OPTS[@]}" "$APP"

echo "==> 署名検証"
codesign --verify --deep --strict --verbose=2 "$APP"

# --- notarize ---
echo "==> notarize 用 zip 作成"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
echo "==> notarytool 提出 (--wait: 完了までブロック)"
xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
echo "==> staple (notarize チケットを .app に貼る)"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Gatekeeper 評価"
spctl -a -vvv --type exec "$APP" || true

echo "==> 配布 zip: $ZIP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
rm -f "$SUBMIT_ZIP"

echo
echo "done -> $ZIP"
echo "GitHub Releases にアップロードして配布できます。"
