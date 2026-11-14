import Foundation

struct Track: Identifiable, Equatable, Codable, Hashable {
    let videoId: String
    let title: String
    let artist: String
    let thumbnail: String
    let duration: Double
    let artistId: String?
    var explicit: Bool?
    var video: Bool?
    var videoType: String?
    var setVideoId: String?

    var isExplicit: Bool { explicit ?? false }
    var isVideo: Bool { video ?? false }

    var id: String { videoId }
    var thumbnailURL: URL? { artURL(size: 0) }

    var isOfficialVideo: Bool { videoType == "MUSIC_VIDEO_TYPE_OMV" }

    init(videoId: String, title: String, artist: String, thumbnail: String,
         duration: Double, artistId: String? = nil,
         explicit: Bool? = nil, video: Bool? = nil, videoType: String? = nil,
         setVideoId: String? = nil) {
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.thumbnail = thumbnail
        self.duration = duration
        self.artistId = artistId
        self.explicit = explicit
        self.video = video
        self.videoType = videoType
        self.setVideoId = setVideoId
    }

    func artURL(size: Int) -> URL? {
        if LocalMusic.isLocal(videoId) {
            return LocalMusic.shared.localArtURL(for: videoId)
        }
        if Downloads.shared.isDownloaded(videoId),
           let saved = Downloads.shared.localArtURL(for: videoId) { return saved }
        if let saved = AudioCache.shared.cachedArtURL(for: videoId) { return saved }

        if thumbnail.hasPrefix("file:") {
            return URL(string: Downloads.fallbackArt(videoId))
        }
        guard !thumbnail.isEmpty else {
            return videoId.isEmpty ? nil : URL(string: Downloads.fallbackArt(videoId))
        }
        guard size > 0 else { return URL(string: thumbnail) }

        if let r = thumbnail.range(of: "=w[0-9]+-h[0-9]+", options: .regularExpression) {
            return URL(string: thumbnail.replacingCharacters(in: r, with: "=w\(size)-h\(size)"))
        }
        if thumbnail.contains("googleusercontent.com"), !thumbnail.contains("=") {
            return URL(string: thumbnail + "=w\(size)-h\(size)")
        }
        if thumbnail.contains("i.ytimg.com"),
           let r = thumbnail.range(of: "/(default|mqdefault|hqdefault|sddefault)\\.jpg",
                                   options: .regularExpression) {
            let name = size >= 700 ? "maxresdefault" : "sddefault"
            return URL(string: thumbnail.replacingCharacters(in: r, with: "/\(name).jpg"))
        }
        return URL(string: thumbnail)
    }

    init?(json: [String: Any]) {
        guard let vid = json["videoId"] as? String, !vid.isEmpty else { return nil }
        videoId = vid
        title = json["title"] as? String ?? ""
        artist = json["artist"] as? String ?? ""
        thumbnail = json["thumbnail"] as? String ?? ""
        duration = (json["duration"] as? Double) ?? (json["duration"] as? NSNumber)?.doubleValue ?? 0
        artistId = json["artistId"] as? String
    }
}

extension Track {
    var asHomeItem: HomeItem {
        HomeItem(title: title, subtitle: artist,
                 thumbnail: artURL(size: 544)?.absoluteString ?? thumbnail,
                 videoId: videoId, browseId: nil, isCircular: false,
                 duration: duration)
    }
}

struct HomeItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let thumbnail: String
    let videoId: String?
    let browseId: String?
    let isCircular: Bool
    var duration: Double = 0

    var thumbnailURL: URL? { URL(string: thumbnail) }
    var asTrack: Track {
        Track(videoId: videoId ?? "", title: title, artist: subtitle,
              thumbnail: thumbnail, duration: duration)
    }
}

struct HomeSection: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let items: [HomeItem]
    let isSongs: Bool
    var browseId: String?
    var params: String?
}

struct HomeChip: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let params: String?
}

struct MoodItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let colorARGB: UInt
    let browseId: String?
    let params: String?
    var isGenre: Bool = false
}

struct UserPlaylist: Identifiable, Hashable {
    let id: String
    let title: String
    let thumbnail: String

    var thumbnailURL: URL? { URL(string: thumbnail) }
}

struct ArtistSection: Identifiable {
    let id = UUID()
    let title: String
    let songs: [Track]
    let cards: [HomeItem]
}

struct ArtistPage {
    let name: String
    let thumbnail: String
    let subscribers: String
    let sections: [ArtistSection]
    var following: Bool = false
    var channelId: String?

    var thumbnailURL: URL? { URL(string: thumbnail) }
}

struct HomeFeed {
    let chips: [HomeChip]
    var sections: [HomeSection]
    var continuation: String?

    static let empty = HomeFeed(chips: [], sections: [], continuation: nil)
}
