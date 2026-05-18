# Audova ROADMAP

開発を 4 つの Phase に分け、 scope を厳しく絞ることで「完成しない foobar2000 クローン」 にしないことを最優先とする。

## Phase 1: MVP — 「ライブラリ管理 + プレイリスト」

ゴール: 個人の音楽ライブラリを Audova 上で管理 / 検索 / 再生 / 静的プレイリスト編集できる状態。

スコープ:

- [ ] フォルダ指定 + 再帰スキャン (= 数万曲想定)
- [ ] メタデータ読取 (= タイトル / アーティスト / アルバム / トラック番号 / 年 / ジャンル / 長さ / サンプルレート / ビット深度)
- [ ] SQLite (GRDB.swift) によるライブラリ DB 構築
- [ ] ライブラリ画面 (= アーティスト / アルバム / 曲) の 3 ペイン表示
- [ ] 検索 (= 部分一致、 incremental)
- [ ] 再生 / 一時停止 / シーク / 音量 (SFBAudioEngine)
- [ ] 再生キュー
- [ ] 静的プレイリスト (= 作成 / 名前変更 / 削除 / 曲追加 / 並べ替え)
- [ ] アルバムアート表示 (= タグ埋め込み + フォルダ内 `cover.jpg` フォールバック)
- [ ] アプリケーションメニュー + 標準ショートカット
- [ ] DMG リリース (= notarize 込み) → GitHub Releases

非スコープ (= Phase 2 以降に持ち越し):

- タグ編集 / ファイル書き戻し
- シャッフル / リピート
- スマートプレイリスト
- イコライザ / DSP
- グローバルホットキー
- iCloud / ネットワーク (= UPnP / DLNA / Subsonic / Jellyfin)

## Phase 2: 使い込み品質

ゴール: 「foobar / MusicBee の代わりに常用できる」 状態。

- タグ編集 (= 単曲 / 一括、 ファイル書き戻し)
- ID3v2 / Vorbis Comment / MP4 atom / WMA frame
- シャッフル / リピート (= track / album / playlist)
- グローバルホットキー (= 再生 / 一時停止 / 次へ / 前へ)
- ライブラリ scan の差分更新 (= FSEvents による watch)
- 「未再生」 / 「最近追加」 / 「お気に入り」 デフォルトビュー
- ReplayGain 値の読取 (= 適用は Phase 4)

## Phase 3: ライブラリ拡張

- スマートプレイリスト (= 条件式エディタ)
- カスタムカラム / カラムソート設定の永続化
- レーティング (= 1-5 / 0-100)
- 再生履歴 + 統計 (= last.fm scrobble は別途)
- アートワーク fetch (= MusicBrainz / Cover Art Archive)

## Phase 4: オーディオ品質 / 拡張

- イコライザ (= AUv3 ホスト)
- DSP チェーン (= compressor / limiter / convolution)
- ReplayGain 適用 (= album / track gain)
- ギャップレス再生 (= SFBAudioEngine デフォルト) の検証 + 計測
- プラグイン機構 (= 仕様未確定)

---

## 完成しない foobar2000 クローンにしないための原則

1. **Phase をまたぐ機能要望は当該 Phase の最後にまとめて議論**: Phase 1 中に「シャッフル欲しい」 が来ても Phase 2 まで待つ
2. **Plane Issue で進捗管理**: 機能単位で `AUD-NN` を起票、 1 Phase 完了で集計
3. **ユーザーは 1 人 (= 作者本人) を前提**: 他人の要望は Phase 4 後まで保留、 まず自分が常用できる状態を作ることを優先
