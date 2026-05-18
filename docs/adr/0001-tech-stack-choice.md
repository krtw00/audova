# ADR-0001: 技術スタック選定

## ステータス

採択 (2026-05-18)

## コンテキスト

Audova は macOS 専用の OSS 音楽プレイヤー。 Windows の foobar2000 / MusicBee 相当を Mac で実現することがゴール。 制約:

- ターゲット OS: macOS 14 以降、 Apple Silicon 優先
- クロスプラットフォーム不要 (= 明示的に Mac 専用)
- 対応すべき format: 少なくとも FLAC / Opus / Vorbis / APE / WavPack / Musepack / DSD / MP3 / AAC / ALAC / WAV (= foobar 級)
- 数万曲規模のライブラリ管理 (= 検索 / フィルタ性能)
- 作者は 1 人、 Mac native 経験は浅い (= 学習しながら作る前提)

## 採択

| レイヤー | 採択 | 理由 |
|---|---|---|
| UI | **SwiftUI (必要に応じて AppKit ブリッジ)** | Mac native 開発の最短ルート。 メニューバー / Spotlight / ショートカット / Quick Look / Sparkle 自動更新が薄く乗る。 ARM ネイティブ |
| オーディオ | **[SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine)** | Cog 作者 Stephen F. Booth の OSS。 foobar 級の format 網羅、 ギャップレス再生 / サンプルレート自動切替 (= ハイレゾ) も対応。 MIT |
| DB | **[GRDB.swift](https://github.com/groue/GRDB.swift)** | SQLite ラッパー、 数万件の動的検索でも実績多数。 Swift modern API。 MIT |
| ビルド | **SwiftPM + Xcode** | 標準路線。 SwiftPM で SFBAudioEngine / GRDB を依存追加 |
| 配布 | **GitHub Releases + notarized DMG (+ 将来 Homebrew Cask)** | Mac native アプリ慣行に合わせる |

## 却下案

### A. SwiftUI + AVAudioEngine 単独 (= SFBAudioEngine 不採用)

却下理由: MP3 / AAC / ALAC / WAV / FLAC は AVFoundation でカバーできるが、 **Opus / Vorbis / APE / WavPack / Musepack / DSD が出ない**。 foobar / MusicBee の代わりを目指す動機 (= format 網羅) を満たさない。

### B. Tauri + Rust (= Symphonia + cpal)

却下理由: クロスプラットフォーム要件が無い。 Mac native UX (= メニューバー / Spotlight / ショートカット) を犠牲にしてまで Rust エコシステムに乗る理由が薄い。 Symphonia は decoder 限定的 (= DSD / Musepack 未対応)、 結局 native binding が必要になる。 「Mac native の foobar」 を目指す動機とズレる。

### C. Core Data / SwiftData

却下理由: 数万件規模の動的検索 / 複雑な join で性能 / API 表現力が GRDB に劣る。 schema migration の自由度も GRDB の方が高い。 SwiftData (Core Data 後継) も Phase 1 時点では成熟度に不安。

### D. Electron + ffmpeg

却下理由: B と同じ + バイナリサイズ (= 200MB+) / 起動速度 / バッテリー消費で native に劣る。

## 制約 / リスク

- **SFBAudioEngine C++ 依存**: Swift Package として linker トラブル発生時の調査コストあり。 → Phase 1 開始時に最小 spike で動作確認する
- **SwiftUI 大量テーブルの性能**: 数万行のライブラリ表示で SwiftUI `List` / `Table` が詰まる可能性あり。 → 詰まったら `NSTableView` を `NSViewRepresentable` でブリッジ
- **macOS 14 限定**: 13 以前のユーザーは切り捨て。 → SwiftUI 4 系の API を遠慮なく使うため
- **作者 Mac native 浅い**: Swift / SwiftUI / AppKit の学習コスト。 → 「困ったら AppKit に落とす」 ポリシーを ADR レベルで明文化

## 変更履歴

- 2026-05-18: 初版採択
