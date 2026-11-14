import Foundation

enum YouTube {

    static let visionUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    private static let visionVersion = "0.1"
    private static let remixVersion = "1.20260213.01.00"
    private static let webUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
    private static let musicPlayer = "https://music.youtube.com/youtubei/v1/player?prettyPrint=false"
    private static let musicSearch = "https://music.youtube.com/youtubei/v1/search?prettyPrint=false"
    private static let musicBrowse = "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false"
    private static let musicSuggest = "https://music.youtube.com/youtubei/v1/music/get_search_suggestions?prettyPrint=false"
    private static let songsFilter = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"

    enum SearchScope: String, CaseIterable, Identifiable {
        case everything, songs, videos, albums, artists
        case communityPlaylists, featuredPlaylists
        case podcasts, episodes, profiles

        var id: String { rawValue }

        var title: String {
            switch self {
            case .everything: return String(localized: "All")
            case .songs: return String(localized: "Songs")
            case .videos: return String(localized: "Videos")
            case .albums: return String(localized: "Albums")
            case .artists: return String(localized: "Artists")
            case .communityPlaylists: return String(localized: "Community playlists")
            case .featuredPlaylists: return String(localized: "Featured playlists")
            case .podcasts: return String(localized: "Podcasts")
            case .episodes: return String(localized: "Episodes")
            case .profiles: return String(localized: "Profiles")
            }
        }

        var params: String? {
            switch self {
            case .everything: return nil
            case .songs: return "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
            case .videos: return "EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D"
            case .albums: return "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"
            case .artists: return "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
            case .communityPlaylists: return "EgeKAQQoAEABagoQAxAEEAoQCRAF"
            case .featuredPlaylists: return "EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D"
            case .podcasts: return "EgWKAQJQAWoKEAkQChAFEAMQBA%3D%3D"
            case .episodes: return "EgWKAQJYAWoKEAkQChAFEAMQBA%3D%3D"
            case .profiles: return "EgWKAQJYAWoSEAUQCRADEAQQEBAVEAoQDhAR"
            }
        }

        var isPlayable: Bool {
            self == .songs || self == .videos || self == .episodes
        }

        var isCircular: Bool { self == .artists || self == .profiles }
    }

    static func searchCards(_ query: String, scope: SearchScope) async -> [HomeItem] {
        guard !scope.isPlayable else { return [] }
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        var body: [String: Any] = [
            "context": ["client": client],
            "query": query,
        ]
        if let params = scope.params { body["params"] = params }

        guard let json = await post(musicSearch, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return [] }

        var out: [HomeItem] = []
        var seen = Set<String>()
        collectSearchCards(json, circular: scope.isCircular, into: &out, seen: &seen)
        return out
    }

