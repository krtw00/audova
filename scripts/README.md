# scripts/

Audova 開発 / 検証用の補助スクリプト群。 ライブラリスキャン / メタタグ読取 / 再生 を実機検証するためのテスト用音源プールを **Internet Archive の netlabels コレクション** (= CC ライセンス音楽) から組み立てる。

音源ファイル自体はリポ管理外 (= `~/Music/audova-test-library/` 配下)、 スクリプトと手順だけここに残す。

## 依存

- `python3` (3.10+ 推奨、 標準ライブラリのみ)
- `ffmpeg` (format 変換 / アートワーク抽出)
- `jq` (manifest 読取)
- `bash` (3.2+、 macOS default で OK)

```sh
brew install ffmpeg jq
```

## 使い方

```sh
# 1. archive.org から ~40 曲 DL (= ~/Music/audova-test-library/_source/)
python3 scripts/fetch_test_audio.py

# 2. library/ に配置調整 (= flat + nested + format 多様化 + cover.jpg)
bash scripts/arrange_test_library.sh
```

`AUDOVA_TEST_LIBRARY` 環境変数で出力先を変更可能 (default: `~/Music/audova-test-library`)。

```sh
AUDOVA_TEST_LIBRARY="$HOME/Desktop/audova-test" python3 scripts/fetch_test_audio.py
AUDOVA_TEST_LIBRARY="$HOME/Desktop/audova-test" bash scripts/arrange_test_library.sh
```

## 出力レイアウト

```
~/Music/audova-test-library/
├── _source/
│   ├── manifest.json                       # ライセンス / クレジット情報 (= 必ず参照)
│   ├── <identifier>/
│   │   └── *.mp3                           # 元 DL (= archive.org からの素のファイル)
│   └── ...
└── library/                                 # Audova の「ライブラリ指定先」 はここ
    ├── <identifier>__<file>.mp3            # フラット配置 (大半)
    ├── format-flac__*.flac                 # format 多様化 (5 曲)
    ├── format-opus__*.opus
    ├── format-m4a-aac__*.m4a
    ├── format-m4a-alac__*.m4a
    ├── format-wav__*.wav
    └── <Artist>/<Album>/                    # ネスト配置 (= 再帰スキャン検証用)
        ├── *.mp3
        └── cover.jpg                       # 埋込アートを抽出した cover.jpg
```

## ライセンス

DL される音源はすべて Internet Archive の **netlabels** コレクション (= CC ライセンス音楽プラットフォーム) 由来。 ライセンス内訳は item ごとに異なるが、 全件 CC 系 (= CC0 / CC-BY / CC-BY-SA / CC-BY-NC / CC-BY-NC-SA / CC-BY-NC-ND / PD-mark)。

`_source/manifest.json` に各 item の `licenseurl` / `creator` / `title` が記録されているので、 配布 / 公開する場合は必ず参照すること。 **このリポジトリには音源ファイルを commit しない** (`.gitignore` で `~/Music/audova-test-library/` 配下を扱わない方針)。

## fetch_test_audio.py オプション

| flag | default | 用途 |
|---|---|---|
| `--target` | `40` | 狙う合計曲数 |
| `--per-item` | `3` | 1 item (= 1 アルバム) からの最大曲数 |
| `--item-rows` | `40` | API で取得する item 数 |
| `--seed` | `20260518` | サンプリング seed (= 再現可能性) |
| `--out` | `$AUDOVA_TEST_LIBRARY` | 出力先 root |

## 増量 / やり直し

- **追加 DL**: `--target` を上げて再実行。 既存ファイルはスキップされる
- **完全やり直し**: `~/Music/audova-test-library/_source/` を消してから fetch を再走
- **arrange やり直し**: arrange は実行のたびに `library/` を `rm -rf` する (= 安全)

## 既知の制約

- archive.org の files format が「VBR MP3」 limited のため、 DL される元ファイルは MP3 のみ (= 元 FLAC が手に入る item は少ない)。 FLAC / Opus / AAC / ALAC / WAV は arrange step で MP3 からトランスコード生成
- APE / WavPack / Musepack / DSD は今回未対応 (= Phase 1 検証範囲外、 Phase 2 以降で必要なら別途追加)
- タグの意図的多様化 (= 空タグ / 部分欠 / 文字化け) も未対応 (= Phase 2 タグ書き戻し着手時に別スクリプトで)
