# audova

## 1. Issue / タスク管理

- タスク/チケット管理はしない。 詳細は global `~/.claude/CLAUDE.md` 「task 粒度 / Issue 起票」 参照
- 忘れたくない bug だけ GitHub/Forgejo に ad-hoc 起票 (規律ではなく備忘)

## 2. 技術スタック

詳細は [`docs/adr/0001-tech-stack-choice.md`](docs/adr/0001-tech-stack-choice.md) を必読。 要約:

- SwiftUI (+ 必要に応じて AppKit ブリッジ)
- [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine) — オーディオ
- [GRDB.swift](https://github.com/groue/GRDB.swift) — ライブラリ DB
- macOS 14+ / Apple Silicon 優先

## 3. ビルド / 実行

SwiftPM executable target。 詳細は [README](README.md) ビルド section 参照。

- `swift build` — CLI ビルド (= 初回 ~7 分、 incremental は数秒)
- `swift run Audova` — CLI から起動
- `open Package.swift` — Xcode で開く (= `Cmd+R` で Run)

### 要件

- macOS 14+ / Apple Silicon (動作確認は macOS 26.5)
- Xcode 26 系 + Swift 6.3+ toolchain
- 起動時に **Dock に出る** ように `AudovaApp` で `NSApplicationDelegateAdaptor` 経由 `NSApp.setActivationPolicy(.regular)` を呼んでいる (= SwiftPM executable は Info.plist 不在のため明示 activation が必要)

### 依存

- [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine) 0.12.1 — オーディオ engine + metadata
- [GRDB.swift](https://github.com/groue/GRDB.swift) 7.10.0 — SQLite ラッパー

## 4. ROADMAP

Phase 1-4 は [`docs/ROADMAP.md`](docs/ROADMAP.md) を正本とする。 機能要望が Phase をまたぐ場合は **次 Phase に持ち越し** が原則 (= scope を膨らませない)。

## 5. autopilot

autopilot 不適合プロジェクト。 理由:

- Phase 1 は UI 設計 / SwiftUI ハマりどころが多発見込み、 ユーザーとの対話が頻繁
- 新規機能 spec 策定中 (= 何を作るかを decide する作業が含まれる)

将来 Phase 2 以降で機械的 task (= タグ書き戻し / format 拡張 / migration) の比率が上がったら autopilot section を追加する。

## 6. HANDOFF.md

構造 / max 行数 / 「中断 context 復元用」 専用ルールは global `~/.claude/CLAUDE.md` 「見通しダッシュボード (現況俯瞰) と セッション引き継ぎ (HANDOFF.md) の役割分担」 → 「HANDOFF.md (短期 / 作業単位の記憶)」 参照。 配置は `docs/sessions/HANDOFF.md` (= `.gitignore` で除外、 local only)。
