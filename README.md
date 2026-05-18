# Audova

> Mac ネイティブのオープンソース音楽プレイヤー。 foobar2000 / MusicBee の哲学を macOS に。

## なぜ作るか

Mac には **「無償・機能濃い・ライブラリ管理込み」** の音楽プレイヤーが構造的に欠けている。 Cog は再生エンジンが強いがライブラリ管理が無く、 Swinsian / Doppler / VOX は有償またはクラウド誘導、 Apple Music.app はタグ編集とプレイリスト管理が貧弱で Apple エコシステムに縛られる。

Audova は **macOS 専用の OSS ライブラリ管理プレイヤー** として、 Windows の foobar2000 / MusicBee に相当する選択肢を Mac に提供することを目指す。

## 名前由来

**Audova** = **audio + nova** — 「音の新星」。 完全造語。

## 技術スタック

- **UI**: SwiftUI (+ 必要に応じて AppKit ブリッジ)
- **オーディオ**: [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine) — FLAC / Opus / Vorbis / APE / WavPack / Musepack / DSD / MP3 / AAC / ALAC / WAV
- **ライブラリ DB**: [GRDB.swift](https://github.com/groue/GRDB.swift) (SQLite)
- **対象**: macOS 14 (Sonoma) 以降、 Apple Silicon 優先

技術選定の根拠は [`docs/adr/0001-tech-stack-choice.md`](docs/adr/0001-tech-stack-choice.md) を参照。

## ステータス

**Phase 1 (= MVP) 開発中** — ライブラリスキャン + メタデータ + 再生 + 静的プレイリスト。 詳細は [`docs/ROADMAP.md`](docs/ROADMAP.md)。

## ビルド / 実行

### 要件

- macOS 14 (Sonoma) 以降、 Apple Silicon
- Xcode 26 系 (= Swift 6.3+ toolchain) — App Store からインストール後 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

### CLI

```sh
swift build              # 依存解決 + ビルド (= 初回は数分 / SFBAudioEngine の C++ 依存ビルドあり)
swift run Audova         # 実行
```

### Xcode

```sh
open Package.swift       # SwiftPM project として Xcode で開く
```

Xcode で Run (`Cmd+R`) すると Audova ウィンドウが起動する。

## ライセンス

[MIT](LICENSE)