    private static func collectSearchCards(_ node: Any, circular: Bool,
                                           into out: inout [HomeItem], seen: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if let r = dict["musicResponsiveListItemRenderer"] as? [String: Any] {
                let nav = r["navigationEndpoint"] as? [String: Any]
                let browse = nav?["browseEndpoint"] as? [String: Any]
                if let id = browse?["browseId"] as? String, !id.isEmpty, seen.insert(id).inserted {
                    let cols = r["flexColumns"] as? [[String: Any]] ?? []
                    out.append(HomeItem(title: flexText(cols, 0),
                                        subtitle: flexText(cols, 1),
                                        thumbnail: musicThumb(r["thumbnail"]),
                                        videoId: nil, browseId: id,
                                        isCircular: circular))
                }
                return
            }
            for (_, v) in dict {
                collectSearchCards(v, circular: circular, into: &out, seen: &seen)
            }
        } else if let arr = node as? [Any] {
            for v in arr { collectSearchCards(v, circular: circular, into: &out, seen: &seen) }
        }
    }

    private static var cachedVisitor: String?
    private static var visitorFetchedAt: Date?
    private static let visitorMaxAge: TimeInterval = 6 * 60 * 60
    private static let visitorLock = NSLock()

    private static var session = URLSession(configuration: .default)
    private static let sessionLock = NSLock()
    private static var currentSession: URLSession { sessionLock.withLock { session } }

    static func freshStart() {
        visitorLock.withLock {
            cachedVisitor = nil
            visitorFetchedAt = nil
        }
        urlCacheLock.withLock { urlCache.removeAll() }
        sourceLock.withLock {
            lastWorked = nil
            benchedUntil.removeAll()
            sourceOf.removeAll()
        }
        let old = sessionLock.withLock { () -> URLSession in
            let old = session
            session = URLSession(configuration: .default)
            return old
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
            old.finishTasksAndInvalidate()
        }
        VideoArtLog.note("fresh start: new visitor id, new connections, sources reset")
    }

    private static var urlCache: [String: (url: URL, duration: Double, expires: Date)] = [:]
    private static let urlCacheLock = NSLock()

    // MARK: - Stream (VISIONOS, uncapped → direct streaming)

    private static var loudnessCache: [String: Double] = [:]
    private static let loudnessLock = NSLock()

    static func loudnessDb(for videoId: String) -> Double? {
        loudnessLock.withLock { loudnessCache[videoId] }
    }

    private static var liveIds = Set<String>()
    private static let liveLock = NSLock()

    static func isLive(_ videoId: String) -> Bool {
        liveLock.withLock { liveIds.contains(videoId) }
    }

    private static func mark(live videoId: String, _ live: Bool) {
        liveLock.withLock {
            if live { liveIds.insert(videoId) } else { liveIds.remove(videoId) }
        }
    }

    private static let sourceLock = NSLock()
    private static var lastWorked: StreamClient?
    private static var benchedUntil: [StreamClient: Date] = [:]
    private static var sourceOf: [String: StreamClient] = [:]
    private static let benchFor: TimeInterval = 10 * 60

    private static func ordered(_ chosen: [StreamClient]) -> [StreamClient] {
        sourceLock.withLock {
            let now = Date()
            let benched = chosen.filter { (benchedUntil[$0] ?? .distantPast) > now }
            var fresh = chosen.filter { !benched.contains($0) }
            if let lastWorked, let at = fresh.firstIndex(of: lastWorked) {
                fresh.insert(fresh.remove(at: at), at: 0)
            }
            return fresh + benched
        }
    }

    private static func bench(_ client: StreamClient) {
        sourceLock.withLock {
            benchedUntil[client] = Date().addingTimeInterval(benchFor)
            if lastWorked == client { lastWorked = nil }
        }
    }

    static func streamFailed(_ url: URL) {
        let client = sourceLock.withLock { sourceOf[url.absoluteString] }
        if let client { bench(client) }
    }

    static func streamURL(for videoId: String) async -> (url: URL, duration: Double)? {
        let hit = urlCacheLock.withLock { () -> (url: URL, duration: Double, expires: Date)? in
            guard let found = urlCache[videoId], found.expires > Date() else { return nil }
            urlCache.removeValue(forKey: videoId)
            return found
        }
        if let hit { return (hit.url, hit.duration) }

        let visitor = await visitorData()
        let clients = ordered(await MainActor.run { StreamPrefs.shared.order })
        let wantsLowest = await MainActor.run {
            let quality = PlaybackPrefs.shared.quality
            return quality == .low
                || (quality == .auto && !Reachability.shared.isUnmetered)
        }

        for client in clients {
            guard let picked = await resolve(videoId, with: client, visitor: visitor,
                                             wantsLowest: wantsLowest) else {
                bench(client)
                continue
            }
            VideoArtLog.note("audio: \(client.rawValue) gave \(videoId)")
            sourceLock.withLock {
                lastWorked = client
                sourceOf[picked.url.absoluteString] = client
                if sourceOf.count > 200 { sourceOf.removeAll() }
            }
            if isLive(videoId) { return (picked.url, picked.duration) }
            urlCacheLock.withLock {
                urlCache[videoId] = (picked.url, picked.duration,
                                     Date().addingTimeInterval(120))
            }
            return (picked.url, picked.duration)
        }
        return nil
    }

    static func videoStreamURL(for videoId: String, maxHeight: Int) async -> URL? {
        await videoStream(for: videoId, maxHeight: maxHeight)?.url
    }

    static func videoStream(for videoId: String, maxHeight: Int) async -> (url: URL, alternate: URL?)? {
        let visitor = await visitorData()
        let preferred = await MainActor.run { StreamPrefs.shared.order }
        let clients = preferred.filter { $0 != .ios } + [StreamClient.ios]

        let answers = await withTaskGroup(of: (Int, [String: Any]?).self) { group -> [Int: [String: Any]?] in
            for (at, client) in clients.enumerated() {
                group.addTask {
                    var context = client.context
                    if let visitor { context["visitorData"] = visitor }
                    let body: [String: Any] = [
                        "context": ["client": context],
                        "videoId": videoId,
                        "contentCheckOk": true, "racyCheckOk": true,
                    ]
                    let answer = await post(musicPlayer, name: client.number, version: client.version,
                                            userAgent: client.userAgent, visitor: visitor, body: body)
                    return (at, answer)
                }
            }
            var out: [Int: [String: Any]?] = [:]
            for await (at, answer) in group { out[at] = answer }
            return out
        }

        for (at, client) in clients.enumerated() {
            let answer = answers[at] ?? nil
            let status = (answer?["playabilityStatus"] as? [String: Any])
            VideoArtLog.note("stream: \(client.rawValue) for \(videoId) → "
                + "\(answer == nil ? "no answer" : (status?["status"] as? String ?? "?"))"
                + ((status?["reason"] as? String).map { " (\($0.prefix(40)))" } ?? ""))
            guard let json = answer,
                  status?["status"] as? String == "OK",
                  let streaming = json["streamingData"] as? [String: Any]
            else { continue }

            let hls = (streaming["hlsManifestUrl"] as? String).flatMap(URL.init(string:))
            guard let formats = streaming["adaptiveFormats"] as? [[String: Any]] else {
                if let hls { return (hls, nil) }
                continue
            }

            var best: [String: Any]?
            var bestHeight = -1
            for f in formats {
                let mime = f["mimeType"] as? String ?? ""
                guard mime.hasPrefix("video/mp4"), mime.contains("avc1"),
                      let u = f["url"] as? String, !u.isEmpty,
                      let height = f["height"] as? Int, height <= maxHeight
                else { continue }
                if height > bestHeight { bestHeight = height; best = f }
            }
            if let best, let u = best["url"] as? String, let url = URL(string: u) {
                if let hls {
                    VideoArtLog.note("stream: hls from \(client.rawValue), file \(bestHeight)p itag \(best["itag"] ?? "?") as alternate")
                    return (hls, url)
                }
                VideoArtLog.note("stream: file \(bestHeight)p itag \(best["itag"] ?? "?") from \(client.rawValue)\(hls == nil ? "" : ", hls alternate")")
                return (url, hls)
            }
            VideoArtLog.note("stream: no H.264 file ≤\(maxHeight)p in \(formats.count) formats\(hls == nil ? "" : ", using hls")")
            if let hls { return (hls, nil) }
        }
        return nil
    }

    private static func resolve(_ videoId: String, with client: StreamClient,
                                visitor: String?,
                                wantsLowest: Bool) async -> (url: URL, duration: Double)? {
        var context = client.context
        if let visitor { context["visitorData"] = visitor }
        let body: [String: Any] = [
            "context": ["client": context],
            "videoId": videoId,
            "contentCheckOk": true, "racyCheckOk": true,
        ]
        let answer = await post(musicPlayer, name: client.number, version: client.version,
                                userAgent: client.userAgent, visitor: visitor, body: body)
        let status = answer?["playabilityStatus"] as? [String: Any]
        guard let json = answer,
              status?["status"] as? String == "OK",
              let streaming = json["streamingData"] as? [String: Any]
        else {
            VideoArtLog.note("audio: \(client.rawValue) for \(videoId) → "
                + (answer == nil ? "no answer" : (status?["status"] as? String ?? "?"))
                + ((status?["reason"] as? String).map { " (\($0.prefix(40)))" } ?? ""))
            return nil
        }

        let details = json["videoDetails"] as? [String: Any]
        if details?["isLive"] as? Bool == true,
           let manifest = streaming["hlsManifestUrl"] as? String,
           let url = URL(string: manifest) {
            mark(live: videoId, true)
            return (url, 0)
        }
        mark(live: videoId, false)

        guard let formats = streaming["adaptiveFormats"] as? [[String: Any]] else { return nil }

        if let config = json["playerConfig"] as? [String: Any],
           let audio = config["audioConfig"] as? [String: Any],
           let db = audio["loudnessDb"] as? Double {
            loudnessLock.withLock { loudnessCache[videoId] = db }
        }

        var best: [String: Any]?
        var bestRate = wantsLowest ? Int.max : -1
        for f in formats {
            let mime = f["mimeType"] as? String ?? ""
            guard mime.hasPrefix("audio/mp4"), let u = f["url"] as? String, !u.isEmpty else { continue }
            let rate = (f["bitrate"] as? Int) ?? (f["averageBitrate"] as? Int) ?? 0
            if wantsLowest ? (rate < bestRate) : (rate > bestRate) { bestRate = rate; best = f }
        }
        guard let best, let u = best["url"] as? String, let url = URL(string: u) else {
            VideoArtLog.note("audio: \(client.rawValue) for \(videoId) → no audio/mp4 in \(formats.count) formats")
            return nil
        }

        var dur = (Double(best["approxDurationMs"] as? String ?? "") ?? 0) / 1000
        if dur <= 0, let ls = details?["lengthSeconds"] as? String {
            dur = Double(ls) ?? 0
        }
        return (url, dur)
    }

    // MARK: - Search (WEB_REMIX music, on-device)

    static func search(_ query: String, scope: SearchScope = .songs) async -> [Track] {
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        var body: [String: Any] = [
            "context": ["client": client],
            "query": query,
        ]
        if let params = scope.params {
            body["params"] = params
        }
        guard let json = await post(musicSearch, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return [] }
        return parseMusicSearch(json)
    }

    static func searchSuggestions(_ query: String) async -> (queries: [String], songs: [Track]) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return ([], []) }

        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "input": q]

        guard let json = await post(musicSuggest, name: "67",
                                    version: remixVersion, userAgent: webUA,
                                    visitor: visitor, body: body),
              let sections = json["contents"] as? [[String: Any]]
        else { return ([], []) }

        var queries: [String] = []
        var songs: [Track] = []
        var seen = Set<String>()

        for section in sections {
            guard let contents = (section["searchSuggestionsSectionRenderer"] as? [String: Any])?["contents"]
                    as? [[String: Any]] else { continue }
            for item in contents {
                if let renderer = item["searchSuggestionRenderer"] as? [String: Any] {
                    let text = runsJoined(renderer["suggestion"])
                    if !text.isEmpty { queries.append(text) }
                } else if item["musicResponsiveListItemRenderer"] != nil {
                    collectTracks(item, into: &songs, seen: &seen)
                }
            }
        }
        return (queries, songs)
    }

    private static func parseMusicSearch(_ json: [String: Any]) -> [Track] {
        guard
            let contents = json["contents"] as? [String: Any],
            let tabbed = contents["tabbedSearchResultsRenderer"] as? [String: Any],
            let tabs = tabbed["tabs"] as? [[String: Any]],
            let tabRenderer = tabs.first?["tabRenderer"] as? [String: Any],
            let content = tabRenderer["content"] as? [String: Any],
            let sectionList = content["sectionListRenderer"] as? [String: Any],
            let sections = sectionList["contents"] as? [[String: Any]]
        else { return [] }

        var out: [Track] = []
        for section in sections {
            guard
                let shelf = section["musicShelfRenderer"] as? [String: Any],
                let items = shelf["contents"] as? [[String: Any]]
            else { continue }
            for item in items {
                guard let r = item["musicResponsiveListItemRenderer"] as? [String: Any] else { continue }
                let videoId = (r["playlistItemData"] as? [String: Any])?["videoId"] as? String
                    ?? overlayVideoId(r["overlay"])
                guard let vid = videoId, !vid.isEmpty else { continue }
                let cols = r["flexColumns"] as? [[String: Any]] ?? []
                let videoType = deepString(r, key: "musicVideoType")
                out.append(Track(
                    videoId: vid,
                    title: flexText(cols, 0),
                    artist: flexArtist(cols),
                    thumbnail: musicThumb(r["thumbnail"]),
                    duration: flexDuration(cols),
                    artistId: flexArtistId(cols),
                    video: videoType.map { $0 != "MUSIC_VIDEO_TYPE_ATV" },
                    videoType: videoType
                ))
                if out.count >= 25 { return out }
            }
        }
        return out
    }

    // MARK: - Home feed (WEB_REMIX browse FEmusic_home)

    static func home(params: String? = nil, continuation: String? = nil) async -> HomeFeed {
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }

        var body: [String: Any] = ["context": ["client": client]]
        if let continuation {
            body["continuation"] = continuation
        } else {
            body["browseId"] = "FEmusic_home"
            if let params { body["params"] = params }
        }

        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return .empty }
        let feed = continuation == nil ? parseHome(json) : parseHomeContinuation(json)
        if !feed.chips.isEmpty { knownChips = feed.chips }
        return feed
    }

    private static func parseHomeContinuation(_ json: [String: Any]) -> HomeFeed {
        guard let cc = json["continuationContents"] as? [String: Any],
              let list = cc["sectionListContinuation"] as? [String: Any]
        else { return .empty }
        let sections = parseShelves(list["contents"] as? [[String: Any]] ?? [])
        return HomeFeed(chips: [], sections: sections,
                        continuation: nextContinuation(list))
    }

    private static func nextContinuation(_ node: [String: Any]) -> String? {
        guard let list = node["continuations"] as? [[String: Any]] else { return nil }
        for entry in list {
            if let next = (entry["nextContinuationData"] as? [String: Any])?["continuation"] as? String {
                return next
            }
        }
        return nil
    }

    private static func parseShelves(_ sections: [[String: Any]]) -> [HomeSection] {
        var out: [HomeSection] = []
        for section in sections {
            guard let shelf = section["musicCarouselShelfRenderer"] as? [String: Any] else { continue }
            let header = (shelf["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
            let title = runsFirst(header?["title"])
            let contentsArr = shelf["contents"] as? [[String: Any]] ?? []
            let isSongs = contentsArr.first?["musicResponsiveListItemRenderer"] != nil
            let items = contentsArr.compactMap(parseHomeItem)
            let more = ((header?["moreContentButton"] as? [String: Any])?["buttonRenderer"]
                as? [String: Any])?["navigationEndpoint"] as? [String: Any]
            let browse = more?["browseEndpoint"] as? [String: Any]
            if !items.isEmpty {
                out.append(HomeSection(title: title, items: items, isSongs: isSongs,
                                       browseId: browse?["browseId"] as? String,
                                       params: browse?["params"] as? String))
            }
        }
        return out
    }

    private static func parseHome(_ json: [String: Any]) -> HomeFeed {
        guard
            let contents = json["contents"] as? [String: Any],
            let browse = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
            let tabs = browse["tabs"] as? [[String: Any]],
            let tab = tabs.first?["tabRenderer"] as? [String: Any],
            let tabContent = tab["content"] as? [String: Any],
            let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
            let sections = sectionList["contents"] as? [[String: Any]]
        else { return .empty }

        return HomeFeed(chips: parseChips(sectionList),
                        sections: parseShelves(sections),
                        continuation: nextContinuation(sectionList))
    }

    private static func parseChips(_ sectionList: [String: Any]) -> [HomeChip] {
        guard let header = sectionList["header"] as? [String: Any],
              let cloud = header["chipCloudRenderer"] as? [String: Any],
              let chips = cloud["chips"] as? [[String: Any]] else { return [] }
        var out: [HomeChip] = [HomeChip(title: "All", params: nil)]
        for c in chips {
            guard let cr = c["chipCloudChipRenderer"] as? [String: Any] else { continue }
            let title = runsFirst(cr["text"])
            let params = ((cr["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["params"] as? String
            if !title.isEmpty { out.append(HomeChip(title: title, params: params)) }
        }
        return out
    }

    // MARK: - Lyrics (YouTube's own, via next -> MPLY browse)

    static func lyrics(videoId: String) async -> (text: String, source: String)? {
        guard !videoId.isEmpty else { return nil }
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }

        let nextURL = "https://music.youtube.com/youtubei/v1/next?prettyPrint=false"
        guard let nextJSON = await post(nextURL, name: "67", version: remixVersion,
                                        userAgent: webUA, visitor: visitor,
                                        body: ["context": ["client": client], "videoId": videoId])
        else { return nil }
        guard let browseId = findLyricsBrowseId(nextJSON) else { return nil }

        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor,
                                    body: ["context": ["client": client], "browseId": browseId]),
              let contents = json["contents"] as? [String: Any],
              let list = contents["sectionListRenderer"] as? [String: Any],
              let sections = list["contents"] as? [[String: Any]],
              let shelf = sections.first?["musicDescriptionShelfRenderer"] as? [String: Any]
        else { return nil }

        let text = runsJoined(shelf["description"])
        guard !text.isEmpty else { return nil }
        let footer = runsJoined(shelf["footer"])
        let source = footer.replacingOccurrences(of: "Source: ", with: "")
        return (text, source.isEmpty ? "YouTube Music" : source)
    }

    private static func findLyricsBrowseId(_ node: Any) -> String? {
        findBrowseId(node, prefix: "MPLY")
    }

    private static func findBrowseId(_ node: Any, prefix: String) -> String? {
        if let dict = node as? [String: Any] {
            if let id = dict["browseId"] as? String, id.hasPrefix(prefix) { return id }
            for (_, v) in dict {
                if let found = findBrowseId(v, prefix: prefix) { return found }
            }
        } else if let arr = node as? [Any] {
            for v in arr {
                if let found = findBrowseId(v, prefix: prefix) { return found }
            }
        }
        return nil
    }

    // MARK: - Related (what powers the ever-changing home rails)

    static func related(videoId: String) async -> [HomeSection] {
        guard !videoId.isEmpty else { return [] }
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }

        let nextURL = "https://music.youtube.com/youtubei/v1/next?prettyPrint=false"
        guard let nextJSON = await post(nextURL, name: "67", version: remixVersion,
                                        userAgent: webUA, visitor: visitor,
                                        body: ["context": ["client": client], "videoId": videoId]),
              let browseId = findBrowseId(nextJSON, prefix: "MPTR")
        else { return [] }

        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor,
                                    body: ["context": ["client": client], "browseId": browseId])
        else { return [] }

        var out: [HomeSection] = []
        collectShelves(json, into: &out)
        return out
    }

    static let supermixPlaylistId = "RDTMAK5uy_kset8DisdE7LSD4TNjEVvrKRTmG7a56sY"

    static func mix(playlistId: String) async -> [Track] {
        guard !playlistId.isEmpty else { return [] }
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let nextURL = "https://music.youtube.com/youtubei/v1/next?prettyPrint=false"
        guard let json = await post(nextURL, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor,
                                    body: ["context": ["client": client],
                                           "playlistId": playlistId])
        else { return [] }

        var out: [Track] = []
        var seen = Set<String>()
        collectPanelTracks(json, into: &out, seen: &seen)
        return out
    }

    private static func collectPanelTracks(_ node: Any, into out: inout [Track],
                                           seen: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if let r = dict["playlistPanelVideoRenderer"] as? [String: Any] {
                if let vid = r["videoId"] as? String, !vid.isEmpty, seen.insert(vid).inserted {
                    let byline = runsJoined(r["longBylineText"])
                    let track = Track(videoId: vid,
                                      title: runsFirst(r["title"]),
                                      artist: byline.components(separatedBy: " • ").first?
                                          .trimmingCharacters(in: .whitespaces) ?? byline,
                                      thumbnail: panelThumb(r["thumbnail"]),
                                      duration: seconds(runsFirst(r["lengthText"])),
                                      artistId: panelArtistId(r["longBylineText"]),
                                      explicit: deepContains(r["badges"], "MUSIC_EXPLICIT_BADGE"),
                                      video: deepString(r, key: "musicVideoType")
                                          .map { $0 != "MUSIC_VIDEO_TYPE_ATV" })
                    if ContentPrefs.allows(track) { out.append(track) }
                }
                return
            }
            for (_, v) in dict { collectPanelTracks(v, into: &out, seen: &seen) }
        } else if let arr = node as? [Any] {
            for v in arr { collectPanelTracks(v, into: &out, seen: &seen) }
        }
    }

    private static func panelThumb(_ obj: Any?) -> String {
        guard let thumbs = (obj as? [String: Any])?["thumbnails"] as? [[String: Any]]
        else { return musicThumb(obj) }
        let raw = thumbs.last?["url"] as? String ?? ""
        if let r = raw.range(of: "=w[0-9]+-h[0-9]+", options: .regularExpression) {
            return raw.replacingCharacters(in: r, with: "=w544-h544")
        }
        return raw
    }

    private static func panelArtistId(_ obj: Any?) -> String? {
        guard let runs = (obj as? [String: Any])?["runs"] as? [[String: Any]] else { return nil }
        for run in runs {
            if let nav = run["navigationEndpoint"] as? [String: Any],
               let browse = nav["browseEndpoint"] as? [String: Any],
               let id = browse["browseId"] as? String, id.hasPrefix("UC") {
                return id
            }
        }
        return nil
    }

    private static func seconds(_ text: String) -> Double {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return 0 }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    private static func collectShelves(_ node: Any, into out: inout [HomeSection]) {
        if let dict = node as? [String: Any] {
            if let shelf = dict["musicCarouselShelfRenderer"] as? [String: Any] {
                let header = (shelf["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
                let contentsArr = shelf["contents"] as? [[String: Any]] ?? []
                let isSongs = contentsArr.first?["musicResponsiveListItemRenderer"] != nil
                let items = contentsArr.compactMap(parseHomeItem)
                if !items.isEmpty {
                    out.append(HomeSection(title: runsFirst(header?["title"]),
                                           items: items, isSongs: isSongs))
                }
                return
            }
            for (_, v) in dict { collectShelves(v, into: &out) }
        } else if let arr = node as? [Any] {
            for v in arr { collectShelves(v, into: &out) }
        }
    }

    // MARK: - Artist

    private static let artistsFilter = "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
    private static var artistIdCache: [String: String] = [:]

    static func resolveArtistId(name: String) async -> String? {
        let key = name.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        if let hit = artistIdCache[key] { return hit }

        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = [
            "context": ["client": client],
            "query": key,
            "params": artistsFilter,
        ]
        guard let json = await post(musicSearch, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return nil }

        var found: String?
        collectFirstArtist(json, name: key, into: &found)
        if let found { artistIdCache[key] = found }
        return found
    }

    private static func collectFirstArtist(_ node: Any, name: String, into found: inout String?) {
        guard found == nil else { return }
        if let dict = node as? [String: Any] {
            if let r = dict["musicResponsiveListItemRenderer"] as? [String: Any] {
                let nav = r["navigationEndpoint"] as? [String: Any]
                if let id = (nav?["browseEndpoint"] as? [String: Any])?["browseId"] as? String,
                   id.hasPrefix("UC") {
                    let cols = r["flexColumns"] as? [[String: Any]] ?? []
                    let title = flexText(cols, 0)
                    if title.compare(name, options: .caseInsensitive) == .orderedSame {
                        found = id
                    } else if found == nil {
                        found = id
                    }
                }
                return
            }
            for (_, v) in dict { collectFirstArtist(v, name: name, into: &found) }
        } else if let arr = node as? [Any] {
            for v in arr { collectFirstArtist(v, name: name, into: &found) }
        }
    }

    static func artist(browseId: String) async -> ArtistPage? {
        guard browseId.hasPrefix("UC") else { return nil }
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "browseId": browseId]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return nil }

        let header = json["header"] as? [String: Any]
        let immersive = header?["musicImmersiveHeaderRenderer"] as? [String: Any]
        let visual = header?["musicVisualHeaderRenderer"] as? [String: Any]
        let plain = header?["musicHeaderRenderer"] as? [String: Any]

        let name = [immersive, visual, plain].compactMap { $0 }
            .map { runsFirst($0["title"]) }.first(where: { !$0.isEmpty }) ?? ""
        guard !name.isEmpty else { return nil }

        var thumb = musicThumb(immersive?["thumbnail"])
        if thumb.isEmpty { thumb = musicThumb(visual?["foregroundThumbnail"]) }

        var subscribers = ""
        if let btn = (immersive?["subscriptionButton2"] as? [String: Any])?["subscribeButtonRenderer"] as? [String: Any] {
            subscribers = runsFirst(btn["subscriberCountWithSubscribeText"])
        }
        if subscribers.isEmpty,
           let btn = (immersive?["subscriptionButton"] as? [String: Any])?["subscribeButtonRenderer"] as? [String: Any] {
            subscribers = runsFirst(btn["longSubscriberCountText"])
            if subscribers.isEmpty { subscribers = runsFirst(btn["shortSubscriberCountText"]) }
        }

        var following = false
        var channelId: String?
        for key in ["subscriptionButton2", "subscriptionButton"] {
            guard let btn = (immersive?[key] as? [String: Any])?["subscribeButtonRenderer"]
                    as? [String: Any] else { continue }
            if let subscribed = btn["subscribed"] as? Bool { following = subscribed }
            if channelId == nil {
                channelId = (btn["channelId"] as? String)
                    ?? ((btn["serviceEndpoints"] as? [[String: Any]])?
                        .compactMap { ($0["subscribeEndpoint"] as? [String: Any])?["channelIds"] as? [String] }
                        .first?.first)
            }
            if channelId != nil { break }
        }

        var sections: [ArtistSection] = []
        if let contents = json["contents"] as? [String: Any],
           let browse = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = browse["tabs"] as? [[String: Any]],
           let tab = tabs.first?["tabRenderer"] as? [String: Any],
           let tabContent = tab["content"] as? [String: Any],
           let list = tabContent["sectionListRenderer"] as? [String: Any],
           let items = list["contents"] as? [[String: Any]] {
            for section in items {
                if let shelf = section["musicShelfRenderer"] as? [String: Any] {
                    var tracks: [Track] = []
                    var seen = Set<String>()
                    collectTracks(shelf, into: &tracks, seen: &seen)
                    if !tracks.isEmpty {
                        sections.append(ArtistSection(title: runsFirst(shelf["title"]),
                                                      songs: tracks, cards: []))
                    }
                } else if let shelf = section["musicCarouselShelfRenderer"] as? [String: Any] {
                    let head = (shelf["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
                    let cards = (shelf["contents"] as? [[String: Any]] ?? []).compactMap(parseHomeItem)
                    if !cards.isEmpty {
                        sections.append(ArtistSection(title: runsFirst(head?["title"]),
                                                      songs: [], cards: cards))
                    }
                }
            }
        }

        return ArtistPage(name: name, thumbnail: thumb, subscribers: subscribers,
                          sections: sections, following: following,
                          channelId: channelId ?? browseId)
    }

    // MARK: - Moods & genres

    static var knownChips: [HomeChip] = []

    static func moodShelves(for moodTitle: String) async -> [HomeSection] {
        if knownChips.isEmpty { _ = await home() }
        let wanted = chipName(for: moodTitle)
        guard let chip = knownChips.first(where: { $0.title.lowercased() == wanted }),
              let params = chip.params
        else { return [] }
        return await home(params: params).sections.filter { !$0.items.isEmpty }
    }

    private static func chipName(for moodTitle: String) -> String {
        switch moodTitle.lowercased() {
        case "chill": "relax"
        case "energy boosters": "energize"
        default: moodTitle.lowercased()
        }
    }

    static func moods() async -> [MoodItem] {
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "browseId": "FEmusic_moods_and_genres"]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return [] }
        guard
            let contents = json["contents"] as? [String: Any],
            let browse = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
            let tabs = browse["tabs"] as? [[String: Any]],
            let tab = tabs.first?["tabRenderer"] as? [String: Any],
            let tabContent = tab["content"] as? [String: Any],
            let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
            let sections = sectionList["contents"] as? [[String: Any]]
        else { return [] }

        var out: [MoodItem] = []
        for (at, section) in sections.enumerated() {
            let grid = section["gridRenderer"] as? [String: Any]
            let items = grid?["items"] as? [[String: Any]] ?? []
            let heading = runsFirst((grid?["header"] as? [String: Any])?["gridHeaderRenderer"]
                .flatMap { ($0 as? [String: Any])?["title"] }).lowercased()
            let isGenre = heading.contains("genre") || (heading.isEmpty && at > 0)
            for item in items {
                guard let b = item["musicNavigationButtonRenderer"] as? [String: Any] else { continue }
                let title = runsFirst(b["buttonText"])
                guard !title.isEmpty else { continue }
                let color = ((b["solid"] as? [String: Any])?["leftStripeColor"] as? NSNumber)?.uintValue ?? 0xFF29_2929
                let click = (b["clickCommand"] as? [String: Any])?["browseEndpoint"] as? [String: Any]
                out.append(MoodItem(title: title, colorARGB: color,
                                    browseId: click?["browseId"] as? String,
                                    params: click?["params"] as? String,
                                    isGenre: isGenre))
            }
        }
        return out
    }

    static func moodPlaylists(browseId: String, params: String?) async -> [HomeItem] {
        await shelfPage(browseId: browseId, params: params).items
    }

    static func shelfPage(
        browseId: String,
        params: String?,
        continuation: String? = nil,
    ) async -> (items: [HomeItem], next: String?) {
        guard !browseId.isEmpty else { return ([], nil) }
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        var body: [String: Any] = ["context": ["client": client], "browseId": browseId]
        if let params { body["params"] = params }
        if let continuation { body["continuation"] = continuation }
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return ([], nil) }
        var out: [HomeItem] = []
        var seen = Set<String>()
        collectCards(json, into: &out, seen: &seen)
        return (out, anyContinuation(json))
    }

    private static func anyContinuation(_ node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if let found = nextContinuation(dict) { return found }
            for value in dict.values {
                if let found = anyContinuation(value) { return found }
            }
        } else if let list = node as? [Any] {
            for value in list {
                if let found = anyContinuation(value) { return found }
            }
        }
        return nil
    }

    private static func parseHomeItem(_ item: [String: Any]) -> HomeItem? {
        if let r = item["musicTwoRowItemRenderer"] as? [String: Any] {
            let title = runsFirst(r["title"])
            guard !title.isEmpty else { return nil }
            let nav = r["navigationEndpoint"] as? [String: Any]
            let videoId = (nav?["watchEndpoint"] as? [String: Any])?["videoId"] as? String
            var browseId = (nav?["browseEndpoint"] as? [String: Any])?["browseId"] as? String
            if browseId == nil, let pid = (nav?["watchPlaylistEndpoint"] as? [String: Any])?["playlistId"] as? String {
                browseId = "VL" + pid
            }
            return HomeItem(
                title: title,
                subtitle: runsJoined(r["subtitle"]),
                thumbnail: musicThumb(r["thumbnailRenderer"]),
                videoId: videoId,
                browseId: browseId,
                isCircular: browseId?.hasPrefix("UC") ?? false,
            )
        }
        if let r = item["musicResponsiveListItemRenderer"] as? [String: Any] {
            let vid = (r["playlistItemData"] as? [String: Any])?["videoId"] as? String
                ?? overlayVideoId(r["overlay"])
            guard let v = vid, !v.isEmpty else { return nil }
            let cols = r["flexColumns"] as? [[String: Any]] ?? []
            return HomeItem(title: flexText(cols, 0), subtitle: flexArtist(cols),
                            thumbnail: musicThumb(r["thumbnail"]), videoId: v,
                            browseId: nil, isCircular: false,
                            duration: flexDuration(cols))
        }
        return nil
    }

    // MARK: - Playlist / album tracks

    static func playlist(browseId: String) async -> [Track] {
        guard !browseId.isEmpty else { return [] }
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "browseId": browseId]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return [] }

        var out: [Track] = []
        var seen = Set<String>()
        collectTracks(json, into: &out, seen: &seen)
        return out
    }

    private static func deepString(_ node: Any, key: String) -> String? {
        if let dict = node as? [String: Any] {
            if let hit = dict[key] as? String { return hit }
            for (_, v) in dict {
                if let hit = deepString(v, key: key) { return hit }
            }
        } else if let arr = node as? [Any] {
            for v in arr {
                if let hit = deepString(v, key: key) { return hit }
            }
        }
        return nil
    }

    private static func deepContains(_ node: Any?, _ needle: String) -> Bool {
        guard let node else { return false }
        if let text = node as? String { return text == needle }
        if let dict = node as? [String: Any] {
            return dict.values.contains { deepContains($0, needle) }
        }
        if let arr = node as? [Any] {
            return arr.contains { deepContains($0, needle) }
        }
        return false
    }

    private static func collectTracks(_ node: Any, into out: inout [Track], seen: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if let r = dict["musicResponsiveListItemRenderer"] as? [String: Any] {
                let itemData = r["playlistItemData"] as? [String: Any]
                let vid = itemData?["videoId"] as? String ?? overlayVideoId(r["overlay"])
                if let v = vid, !v.isEmpty, seen.insert(v).inserted {
                    let cols = r["flexColumns"] as? [[String: Any]] ?? []
                    let explicit = deepContains(r["badges"], "MUSIC_EXPLICIT_BADGE")
                    let videoType = deepString(r, key: "musicVideoType")
                    let track = Track(videoId: v, title: flexText(cols, 0),
                                      artist: flexArtist(cols),
                                      thumbnail: musicThumb(r["thumbnail"]),
                                      duration: flexDuration(cols),
                                      artistId: flexArtistId(cols),
                                      explicit: explicit,
                                      video: videoType.map { $0 != "MUSIC_VIDEO_TYPE_ATV" },
                                      videoType: videoType,
                                      setVideoId: itemData?["playlistSetVideoId"] as? String)
                    if ContentPrefs.allows(track) { out.append(track) }
                }
                return
            }
            for (_, v) in dict { collectTracks(v, into: &out, seen: &seen) }
        } else if let arr = node as? [Any] {
            for v in arr { collectTracks(v, into: &out, seen: &seen) }
        }
    }

    static func trackMetadata(videoId: String) async -> Track? {
        guard !videoId.isEmpty else { return nil }
        let visitor = await visitorData()
        let client = StreamClient.ios
        var context = client.context
        if let visitor { context["visitorData"] = visitor }
        let body: [String: Any] = [
            "context": ["client": context],
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
        ]
        guard let json = await post(musicPlayer, name: client.number, version: client.version,
                                    userAgent: client.userAgent, visitor: visitor, body: body),
              let details = json["videoDetails"] as? [String: Any]
        else { return nil }
        let title = details["title"] as? String ?? ""
        guard !title.isEmpty else { return nil }
        let artist = details["author"] as? String ?? ""
        let length = Double(details["lengthSeconds"] as? String ?? "") ?? 0
        let thumbs = (details["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let thumb = thumbs?.last?["url"] as? String ?? Downloads.fallbackArt(videoId)
        return Track(
            videoId: videoId,
            title: title,
            artist: artist,
            thumbnail: thumb,
            duration: length,
            artistId: details["channelId"] as? String
        )
    }

    private static func collectCards(_ node: Any, into out: inout [HomeItem], seen: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if dict["musicTwoRowItemRenderer"] != nil, let item = parseHomeItem(dict),
               let bid = item.browseId, seen.insert(bid).inserted {
                out.append(item)
                return
            }
            if let r = dict["musicResponsiveListItemRenderer"] as? [String: Any],
               let item = parseListCard(r), let bid = item.browseId,
               seen.insert(bid).inserted {
                out.append(item)
                return
            }
            for (_, v) in dict { collectCards(v, into: &out, seen: &seen) }
        } else if let arr = node as? [Any] {
            for v in arr { collectCards(v, into: &out, seen: &seen) }
        }
    }

    private static func parseListCard(_ r: [String: Any]) -> HomeItem? {
        let nav = r["navigationEndpoint"] as? [String: Any]
        guard let browseId = (nav?["browseEndpoint"] as? [String: Any])?["browseId"] as? String,
              !browseId.isEmpty else { return nil }
        let cols = r["flexColumns"] as? [[String: Any]] ?? []
        let title = flexText(cols, 0)
        guard !title.isEmpty else { return nil }
        return HomeItem(title: title, subtitle: flexText(cols, 1),
                        thumbnail: musicThumb(r["thumbnail"]), videoId: nil,
                        browseId: browseId,
                        isCircular: browseId.hasPrefix("UC"))
    }

    // MARK: - Charts (what's trending on YouTube Music)

    static func charts() async -> (songs: [Track], artists: [HomeItem]) {
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client],
                                   "browseId": "FEmusic_charts",
                                   "params": "ggMGCgQIgAQ%3D"]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return ([], []) }

        var songs: [Track] = []
        var songSeen = Set<String>()
        collectTracks(json, into: &songs, seen: &songSeen)
        collectChartVideos(json, into: &songs, seen: &songSeen)

        var cards: [HomeItem] = []
        var cardSeen = Set<String>()
        collectCards(json, into: &cards, seen: &cardSeen)
        let artists = cards.filter { $0.browseId?.hasPrefix("UC") == true }

        if songs.count < 6 {
            let feed = await home()
            for item in feed.sections.flatMap(\.items) {
                guard let vid = item.videoId, !vid.isEmpty, songSeen.insert(vid).inserted else { continue }
                songs.append(item.asTrack)
                if songs.count >= 12 { break }
            }
        }

        return (songs, artists)
    }

    private static func collectChartVideos(_ node: Any, into out: inout [Track],
                                           seen: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if dict["musicTwoRowItemRenderer"] != nil, let item = parseHomeItem(dict),
               let vid = item.videoId, !vid.isEmpty, seen.insert(vid).inserted {
                out.append(item.asTrack)
                return
            }
            for (_, v) in dict { collectChartVideos(v, into: &out, seen: &seen) }
        } else if let arr = node as? [Any] {
            for v in arr { collectChartVideos(v, into: &out, seen: &seen) }
        }
    }

    // MARK: - Parsing helpers

    private static func runsFirst(_ obj: Any?) -> String {
        guard let o = obj as? [String: Any] else { return "" }
        if let runs = o["runs"] as? [[String: Any]], let f = runs.first?["text"] as? String { return f }
        return o["simpleText"] as? String ?? ""
    }

    private static func runsJoined(_ obj: Any?) -> String {
        guard let o = obj as? [String: Any], let runs = o["runs"] as? [[String: Any]] else {
            return runsFirst(obj)
        }
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    private static func flexText(_ cols: [[String: Any]], _ i: Int) -> String {
        guard cols.indices.contains(i),
              let r = cols[i]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = r["text"] as? [String: Any] else { return "" }
        if let runs = text["runs"] as? [[String: Any]], let f = runs.first?["text"] as? String { return f }
        return text["simpleText"] as? String ?? ""
    }

    private static func flexArtist(_ cols: [[String: Any]]) -> String {
        guard cols.indices.contains(1),
              let r = cols[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = r["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]] else { return "" }
        for run in runs {
            guard let nav = run["navigationEndpoint"] as? [String: Any],
                  let browse = nav["browseEndpoint"] as? [String: Any],
                  let id = browse["browseId"] as? String, id.hasPrefix("UC"),
                  let name = run["text"] as? String,
                  !name.trimmingCharacters(in: .whitespaces).isEmpty
            else { continue }
            return name.trimmingCharacters(in: .whitespaces)
        }
        for run in runs {
            let t = (run["text"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            if !t.isEmpty && t != "•" { return t }
        }
        return ""
    }

    private static func flexDuration(_ cols: [[String: Any]]) -> Double {
        guard cols.indices.contains(1),
              let r = cols[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = r["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]] else { return 0 }
        for run in runs.reversed() {
            let t = (run["text"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let parts = t.split(separator: ":")
            guard parts.count == 2 || parts.count == 3,
                  parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
                  let seconds = parts.compactMap({ Double($0) }).reduce(0, { $0 * 60 + $1 }) as Double?
            else { continue }
            return seconds
        }
        return 0
    }

    private static func flexArtistId(_ cols: [[String: Any]]) -> String? {
        guard cols.indices.contains(1),
              let r = cols[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = r["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]] else { return nil }
        for run in runs {
            if let nav = run["navigationEndpoint"] as? [String: Any],
               let browse = nav["browseEndpoint"] as? [String: Any],
               let id = browse["browseId"] as? String, id.hasPrefix("UC") {
                return id
            }
        }
        return nil
    }

    private static func overlayVideoId(_ overlay: Any?) -> String? {
        guard
            let o = overlay as? [String: Any],
            let mo = o["musicItemThumbnailOverlayRenderer"] as? [String: Any],
            let c = mo["content"] as? [String: Any],
            let btn = c["musicPlayButtonRenderer"] as? [String: Any],
            let nav = btn["playNavigationEndpoint"] as? [String: Any],
            let watch = nav["watchEndpoint"] as? [String: Any]
        else { return nil }
        return watch["videoId"] as? String
    }

    private static func musicThumb(_ obj: Any?) -> String {
        guard
            let mtr = (obj as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any],
            let t = mtr["thumbnail"] as? [String: Any],
            let thumbs = t["thumbnails"] as? [[String: Any]]
        else { return "" }
        let raw = thumbs.last?["url"] as? String ?? ""
        if let r = raw.range(of: "=w[0-9]+-h[0-9]+", options: .regularExpression) {
            return raw.replacingCharacters(in: r, with: "=w544-h544")
        }
        return raw
    }

    // MARK: - InnerTube POST

    private static func post(_ endpoint: String, name: String, version: String,
                             userAgent: String, visitor: String?, body: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: endpoint),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = payload
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(name, forHTTPHeaderField: "X-Youtube-Client-Name")
        req.setValue(version, forHTTPHeaderField: "X-Youtube-Client-Version")
        req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        req.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        if let visitor { req.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id") }
        let data: Data
        do {
            data = try await currentSession.data(for: req).0
        } catch {
            let e = error as NSError
            VideoArtLog.note("request \(url.lastPathComponent) as \(name) failed: \(e.domain) \(e.code)")
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    // MARK: - visitorData (music.youtube.com/sw.js_data)

    private static func visitorData() async -> String? {
        let kept = visitorLock.withLock { () -> String? in
            guard let cachedVisitor, let at = visitorFetchedAt,
                  Date().timeIntervalSince(at) < visitorMaxAge else { return nil }
            return cachedVisitor
        }
        if let kept { return kept }
        guard let url = URL(string: "https://music.youtube.com/sw.js_data") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        guard let (data, _) = try? await currentSession.data(for: req), data.count > 5 else {
            return visitorLock.withLock { cachedVisitor }
        }
        let jsonData = data.subdata(in: 5..<data.count)
        guard
            let arr = try? JSONSerialization.jsonObject(with: jsonData) as? [Any],
            let a0 = arr.first as? [Any], a0.count > 2,
            let a2 = a0[2] as? [Any]
        else { return nil }
        for item in a2 {
            if let s = item as? String, s.count >= 3, s.hasPrefix("Cg") {
                let third = s[s.index(s.startIndex, offsetBy: 2)]
                if third == "t" || third == "s" {
                    visitorLock.withLock {
                        cachedVisitor = s
                        visitorFetchedAt = Date()
                    }
                    return s
                }
            }
        }
        return nil
    }
}
