import Foundation
import Combine

enum DownloadState: Equatable { case none, downloading, done }

final class Downloads: ObservableObject {
    static let shared = Downloads()

    @Published private(set) var states: [String: DownloadState] = [:]
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var sizeBytes: Int64 = 0

    private let dir: URL

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()

    func refreshSize() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let size = self.measure()
            await MainActor.run { self.sizeBytes = size }
        }
    }

    private func measure() -> Int64 {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]))?
            .reduce(Int64(0)) { total, url in
                total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            } ?? 0
    }

    func clearAll() {
        for track in tracks { remove(track.videoId) }
        tracks = []
        sizeBytes = 0
        saveMeta()
    }
    private let metaURL: URL
    private var durations: [String: Double] = [:]

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        metaURL = dir.appendingPathComponent("meta.json")
        loadMeta()
    }

    // MARK: Paths / queries

    private func audioURL(for id: String) -> URL { dir.appendingPathComponent("\(id).m4a") }
    private func artURL(for id: String) -> URL { dir.appendingPathComponent("\(id).jpg") }
    private func lyricsURL(for id: String) -> URL { dir.appendingPathComponent("\(id).lrc") }
    private func plainLyricsURL(for id: String) -> URL { dir.appendingPathComponent("\(id).txt") }

    func cachedLyrics(for id: String) -> LyricsResult? {
        if let lrc = try? String(contentsOf: lyricsURL(for: id), encoding: .utf8), !lrc.isEmpty {
            return LyricsResult(lines: Lyrics.parseLRC(lrc), plain: nil, synced: true, raw: lrc)
        }
        if let plain = try? String(contentsOf: plainLyricsURL(for: id), encoding: .utf8), !plain.isEmpty {
            return LyricsResult(lines: [], plain: plain, synced: false, raw: nil)
        }
        return nil
    }

    func localAudioURL(for id: String) -> URL? {
        let u = audioURL(for: id)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    func duration(for id: String) -> Double? { durations[id] }
    func state(_ id: String) -> DownloadState { states[id] ?? .none }
    func isDownloaded(_ id: String) -> Bool { states[id] == .done }

    // MARK: Actions

    func toggle(_ track: Track) {
        if isDownloaded(track.videoId) { remove(track.videoId) } else { download(track) }
    }

    private var pending: [Track] = []
    private var activeCount = 0
    private let maxConcurrent = 3
    private var running: [String: Task<Void, Never>] = [:]

    func download(_ track: Track) {
        let id = track.videoId
        guard !id.isEmpty, !LocalMusic.isLocal(id), !YouTube.isLive(id),
              state(id) == .none else { return }
        states[id] = .downloading
        progress[id] = 0
        pending.append(track)
        pump()
    }

    func downloadAll(_ tracks: [Track]) {
        for t in tracks { download(t) }
    }

    func cancel(_ id: String) {
        guard state(id) == .downloading else { return }
        pending.removeAll { $0.videoId == id }
        running[id]?.cancel()
        running[id] = nil
        states[id] = nil
        progress[id] = nil
    }

    func cancelAll(_ tracks: [Track]) {
        for t in tracks where state(t.videoId) == .downloading { cancel(t.videoId) }
    }

    private func pump() {
        while activeCount < maxConcurrent, !pending.isEmpty {
            let next = pending.removeFirst()
            let id = next.videoId
            activeCount += 1
            let job = Task { await perform(next) }
            running[id] = job
            Task {
                await job.value
                await MainActor.run {
                    if self.running[id] == job { self.running[id] = nil }
                    self.activeCount -= 1
                    self.pump()
                }
            }
        }
    }

    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: audioURL(for: id))
        try? FileManager.default.removeItem(at: artURL(for: id))
        try? FileManager.default.removeItem(at: lyricsURL(for: id))
        try? FileManager.default.removeItem(at: plainLyricsURL(for: id))
        tracks.removeAll { $0.videoId == id }
        durations[id] = nil
        states[id] = nil
        progress[id] = nil
        saveMeta()
    }

    private func perform(_ track: Track) async {
        let id = track.videoId
        var stream = await YouTube.streamURL(for: id)
        if stream == nil, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 800_000_000)
            stream = await YouTube.streamURL(for: id)
        }
        guard !Task.isCancelled else { return }
        guard let stream else {
            await MainActor.run { self.states[id] = DownloadState.none }
            return
        }
        do {
            let data = try await fetchAudio(stream.url, id: id)
            try Task.checkCancellation()
            try? FileManager.default.removeItem(at: audioURL(for: id))
            try data.write(to: audioURL(for: id))

            let stored = Track(videoId: id, title: track.title, artist: track.artist,
                               thumbnail: track.thumbnail, duration: stream.duration)
            let kept = await MainActor.run { () -> Bool in
                guard !Task.isCancelled else { return false }
                self.durations[id] = stream.duration
                self.tracks.removeAll { $0.videoId == id }
                self.tracks.insert(stored, at: 0)
                self.states[id] = .done
                self.progress[id] = nil
                self.saveMeta()
                self.refreshSize()
                return true
            }
            guard kept else {
                try? FileManager.default.removeItem(at: audioURL(for: id))
                return
            }
            Task.detached(priority: .utility) { [weak self] in
                await self?.enrich(track, id: id, duration: stream.duration)
            }
        } catch {
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.states[id] = DownloadState.none
                self.progress[id] = nil
            }
        }
    }

    // MARK: Ranged fetch

    private func fetchAudio(_ url: URL, id: String) async throws -> Data {
        let chunkSize = 512 * 1024

        let (head, total) = try await Downloads.fetchRange(url, 0, chunkSize - 1)
        guard total > head.count else { return head }

        var received = head.count
        await setProgress(id, Double(received) / Double(total))

        var parts: [Int: Data] = [0: head]
        let chunks = (total + chunkSize - 1) / chunkSize
        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for index in 1..<chunks {
                let from = index * chunkSize
                let to = min(from + chunkSize, total) - 1
                group.addTask {
                    let part = try await Downloads.fetchRange(url, from, to).0
                    return (index, part)
                }
            }
            for try await (index, part) in group {
                parts[index] = part
                received += part.count
                await setProgress(id, Double(received) / Double(total))
            }
        }

        var out = Data(capacity: total)
        for index in 0..<chunks { out.append(parts[index] ?? Data()) }
        return out
    }

    private static func fetchRange(_ url: URL, _ from: Int, _ to: Int) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.setValue(YouTube.visionUA, forHTTPHeaderField: "User-Agent")
        req.setValue("bytes=\(from)-\(to)", forHTTPHeaderField: "Range")
        req.allowsCellularAccess = !PlaybackPrefs.shared.downloadOnWifiOnly
        let (data, response) = try await session.data(for: req)
        var total = data.count
        if let http = response as? HTTPURLResponse,
           let header = http.value(forHTTPHeaderField: "Content-Range"),
           let tail = header.split(separator: "/").last,
           let parsed = Int(tail) {
            total = parsed
        }
        return (data, total)
    }

    private func setProgress(_ id: String, _ value: Double) async {
        await MainActor.run { self.progress[id] = min(max(value, 0), 1) }
    }

    private func enrich(_ track: Track, id: String, duration: Double) async {
        if let remote = track.artURL(size: 1080),
           let adata = await ArtFetch.data(from: remote) {
            try? adata.write(to: artURL(for: id))
            let artPath = self.localArt(for: id) ?? track.thumbnail
            await MainActor.run {
                self.remoteArt[id] = track.thumbnail
                if let i = self.tracks.firstIndex(where: { $0.videoId == id }) {
                    self.tracks[i] = Track(videoId: id, title: track.title, artist: track.artist,
                                           thumbnail: artPath, duration: duration)
                    self.saveMeta()
                }
            }
        }

        let candidates = await LyricsCache.shared.warm(videoId: id, title: track.title,
                                                       artist: track.artist, duration: duration)
        if let lyrics = Lyrics.best(candidates) {
            if let lrc = lyrics.raw {
                try? lrc.write(to: lyricsURL(for: id), atomically: true, encoding: .utf8)
            } else if let plain = lyrics.plain {
                try? plain.write(to: plainLyricsURL(for: id), atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: Persistence

    private var remoteArt: [String: String] = [:]

    private struct StoredTrack: Codable {
        let videoId, title, artist, thumbnail: String
        let duration: Double
    }
    private struct Meta: Codable {
        let tracks: [StoredTrack]
        let durations: [String: Double]
    }

    static func fallbackArt(_ videoId: String) -> String {
        "https://i.ytimg.com/vi/\(videoId)/maxresdefault.jpg"
    }

    func localArtURL(for id: String) -> URL? {
        let u = artURL(for: id)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    private func localArt(for id: String) -> String? {
        let u = artURL(for: id)
        return FileManager.default.fileExists(atPath: u.path) ? u.absoluteString : nil
    }

    private func saveMeta() {
        let stored = tracks.map {
            StoredTrack(videoId: $0.videoId, title: $0.title, artist: $0.artist,
                        thumbnail: $0.thumbnail.hasPrefix("file:") ? (remoteArt[$0.videoId] ?? "")
                                                                   : $0.thumbnail,
                        duration: $0.duration)
        }
        if let data = try? JSONEncoder().encode(Meta(tracks: stored, durations: durations)) {
            try? data.write(to: metaURL)
        }
    }

    private func loadMeta() {
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return }
        durations = meta.durations
        tracks = meta.tracks.map {
            remoteArt[$0.videoId] = $0.thumbnail
            let stored = $0.thumbnail
            let usable = !stored.isEmpty && !stored.hasPrefix("file:")
            return Track(videoId: $0.videoId, title: $0.title, artist: $0.artist,
                         thumbnail: localArt(for: $0.videoId)
                                    ?? (usable ? stored : Downloads.fallbackArt($0.videoId)),
                         duration: $0.duration)
        }
        for t in tracks { states[t.videoId] = .done }
    }
}
