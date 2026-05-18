#!/usr/bin/env bash
# Audova テストライブラリの配置調整。
#   - _source/ の MP3 を library/ にコピー (フラット配置がデフォルト)
#   - 一部曲を ffmpeg で FLAC / Opus / AAC / ALAC / WAV に format 多様化
#   - 1 item を Artist/Album ネスト配置 + フォルダ内 cover.jpg (= 埋込 art を抽出して配置)
#
# 依存: bash, jq, ffmpeg
# 入力: $AUDOVA_TEST_LIBRARY/_source/manifest.json (= fetch_test_audio.py の出力)
# 出力: $AUDOVA_TEST_LIBRARY/library/

set -euo pipefail

ROOT="${AUDOVA_TEST_LIBRARY:-$HOME/Music/audova-test-library}"
SOURCE="$ROOT/_source"
LIB="$ROOT/library"
MANIFEST="$SOURCE/manifest.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "[error] manifest not found: $MANIFEST" >&2
  echo "[error] fetch_test_audio.py を先に実行してください" >&2
  exit 1
fi

rm -rf "$LIB"
mkdir -p "$LIB"

# 全 mp3 を identifier:filename 形式で列挙 (= bash 3.2 互換のため while read で配列に)
TRACKS=()
while IFS= read -r line; do
  TRACKS+=("$line")
done < <(jq -r '.items[] | .identifier as $id | .files[] | "\($id)\t\(.name)"' "$MANIFEST")
echo "[info] ${#TRACKS[@]} tracks in manifest"

# ----- 1. フラット配置 (基本) -----
flat_count=0
for entry in "${TRACKS[@]}"; do
  ident="${entry%%$'\t'*}"
  fname="${entry#*$'\t'}"
  src="$SOURCE/$ident/$fname"
  [[ -f "$src" ]] || { echo "[warn] missing: $src" >&2; continue; }
  cp "$src" "$LIB/${ident}__${fname}"
  flat_count=$((flat_count + 1))
done
echo "[info] flat layout: $flat_count files"

# ----- 2. format 多様化 (= 先頭 5 曲を別 codec へ変換) -----
FORMATS=("flac" "opus" "m4a-aac" "m4a-alac" "wav")
fmt_index=0
fmt_max=${#FORMATS[@]}
total_tracks=${#TRACKS[@]}
[[ $fmt_max -gt $total_tracks ]] && fmt_max=$total_tracks
i=0
while [[ $i -lt $fmt_max ]]; do
  entry="${TRACKS[$i]}"
  ident="${entry%%$'\t'*}"
  fname="${entry#*$'\t'}"
  src="$SOURCE/$ident/$fname"
  i=$((i + 1))
  [[ -f "$src" ]] || continue
  base="${fname%.mp3}"
  target="${FORMATS[$fmt_index]}"
  out="$LIB/format-${target}__${ident}__${base}"
  case "$target" in
    # -vn で埋込アート (動画 stream として扱われる) を捨てる。 audio-only にして muxer 互換性を担保
    flac)     ffmpeg -loglevel error -y -i "$src" -vn -c:a flac "$out.flac" ;;
    opus)     ffmpeg -loglevel error -y -i "$src" -vn -c:a libopus -b:a 128k "$out.opus" ;;
    m4a-aac)  ffmpeg -loglevel error -y -i "$src" -vn -c:a aac -b:a 192k "$out.m4a" ;;
    m4a-alac) ffmpeg -loglevel error -y -i "$src" -vn -c:a alac "$out.m4a" ;;
    wav)      ffmpeg -loglevel error -y -i "$src" -vn -c:a pcm_s16le "$out.wav" ;;
  esac
  echo "[transcode] $target ← $fname"
  fmt_index=$((fmt_index + 1))
done

# ----- 3. ネスト配置 + cover.jpg (= 最初の item を Artist/Album 構造に) -----
first_ident=$(jq -r '.items[0].identifier' "$MANIFEST")
first_title=$(jq -r '.items[0].title // .items[0].identifier' "$MANIFEST")
first_creator=$(jq -r '.items[0].creator // "Unknown Artist"' "$MANIFEST")
# パス安全化 (= /, \, :, * 等を _ に)
safe_creator=$(printf '%s' "$first_creator" | tr '/\\:*?"<>|' '_________')
safe_album=$(printf '%s' "$first_title" | tr '/\\:*?"<>|' '_________')
nest_dir="$LIB/$safe_creator/$safe_album"
mkdir -p "$nest_dir"
nest_count=0
while IFS= read -r fname; do
  src="$SOURCE/$first_ident/$fname"
  [[ -f "$src" ]] || continue
  cp "$src" "$nest_dir/$fname"
  ((nest_count++))
done < <(jq -r --arg id "$first_ident" '.items[] | select(.identifier==$id) | .files[].name' "$MANIFEST")
echo "[nested] $nest_count files → $nest_dir"

# cover.jpg を埋込 art から抽出 (= 1 曲目から、 art あれば)
first_nested=$(find "$nest_dir" -maxdepth 1 -type f -name '*.mp3' | head -1 || true)
if [[ -n "$first_nested" ]]; then
  if ffmpeg -loglevel error -y -i "$first_nested" -an -vcodec copy "$nest_dir/cover.jpg" 2>/dev/null; then
    echo "[cover] $nest_dir/cover.jpg (extracted from embedded art)"
  else
    echo "[cover] 埋込 art なし (skip)"
    rm -f "$nest_dir/cover.jpg"
  fi
fi

echo "[done] library: $LIB"
find "$LIB" -type f | wc -l | awk '{print "[done] total files: " $1}'
