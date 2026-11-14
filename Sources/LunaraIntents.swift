import AppIntents
import Foundation

extension LunaraLink {
    static func request(for url: URL) -> LunaraRequest? {
        guard url.scheme == scheme else { return nil }
        switch url.host {
        case "resume": return .resume
        case "favourites": return .favourites
        case "downloads": return .downloads
        case "search": return .search
        default: return nil
        }
    }
}

enum LunaraRequest: Equatable {
    case resume, favourites, downloads, search
    case play(String)

    private static let key = "pendingIntentRequest"
    private static let queryKey = "pendingIntentQuery"

    private var name: String {
        switch self {
        case .resume: return "resume"
        case .favourites: return "favourites"
        case .downloads: return "downloads"
        case .search: return "search"
        case .play: return "play"
        }
    }

    func store() {
        let d = UserDefaults.standard
        d.set(name, forKey: Self.key)
        if case .play(let videoId) = self {
            d.set(videoId, forKey: Self.queryKey)
        } else {
            d.removeObject(forKey: Self.queryKey)
        }
    }

    static func take() -> LunaraRequest? {
        let d = UserDefaults.standard
        guard let raw = d.string(forKey: key) else { return nil }
        let query = d.string(forKey: queryKey)
        d.removeObject(forKey: key)
        d.removeObject(forKey: queryKey)
        switch raw {
        case "resume": return .resume
        case "favourites": return .favourites
        case "downloads": return .downloads
        case "search": return .search
        case "play":
            guard let query, !query.isEmpty else { return nil }
            return .play(query)
        default: return nil
        }
    }
}

struct SongEntity: AppEntity, Identifiable {
    let id: String
    let title: String
    let artist: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Song")
    static var defaultQuery = SongQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(artist)")
    }
}

struct SongQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [SongEntity] {
        let results = await YouTube.search(string)
        return results.prefix(8).map {
            SongEntity(id: $0.videoId, title: $0.title, artist: $0.artist)
        }
    }

    func entities(for identifiers: [String]) async throws -> [SongEntity] {
        let known = Downloads.shared.tracks + PlayHistory.tracks
        return identifiers.compactMap { id in
            known.first { $0.videoId == id }
                .map { SongEntity(id: $0.videoId, title: $0.title, artist: $0.artist) }
        }
    }

    func suggestedEntities() async throws -> [SongEntity] {
        PlayHistory.recent.prefix(8).map {
            SongEntity(id: $0.videoId, title: $0.title, artist: $0.artist)
        }
    }
}

struct PlaySongIntent: AppIntent {
    static var title: LocalizedStringResource = "Play a song"
    static var description = IntentDescription("Play a song in Lunara.")
    static var openAppWhenRun = true

    @Parameter(title: "Song", requestValueDialog: "What would you like to hear?")
    var song: SongEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        LunaraRequest.play(song.id).store()
        return .result(dialog: "Playing \(song.title).")
    }
}

struct ResumeLunaraIntent: AppIntent {
    static var title: LocalizedStringResource = "Play"
    static var description = IntentDescription("Carry on where Lunara left off.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        LunaraRequest.resume.store()
        return .result()
    }
}

struct PlayFavouritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Play favourites"
    static var description = IntentDescription("Shuffle the songs you've hearted.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        LunaraRequest.favourites.store()
        return .result(dialog: "Shuffling your favourites.")
    }
}

struct PlayDownloadsIntent: AppIntent {
    static var title: LocalizedStringResource = "Play downloads"
    static var description = IntentDescription("Shuffle everything saved on this device — works with no signal.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        LunaraRequest.downloads.store()
        return .result(dialog: "Shuffling your downloads.")
    }
}

struct LunaraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumeLunaraIntent(),
            phrases: [
                "Resume \(.applicationName)",
                "Continue \(.applicationName)",
                "Play \(.applicationName)",
            ],
            shortTitle: "Play",
            systemImageName: "play.fill")

        AppShortcut(
            intent: PlaySongIntent(),
            phrases: [
                "Play a song on \(.applicationName)",
                "Find a song on \(.applicationName)",
                "Search \(.applicationName)",
            ],
            shortTitle: "Play a song",
            systemImageName: "music.note")

        AppShortcut(
            intent: PlayFavouritesIntent(),
            phrases: [
                "Shuffle favourites on \(.applicationName)",
                "Shuffle liked songs on \(.applicationName)",
            ],
            shortTitle: "Favourites",
            systemImageName: "heart.fill")

        AppShortcut(
            intent: PlayDownloadsIntent(),
            phrases: [
                "Shuffle downloads on \(.applicationName)",
                "Shuffle offline music on \(.applicationName)",
            ],
            shortTitle: "Downloads",
            systemImageName: "arrow.down.circle.fill")
    }
}
