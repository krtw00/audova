import Foundation

/// M3U8 形式のプレイリストファイルを生成する純関数コレクション (= UI 非依存)。
///
/// 仕様:
/// - 1 行目: `#EXTM3U`
/// - 各曲前: `#EXTINF:<秒>,<artist> - <title>` (秒は durationMs/1000 を四捨五入、不明なら -1)
/// - パス: baseURL (= 保存先ディレクトリ) 基準の相対パス。共通接頭辞が無い場合は絶対パス
/// - 改行: `\n`、エンコード: UTF-8
public enum M3U8Exporter {
    /// トラック配列と保存先ディレクトリ URL から M3U8 文字列を生成する。
    ///
    /// - Parameters:
    ///   - tracks: プレイリストのトラック一覧 (順序そのまま出力)
    ///   - baseURL: 保存先ディレクトリ (= `NSSavePanel` で選んだファイルの `deletingLastPathComponent()`)
    /// - Returns: UTF-8 の M3U8 文字列
    public static func makeContent(tracks: [TrackRow], relativeTo baseURL: URL) -> String {
        var lines: [String] = ["#EXTM3U"]
        for track in tracks {
            let extinf = extinfLine(for: track)
            let trackURL = URL(fileURLWithPath: track.path)
            let pathString = relativePath(from: baseURL, to: trackURL) ?? track.path
            lines.append(extinf)
            lines.append(pathString)
        }
        // 末尾改行なし (各行を \n で結合)
        return lines.joined(separator: "\n")
    }

    // MARK: - internal helpers (internal for testing)

    /// `#EXTINF:<秒>,<label>` 行を生成する。
    static func extinfLine(for track: TrackRow) -> String {
        let seconds: Int
        if let ms = track.durationMs {
            seconds = Int((Double(ms) / 1000.0).rounded())
        } else {
            seconds = -1
        }
        let label = extinfLabel(title: track.title, artistName: nil)
        return "#EXTINF:\(seconds),\(label)"
    }

    /// `#EXTINF` のラベル部分 (`<artist> - <title>` or タイトルのみ or パスのファイル名) を生成する。
    ///
    /// - Note: TrackRow は artistId しか持たないため、artist 名はこのレイヤーでは不明。
    ///   呼び出し側で artistName を解決して渡せるよう引数を用意している。
    static func extinfLabel(title: String?, artistName: String?) -> String {
        switch (artistName, title) {
        case let (artist?, title?):
            return "\(artist) - \(title)"
        case (nil, let title?):
            return title
        case (let artist?, nil):
            return artist
        case (nil, nil):
            return "Unknown"
        }
    }

    /// `baseURL` (ディレクトリ) から `targetURL` (ファイル) への相対パスを計算する。
    ///
    /// 両 URL を path component 分解して共通接頭辞を除去し、残差に `../` を補完する。
    /// 共通接頭辞が無い (別ボリューム等) 場合は `nil` を返す。
    static func relativePath(from baseURL: URL, to targetURL: URL) -> String? {
        // 標準化した絶対パス components を取得する。
        let baseComponents = baseURL.standardized.pathComponents
        let targetComponents = targetURL.standardized.pathComponents

        // ルート component (`/`) が異なる = 別ボリューム → 相対パス不可
        guard baseComponents.first == targetComponents.first else { return nil }

        // 共通接頭辞の長さを求める。
        var commonLength = 0
        let minLength = min(baseComponents.count, targetComponents.count)
        while commonLength < minLength
            && baseComponents[commonLength] == targetComponents[commonLength]
        {
            commonLength += 1
        }

        // 共通接頭辞が base 全体でない場合、 base 側の残差分だけ `../` を付ける。
        let upCount = baseComponents.count - commonLength
        let downComponents = Array(targetComponents[commonLength...])

        var parts: [String] = Array(repeating: "..", count: upCount)
        parts.append(contentsOf: downComponents)

        guard !parts.isEmpty else { return "." }
        return parts.joined(separator: "/")
    }
}
