import Foundation
import SFBAudioEngine

/// アートワーク抽出ユーティリティ。
///
/// (1) 埋め込み front cover 優先・無ければ最初の picture
/// (2) 無ければ同フォルダの候補ファイル (cover.jpg / cover.png / folder.jpg / front.jpg) を大文字小文字無視で探す。
public enum ArtworkService {
    /// 抽出済みアートワーク。
    public struct ExtractedArtwork: Sendable, Hashable {
        public let data: Data
        /// "jpg" または "png"。 PNG マジックバイト (89 50 4E 47) なら "png"、 それ以外は "jpg"。
        public let ext: String
    }

    /// トラックファイルからアートワークを抽出する。 見つからなければ `nil`。
    public static func extract(forTrackAt url: URL) -> ExtractedArtwork? {
        // 1. 埋め込み画像
        if let artwork = embeddedArtwork(forTrackAt: url) {
            return artwork
        }
        // 2. フォルダ内候補ファイル
        return folderArtwork(forTrackAt: url)
    }

    // MARK: - private

    private static func embeddedArtwork(forTrackAt url: URL) -> ExtractedArtwork? {
        guard let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url) else {
            return nil
        }
        let pictures = audioFile.metadata.attachedPictures
        guard !pictures.isEmpty else { return nil }

        // front cover 優先、 無ければ最初の 1 枚
        let picture = pictures.first(where: { $0.type == .frontCover }) ?? pictures.first!
        let data = picture.imageData as Data
        return ExtractedArtwork(data: data, ext: imageExt(data))
    }

    private static func folderArtwork(forTrackAt url: URL) -> ExtractedArtwork? {
        let folder = url.deletingLastPathComponent()
        let candidates = ["cover.jpg", "cover.png", "folder.jpg", "front.jpg"]

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return nil
        }
        // 候補の順に探す (priority 順)
        for candidate in candidates {
            if let match = contents.first(where: { $0.lowercased() == candidate }) {
                let fileURL = folder.appendingPathComponent(match)
                if let data = try? Data(contentsOf: fileURL) {
                    return ExtractedArtwork(data: data, ext: imageExt(data))
                }
            }
        }
        return nil
    }

    /// data 先頭バイトで PNG / JPEG を判定する。 それ以外は "jpg" 既定。
    static func imageExt(_ data: Data) -> String {
        guard data.count >= 4 else { return "jpg" }
        // PNG: 89 50 4E 47
        if data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 {
            return "png"
        }
        // JPEG: FF D8
        if data[0] == 0xFF && data[1] == 0xD8 {
            return "jpg"
        }
        return "jpg"
    }
}
