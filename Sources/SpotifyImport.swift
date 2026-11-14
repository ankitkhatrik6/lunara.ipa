import Foundation

private let toleranceSeconds = 8.0

private let atOnce = 4

@MainActor
enum SpotifyImport {
    struct Outcome {
        let name: String
        let playlistId: String?
        let songs: [Track]
        let total: Int
        let missing: [String]
        let mayHaveMore: Bool

        var matched: Int { songs.count }
    }

    enum Failure: LocalizedError {
        case playlistEmpty

        var errorDescription: String? {
            switch self {
            case .playlistEmpty: String(localized: "Could not find songs in this playlist.")
            }
        }
    }

    static func run(
        link: String,
        onProgress: (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> Outcome {
        let playlist = try await SpotifyPlaylist.read(link)
        let found = try await search(playlist.tracks, onProgress: onProgress)
        let songs = found.compactMap { $0 }

        let created = LocalPlaylistStore.shared.create(title: playlist.name, tracks: songs)

        let missing = zip(playlist.tracks, found).compactMap { track, match in
            match == nil ? track.title : nil
        }
        return Outcome(
            name: playlist.name,
            playlistId: created.id,
            songs: songs,
            total: playlist.tracks.count,
            missing: missing,
            mayHaveMore: playlist.mayHaveMore)
    }

    private static func search(
        _ tracks: [SpotifyPlaylist.Track],
        onProgress: (_ done: Int, _ total: Int) -> Void
    ) async throws -> [Track?] {
        var found = [Track?](repeating: nil, count: tracks.count)
        var done = 0
        onProgress(0, tracks.count)

        await withTaskGroup(of: (Int, Track?).self) { group in
            var next = 0
            while next < min(atOnce, tracks.count) {
                let index = next, track = tracks[next]
                group.addTask {
                    let song = await Self.match(track)
                    return (index, song)
                }
                next += 1
            }
            while let (index, match) = await group.next() {
                found[index] = match
                done += 1
                onProgress(done, tracks.count)
                if next < tracks.count {
                    let index = next, track = tracks[next]
                    group.addTask {
                        let song = await Self.match(track)
                        return (index, song)
                    }
                    next += 1
                }
            }
        }
        try Task.checkCancellation()
        return found
    }

    nonisolated private static func match(_ track: SpotifyPlaylist.Track) async -> Track? {
        let query = [track.title, track.artists]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
        let results = await YouTube.search(query, scope: .songs)
        return pick(from: results, for: track)
    }

    nonisolated static func pick(from results: [Track], for track: SpotifyPlaylist.Track) -> Track? {
        guard !results.isEmpty else { return nil }
        guard track.durationSeconds > 0 else { return results.first }
        let wanted = Double(track.durationSeconds)
        return results
            .filter { $0.duration > 0 }
            .map { ($0, abs($0.duration - wanted)) }
            .filter { $0.1 <= toleranceSeconds }
            .min { $0.1 < $1.1 }?
            .0
    }
}
