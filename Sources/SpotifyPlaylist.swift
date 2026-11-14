import Foundation

enum SpotifyPlaylist {
    struct Track: Equatable {
        let title: String
        let artists: String
        let durationSeconds: Int
    }

    struct Playlist: Equatable {
        let name: String
        let tracks: [Track]
        let mayHaveMore: Bool
    }

    private static let pageLimit = 100

    enum Failure: LocalizedError {
        case notASpotifyLink
        case noTrackList

        var errorDescription: String? {
            switch self {
            case .notASpotifyLink: String(localized: "That is not a Spotify playlist link.")
            case .noTrackList: String(localized: "Could not read that playlist.")
            }
        }
    }

    static func parseLink(_ link: String) -> (kind: String, id: String)? {
        let pattern = "(?:open\\.spotify\\.com/(?:intl-[a-z-]+/)?|spotify:)(playlist|album)[:/]([A-Za-z0-9]+)"
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let kind = Range(match.range(at: 1), in: text),
              let id = Range(match.range(at: 2), in: text)
        else { return nil }
        return (String(text[kind]), String(text[id]))
    }

    static func read(_ link: String) async throws -> Playlist {
        guard let (kind, id) = parseLink(link) else { throw Failure.notASpotifyLink }
        guard let url = URL(string: "https://open.spotify.com/embed/\(kind)/\(id)") else {
            throw Failure.notASpotifyLink
        }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let page = String(data: data, encoding: .utf8) else { throw Failure.noTrackList }
        return try parse(page)
    }

    static func parse(_ page: String) throws -> Playlist {
        guard let json = nextData(in: page),
              let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["state"] as? [String: Any],
              let data = state["data"] as? [String: Any],
              let entity = data["entity"] as? [String: Any],
              let list = entity["trackList"] as? [[String: Any]]
        else { throw Failure.noTrackList }

        let tracks: [Track] = list.compactMap { row in
            let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !title.isEmpty else { return nil }
            let ms = (row["duration"] as? NSNumber)?.doubleValue ?? 0
            return Track(
                title: title,
                artists: (row["subtitle"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "",
                durationSeconds: Int(ms / 1000))
        }
        guard !tracks.isEmpty else { throw Failure.noTrackList }

        let name = (entity["name"] as? String)?.trimmingCharacters(in: .whitespaces)
        return Playlist(
            name: name?.isEmpty == false ? name! : String(localized: "Spotify playlist"),
            tracks: tracks,
            mayHaveMore: list.count >= pageLimit)
    }

    private static func nextData(in page: String) -> String? {
        guard let open = page.range(of: "<script id=\"__NEXT_DATA__\"", options: .literal),
              let bodyStart = page.range(of: ">", range: open.upperBound..<page.endIndex),
              let close = page.range(of: "</script>", range: bodyStart.upperBound..<page.endIndex)
        else { return nil }
        return String(page[bodyStart.upperBound..<close.lowerBound])
    }
}
