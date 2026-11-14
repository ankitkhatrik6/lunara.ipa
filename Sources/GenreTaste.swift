import Foundation
import SwiftUI

@MainActor
final class GenreTaste: ObservableObject {
    static let shared = GenreTaste()

    @Published private(set) var scores: [String: Double] = [:]

    private var artistsByGenre: [String: [String]]
    private var scannedAt: Date?
    private var opened: [String: Double]
    private var scanning = false

    private let keepFor: TimeInterval = 24 * 60 * 60
    private let openWeight: Double = 4
    private let artistsConsidered = 40

    private init() {
        let d = UserDefaults.standard
        artistsByGenre = (try? JSONDecoder().decode([String: [String]].self,
                                                    from: d.data(forKey: "genreTasteArtists") ?? Data())) ?? [:]
        scannedAt = d.object(forKey: "genreTasteScannedAt") as? Date
        opened = (try? JSONDecoder().decode([String: Double].self,
                                            from: d.data(forKey: "genreTasteOpened") ?? Data())) ?? [:]
        rescore()
    }

    func order(_ tiles: [MoodItem]) -> [MoodItem] {
        let moods = tiles.filter { !$0.isGenre }
        let genres = tiles.filter(\.isGenre)
        let ranked = genres.enumerated().sorted { a, b in
            let sa = scores[a.element.title] ?? 0, sb = scores[b.element.title] ?? 0
            if sa != sb { return sa > sb }
            return a.offset < b.offset
        }.map(\.element)
        return moods + ranked
    }

    func count(of tiles: [MoodItem]) -> Int {
        tiles.filter { $0.isGenre && (scores[$0.title] ?? 0) > 0 }.count
    }

    func noteOpened(_ tile: MoodItem) {
        guard tile.isGenre else { return }
        opened[tile.title, default: 0] += 1
        if let data = try? JSONEncoder().encode(opened) {
            UserDefaults.standard.set(data, forKey: "genreTasteOpened")
        }
        rescore()
    }

    func refresh(_ tiles: [MoodItem]) async {
        let genres = tiles.filter(\.isGenre)
        guard !genres.isEmpty, !scanning else { return }
        if let scannedAt, Date().timeIntervalSince(scannedAt) < keepFor,
           genres.allSatisfy({ artistsByGenre[$0.title] != nil }) {
            return
        }
        scanning = true
        defer { scanning = false }

        var found: [String: [String]] = [:]
        for group in stride(from: 0, to: genres.count, by: 3) {
            let batch = Array(genres[group ..< min(group + 3, genres.count)])
            await withTaskGroup(of: (String, [String]).self) { tasks in
                for tile in batch {
                    tasks.addTask {
                        let page = await YouTube.shelfPage(browseId: tile.browseId ?? "", params: tile.params)
                        return (tile.title, Self.artistNames(in: page.items))
                    }
                }
                for await (title, names) in tasks { found[title] = names }
            }
        }
        guard !found.isEmpty else { return }
        for (title, names) in found { artistsByGenre[title] = names }
        scannedAt = Date()
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(artistsByGenre) { d.set(data, forKey: "genreTasteArtists") }
        d.set(scannedAt, forKey: "genreTasteScannedAt")
        rescore()
    }

    private func rescore() {
        let top = PlayHistory.topArtists(.all, limit: artistsConsidered)
        var out: [String: Double] = [:]
        for (genre, names) in artistsByGenre {
            let on = Set(names)
            var score = 0.0
            for artist in top where on.contains(artist.name.lowercased()) {
                score += Double(artist.plays)
            }
            if score > 0 { out[genre] = score }
        }
        for (genre, times) in opened {
            out[genre, default: 0] += times * openWeight
        }
        scores = out
    }

    nonisolated private static func artistNames(in items: [HomeItem]) -> [String] {
        var names: Set<String> = []
        for item in items {
            for part in item.subtitle.split(whereSeparator: { "•,&".contains($0) }) {
                let name = part.trimmingCharacters(in: .whitespaces).lowercased()
                if name.count > 1 { names.insert(name) }
            }
        }
        return Array(names)
    }
}
