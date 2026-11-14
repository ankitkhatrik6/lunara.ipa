import SwiftUI
import UIKit
import ImageIO

enum ImageCache {
    static let store: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        c.totalCostLimit = 80 * 1024 * 1024
        return c
    }()

    static func prefetch(_ url: URL?) async {
        guard let target = ThumbSize.url(url, points: nil), !target.isFileURL else { return }
        let key = "\(target.absoluteString)|0" as NSString
        guard store.object(forKey: key) == nil else { return }
        guard let data = await ArtFetch.data(from: target), let decoded = UIImage(data: data) else { return }
        store.setObject(decoded, forKey: key, cost: Int(decoded.size.width * decoded.size.height * 4))
    }

    static func configureDiskCache() {
        let mb = ImageCacheSettings.limitMB
        URLCache.shared = URLCache(memoryCapacity: 16 * 1024 * 1024,
                                   diskCapacity: max(mb, 0) * 1024 * 1024)
    }
}

enum ArtFetch {
    static func data(from url: URL) async -> Data? {
        if let data = try? await URLSession.shared.data(from: url).0, !data.isEmpty {
            return data
        }
        guard url.absoluteString.contains("maxresdefault"),
              let fallback = URL(string: url.absoluteString
                  .replacingOccurrences(of: "maxresdefault", with: "hqdefault"))
        else { return nil }
        return try? await URLSession.shared.data(from: fallback).0
    }
}

enum ThumbSize {
    static func url(_ url: URL?, points: CGFloat?) -> URL? {
        guard let url else { return url }
        let s = url.absoluteString
        guard let range = s.range(of: "=w[0-9]+-h[0-9]+", options: .regularExpression) else {
            return url
        }
        let pixels: Int
        if let points {
            pixels = min(Int((points * UIScreen.main.scale).rounded()), 1080)
        } else {
            let existing = Int(s[range].dropFirst(2).prefix { $0.isNumber }) ?? 0
            pixels = min(max(existing, 544), 1080)
        }
        return URL(string: s.replacingCharacters(in: range, with: "=w\(pixels)-h\(pixels)")) ?? url
    }
}

struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var size: CGFloat?
    var fill = true
    var crossfade = false
    var logo = true
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    private var resolved: URL? { ThumbSize.url(url, points: size) }

    private var decodePixels: Int {
        guard let size, size > 0 else { return 0 }
        return Int(min(size * UIScreen.main.scale, 1080))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
                    .id(ObjectIdentifier(image))
                    .transition(.opacity)
            } else {
                placeholder()
                    .overlay { if logo, Placeholder.self != ArtPlaceholder.self { ArtLogoMark() } }
            }
        }
        .animation(crossfade ? Animation.easeInOut(duration: 0.3) : nil, value: image.map { ObjectIdentifier($0) })
        .task(id: "\(resolved?.absoluteString ?? "")|\(decodePixels)") { await load() }
    }

    private func load() async {
        guard let target = resolved else { return }
        let key = "\(target.absoluteString)|\(decodePixels)" as NSString

        if let cached = ImageCache.store.object(forKey: key) {
            image = cached
            return
        }

        if target.isFileURL {
            guard let data = try? Data(contentsOf: target) else { return }
            guard let decoded = Self.downsample(data, to: size) ?? UIImage(data: data) else { return }
            store(decoded, key: key)
            return
        }

        guard let data = await ArtFetch.data(from: target),
              let decoded = Self.downsample(data, to: size) ?? UIImage(data: data) else { return }
        store(decoded, key: key)
    }

    private func store(_ ui: UIImage, key: NSString) {
        let cost = Int(ui.size.width * ui.size.height * 4)
        ImageCache.store.setObject(ui, forKey: key, cost: cost)
        image = ui
    }

    private static func downsample(_ data: Data, to points: CGFloat?) -> UIImage? {
        guard let points, points > 0,
              let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        let maxPixels = min(points * UIScreen.main.scale, 1080)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

struct ArtLogoMark: View {
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.42
            Image(systemName: "music.note")
                .font(.system(size: side * 0.72, weight: .semibold))
                .foregroundStyle(palette.onSurface.opacity(palette.dark ? 0.32 : 0.25))
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}
