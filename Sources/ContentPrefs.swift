import Combine
import SwiftUI

final class ContentPrefs: ObservableObject {
    static let shared = ContentPrefs()

    @Published var language: String { didSet { save(language, "contentLanguage") } }
    @Published var country: String { didSet { save(country, "contentCountry") } }

    @Published var hideExplicit: Bool { didSet { save(hideExplicit, "hideExplicit") } }
    @Published var hideShorts: Bool { didSet { save(hideShorts, "hideYoutubeShorts") } }
    @Published var hideVideoSongs: Bool { didSet { save(hideVideoSongs, "hideVideoSongs") } }

    @Published var showArtistDescription: Bool { didSet { save(showArtistDescription, "showArtistDescription") } }
    @Published var showSubscriberCount: Bool { didSet { save(showSubscriberCount, "showArtistSubscriberCount") } }

    @Published var randomizeHomeOrder: Bool { didSet { save(randomizeHomeOrder, "randomizeHomeOrder") } }
    @Published var showStatsPlaylists: Bool { didSet { save(showStatsPlaylists, "showMostStatsPlaylists") } }

    static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("ne", "Nepali"), ("hi", "Hindi"), ("es", "Spanish"),
        ("fr", "French"), ("de", "German"), ("pt", "Portuguese"), ("ru", "Russian"),
        ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("ar", "Arabic"),
        ("id", "Indonesian"), ("tr", "Turkish"), ("it", "Italian"),
    ]
    static let countries: [(code: String, name: String)] = [
        ("US", "United States"), ("NP", "Nepal"), ("IN", "India"), ("GB", "United Kingdom"),
        ("CA", "Canada"), ("AU", "Australia"), ("DE", "Germany"), ("FR", "France"),
        ("BR", "Brazil"), ("JP", "Japan"), ("KR", "South Korea"), ("ID", "Indonesia"),
        ("MX", "Mexico"), ("RU", "Russia"), ("ZA", "South Africa"),
    ]

    static func name(ofLanguage code: String) -> String {
        languages.first { $0.code == code }?.name ?? code
    }
    static func name(ofCountry code: String) -> String {
        countries.first { $0.code == code }?.name ?? code
    }

    private init() {
        let d = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }

        let deviceLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let deviceRegion = Locale.current.region?.identifier ?? "US"
        language = d.string(forKey: "contentLanguage")
            ?? (Self.languages.contains { $0.code == deviceLanguage } ? deviceLanguage : "en")
        country = d.string(forKey: "contentCountry")
            ?? (Self.countries.contains { $0.code == deviceRegion } ? deviceRegion : "US")

        hideExplicit = flag("hideExplicit", false)
        hideVideoSongs = flag("hideVideoSongs", false)
        hideShorts = flag("hideYoutubeShorts", false)
        showArtistDescription = flag("showArtistDescription", true)
        showSubscriberCount = flag("showArtistSubscriberCount", true)
        randomizeHomeOrder = flag("randomizeHomeOrder", true)
        showStatsPlaylists = flag("showMostStatsPlaylists", true)
    }

    static func allows(_ track: Track) -> Bool {
        let d = UserDefaults.standard
        if d.bool(forKey: "hideExplicit"), track.isExplicit { return false }
        if d.bool(forKey: "hideVideoSongs"), track.isVideo { return false }
        return true
    }

    static func filtered(_ tracks: [Track]) -> [Track] { tracks.filter(allows) }

    static var locale: (hl: String, gl: String) {
        let d = UserDefaults.standard
        return (d.string(forKey: "contentLanguage") ?? "en",
                d.string(forKey: "contentCountry") ?? "US")
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

extension Array where Element == HomeSection {
    func withoutShorts() -> [HomeSection] {
        guard ContentPrefs.shared.hideShorts else { return self }
        return compactMap { section in
            let kept = section.items.filter { !($0.browseId?.hasPrefix("SS") ?? false) }
            if kept.isEmpty { return nil }
            if kept.count == section.items.count { return section }
            return HomeSection(title: section.title, items: kept, isSongs: section.isSongs,
                               browseId: section.browseId, params: section.params)
        }
    }
}
