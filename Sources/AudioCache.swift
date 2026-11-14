import Foundation
import Combine

final class AudioCache: ObservableObject {
    static let shared = AudioCache()

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "enableSongCache") as? Bool ?? true
    }

    var limitMB: Int {
        guard UserDefaults.standard.object(forKey: "songCacheLimitMB") != nil else { return 512 }
        return UserDefaults.standard.integer(forKey: "songCacheLimitMB")
    }

    var limitBytes: Int64? {
        limitMB < 0 ? nil : Int64(limitMB) * 1024 * 1024
    }

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var sizeBytes: Int64 = 0

    private let dir: URL
    private let metaURL: URL
    private var lastUsed: [String: Date] = [:]
    private var inFlight: Set<String> = []

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = caches.appendingPathComponent("AudioCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        metaURL = dir.appendingPathComponent("cache.json")
        load()
        refreshSize()
    }

    // MARK: Lookup

    private func fileURL(for id: String) -> URL { dir.appendingPathComponent("\(id).m4a") }
    private func artFileURL(for id: String) -> URL { dir.appendingPathComponent("\(id).jpg") }
    private func lrcURL(for id: String) -> URL { dir.appendingPathComponent("\(id).lrc") }
    private func txtURL(for id: String) -> URL { dir.appendingPathComponent("\(id).txt") }

    func cachedArtURL(for id: String) -> URL? {
        guard lastUsed[id] != nil else { return nil }
        return localArtURL(for: id)
    }

    func localArtURL(for id: String) -> URL? {
        let u = artFileURL(for: id)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    func cachedLyrics(for id: String) -> LyricsResult? {
        if let lrc = try? String(contentsOf: lrcURL(for: id), encoding: .utf8), !lrc.isEmpty {
            return LyricsResult(lines: Lyrics.parseLRC(lrc), plain: nil, synced: true, raw: lrc)
        }
        if let plain = try? String(contentsOf: txtURL(for: id), encoding: .utf8), !plain.isEmpty {
            return LyricsResult(lines: [], plain: plain, synced: false, raw: nil)
        }
        return nil
    }

    private func enrich(_ track: Track) {
        let id = track.videoId
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            if self.localArtURL(for: id) == nil,
               let remote = track.artURL(size: 1080),
               let data = await ArtFetch.data(from: remote) {
                try? data.write(to: self.artFileURL(for: id))
            }
            guard self.cachedLyrics(for: id) == nil else { return }
            let candidates = await LyricsCache.shared.warm(
                videoId: id, title: track.title, artist: track.artist,
                duration: track.duration)
            guard let lyrics = Lyrics.best(candidates) else { return }
            if let lrc = lyrics.raw {
                try? lrc.write(to: self.lrcURL(for: id), atomically: true, encoding: .utf8)
            } else if let plain = lyrics.plain {
                try? plain.write(to: self.txtURL(for: id), atomically: true, encoding: .utf8)
            }
        }
    }

    func cachedURL(for id: String) -> URL? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        lastUsed[id] = Date()
        save()
        return url
    }

    func isCached(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    // MARK: Filling

    func cache(_ track: Track) {
        let id = track.videoId
        guard isEnabled, limitMB != 0 else { return }
        guard !id.isEmpty, !isCached(id), !inFlight.contains(id) else { return }
        guard !YouTube.isLive(id) else { return }
        guard Downloads.shared.localAudioURL(for: id) == nil else { return }
        inFlight.insert(id)
        let dest = fileURL(for: id)

        Task.detached(priority: .background) { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)

            guard let fresh = await YouTube.streamURL(for: id) else {
                _ = await MainActor.run { [weak self] in self?.inFlight.remove(id) }
                return
            }

            var req = URLRequest(url: fresh.url)
            req.setValue(YouTube.visionUA, forHTTPHeaderField: "User-Agent")

            var didStore = false
            if let (tmp, response) = try? await URLSession.shared.download(for: req),
               (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 {
                try? FileManager.default.removeItem(at: dest)
                didStore = (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil
            }
            let stored = didStore

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inFlight.remove(id)
                guard stored else { return }
                self.lastUsed[id] = Date()
                self.tracks.removeAll { $0.videoId == id }
                self.tracks.insert(track, at: 0)
                self.enrich(track)
                self.save()
                self.evictIfNeeded()
                self.refreshSize()
            }
        }
    }

    // MARK: Housekeeping

    private func measure() -> Int64 {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]))?
            .reduce(Int64(0)) { total, url in
                total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            } ?? 0
    }

    func refreshSize() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let size = self.measure()
            await MainActor.run { self.sizeBytes = size }
        }
    }

    private func evictIfNeeded() {
        guard let cap = limitBytes, measure() > cap else { return }
        let order = tracks.sorted {
            (lastUsed[$0.videoId] ?? .distantPast) < (lastUsed[$1.videoId] ?? .distantPast)
        }
        for track in order {
            guard measure() > cap else { break }
            remove(track.videoId)
        }
    }

    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: artFileURL(for: id))
        try? FileManager.default.removeItem(at: lrcURL(for: id))
        try? FileManager.default.removeItem(at: txtURL(for: id))
        try? FileManager.default.removeItem(at: fileURL(for: id))
        tracks.removeAll { $0.videoId == id }
        lastUsed[id] = nil
        save()
    }

    func clear() {
        for track in tracks { try? FileManager.default.removeItem(at: fileURL(for: track.videoId)) }
        tracks = []
        lastUsed = [:]
        save()
        sizeBytes = 0
    }

    // MARK: Persistence

    private struct Meta: Codable {
        let tracks: [Track]
        let lastUsed: [String: Date]
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Meta(tracks: tracks, lastUsed: lastUsed)) else { return }
        try? data.write(to: metaURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return }
        lastUsed = meta.lastUsed
        tracks = meta.tracks.filter { isCached($0.videoId) }
    }
}
