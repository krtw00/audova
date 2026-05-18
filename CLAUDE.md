# audova

## 1. Plane (Issue 管理)

- identifier: `AUD` — https://plane.codenica.dev/codenica/projects/9e973fd5-4a6e-48bd-8e50-4580176c3cb8/issues/
- 共通運用 (Issue 起票 / commit msg / 状況確認) は global `~/.claude/CLAUDE.md` 「プロジェクト管理 (Plane)」 参照

## 2. 技術スタック

詳細は [`docs/adr/0001-tech-stack-choice.md`](docs/adr/0001-tech-stack-choice.md) を必読。 要約:

- SwiftUI (+ 必要に応じて AppKit ブリッジ)
- [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine) — オーディオ
- [GRDB.swift](https://github.com/groue/GRDB.swift) — ライブラリ DB
- macOS 14+ / Apple Silicon 優先

## 3. ビルド / 実行

Phase 1 開始時に SwiftPM / Xcode project を整備し本 section を更新する (= 現状未整備)。

## 4. ROADMAP

Phase 1-4 は [`docs/ROADMAP.md`](docs/ROADMAP.md) を正本とする。 機能要望が Phase をまたぐ場合は **次 Phase に持ち越し** が原則 (= scope を膨らませない)。

## 5. autopilot

autopilot 不適合プロジェクト。 理由:

- Phase 1 は UI 設計 / SwiftUI ハマりどころが多発見込み、 ユーザーとの対話が頻繁
- 新規機能 spec 策定中 (= 何を作るかを decide する作業が含まれる)

将来 Phase 2 以降で機械的 task (= タグ書き戻し / format 拡張 / migration) の比率が上がったら autopilot section を追加する。

## 6. HANDOFF.md

構造 / max 行数 / 「中断 context 復元用」 専用ルールは global `~/.claude/CLAUDE.md` 「プロジェクト管理 (Plane) と セッション引き継ぎ (HANDOFF.md) の役割分担」 → 「HANDOFF.md (短期 / 作業単位の記憶)」 参照。 配置は `docs/sessions/HANDOFF.md` (= `.gitignore` で除外、 local only)。
