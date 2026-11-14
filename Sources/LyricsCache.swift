import Foundation

actor LyricsCache {
    static let shared = LyricsCache()

    private var store: [String: [LyricsCandidate]] = [:]
    private var inFlight: Set<String> = []
    private let limit = 40
    private var order: [String] = []

    func candidates(for videoId: String) -> [LyricsCandidate]? {
        store[videoId]
    }

    @discardableResult
    func warm(videoId: String, title: String, artist: String,
              duration: Double) async -> [LyricsCandidate] {
        if let hit = store[videoId] { return hit }
        guard !inFlight.contains(videoId), !videoId.isEmpty else { return [] }
        inFlight.insert(videoId)
        defer { inFlight.remove(videoId) }

        let imported = LocalMusic.isLocal(videoId)
        let found = await Lyrics.search(title: imported ? Lyrics.fileTitle(title) : title,
                                        artist: artist,
                                        videoId: imported ? "" : videoId,
                                        duration: duration)
        guard !found.isEmpty else { return [] }

        store[videoId] = found
        order.removeAll { $0 == videoId }
        order.append(videoId)
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            store[oldest] = nil
        }
        return found
    }

    func clear() {
        store = [:]
        order = []
    }
}
