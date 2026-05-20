import SwiftUI
import AppKit
import ImageIO

/// アルバムアートを表示する正方形ビュー。 `path` が nil / 読込失敗なら placeholder (`music.note`)。
///
/// ImageIO で要求サイズ (Retina 考慮で ×2) にダウンサンプルして `NSCache` する。
/// 一覧で大量に並んでも原寸画像をメモリに抱えないので軽い。
struct ArtworkImage: View {
    let path: String?
    var size: CGFloat
    var cornerRadius: CGFloat = 4

    var body: some View {
        Group {
            if let image = ArtworkImageCache.shared.image(forPath: path, pointSize: size) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.secondary)
            }
    }
}

/// ダウンサンプル済み `NSImage` の in-memory cache。 key は `"path@pixelSize"`。
final class ArtworkImageCache {
    static let shared = ArtworkImageCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(forPath path: String?, pointSize: CGFloat) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        // Retina を考慮し point の 2 倍を上限ピクセルにする。
        let maxPixel = Int((pointSize * 2).rounded())
        let key = "\(path)@\(maxPixel)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = Self.downsample(path: path, maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func downsample(path: String, maxPixel: Int) -> NSImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
