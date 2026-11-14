import Foundation

enum YouTubeLink: Equatable {
    case song(String)
    case playlist(String)

    static func parse(_ raw: String) -> YouTubeLink? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let found = firstURL(in: text), let url = URL(string: found),
              let host = url.host?.lowercased() else { return nil }

        let isYouTube = host.hasSuffix("youtube.com") || host.hasSuffix("youtu.be")
            || host.hasSuffix("youtube-nocookie.com")
        guard isYouTube else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func query(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }

        if host.hasSuffix("youtu.be") {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !id.isEmpty { return .song(id) }
        }
        if let id = query("v") { return .song(id) }
        if let list = query("list") { return .playlist(list) }
        let path = url.path
        for prefix in ["/embed/", "/shorts/", "/v/", "/live/"] where path.hasPrefix(prefix) {
            let id = String(path.dropFirst(prefix.count)).components(separatedBy: "/").first ?? ""
            if !id.isEmpty { return .song(id) }
        }
        return nil
    }

    var browseId: String? {
        guard case .playlist(let id) = self else { return nil }
        return id.hasPrefix("VL") ? id : "VL" + id
    }

    private static func firstURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        let match = detector.firstMatch(in: text, range: range)
        return match?.url?.absoluteString ?? text
    }
}
