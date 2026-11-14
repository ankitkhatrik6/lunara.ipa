import Foundation

struct PlayEvent: Codable, Hashable {
    let videoId: String
    let at: Date
}

enum StatPeriod: String, CaseIterable, Identifiable {
    case day, week1, month1, month3, month6, year1, all

    var id: String { rawValue }

    static var topFilters: [StatPeriod] { [.all, .day, .week1, .month1, .year1] }

    var title: String {
        switch self {
        case .day: String(localized: "Today")
        case .week1: String(localized: "1 week")
        case .month1: String(localized: "1 month")
        case .month3: String(localized: "3 months")
        case .month6: String(localized: "6 months")
        case .year1: String(localized: "1 year")
        case .all: String(localized: "All time")
        }
    }

    var since: Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .day: return cal.startOfDay(for: now)
        case .week1: return cal.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case .month1: return cal.date(byAdding: .month, value: -1, to: now) ?? now
        case .month3: return cal.date(byAdding: .month, value: -3, to: now) ?? now
        case .month6: return cal.date(byAdding: .month, value: -6, to: now) ?? now
        case .year1: return cal.date(byAdding: .year, value: -1, to: now) ?? now
        case .all: return .distantPast
        }
    }
}

enum DateAgo: Hashable {
    case today, yesterday, thisWeek, lastWeek
    case other(Date)

    var title: String {
        switch self {
        case .today: return String(localized: "Today")
        case .yesterday: return String(localized: "Yesterday")
        case .thisWeek: return String(localized: "This week")
        case .lastWeek: return String(localized: "Last week")
        case .other(let date):
            let f = DateFormatter()
            f.dateFormat = "yyyy/MM"
            return f.string(from: date)
        }
    }

    var order: Int {
        switch self {
        case .today: 0
        case .yesterday: 1
        case .thisWeek: 2
        case .lastWeek: 3
        case .other(let date): 4 + max(0, Calendar.current.dateComponents(
            [.day], from: date, to: Date()).day ?? 0)
        }
    }

    static func of(_ date: Date) -> DateAgo {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let today = cal.startOfDay(for: Date())
        let daysAgo = cal.dateComponents([.day], from: day, to: today).day ?? 0

        if daysAgo == 0 { return .today }
        if daysAgo == 1 { return .yesterday }

        var monday = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        monday.weekday = 2
        let thisMonday = cal.date(from: monday) ?? today
        let lastMonday = cal.date(byAdding: .weekOfYear, value: -1, to: thisMonday) ?? today

        if day >= thisMonday { return .thisWeek }
        if day >= lastMonday { return .lastWeek }

        let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: day)) ?? day
        return .other(firstOfMonth)
    }
}

enum PlayHistory {
    private static let eventsKey = "playEvents"
    private static let tracksKey = "playedTracks"
    private static let limit = 3000

    // MARK: Cache

    private static var cachedEvents: [PlayEvent]?
    private static var cachedTracks: [Track]?
    private static var cachedById: [String: Track]?
    private static var cachedCounts: [String: [String: Int]] = [:]

    private static func invalidate() {
        cachedEvents = nil
        cachedTracks = nil
        cachedById = nil
        cachedCounts = [:]
    }

    // MARK: Recording

    static func record(_ track: Track) {
        guard !UserDefaults.standard.bool(forKey: "pauseListenHistory") else { return }
        guard !track.videoId.isEmpty else { return }
        var events = self.events
        events.append(PlayEvent(videoId: track.videoId, at: Date()))
        if events.count > limit { events.removeFirst(events.count - limit) }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: eventsKey)
        }

        var known = tracks
        known.removeAll { $0.videoId == track.videoId }
        known.insert(track, at: 0)
        if known.count > 500 { known = Array(known.prefix(500)) }
        if let data = try? JSONEncoder().encode(known) {
            UserDefaults.standard.set(data, forKey: tracksKey)
        }
        invalidate()
    }

    // MARK: Reading

    static var events: [PlayEvent] {
        if let cachedEvents { return cachedEvents }
        guard let data = UserDefaults.standard.data(forKey: eventsKey),
              let list = try? JSONDecoder().decode([PlayEvent].self, from: data) else {
            cachedEvents = []
            return []
        }
        cachedEvents = list
        return list
    }

    static var tracks: [Track] {
        if let cachedTracks { return cachedTracks }
        guard let data = UserDefaults.standard.data(forKey: tracksKey),
              let list = try? JSONDecoder().decode([Track].self, from: data) else {
            cachedTracks = []
            return []
        }
        cachedTracks = list
        return list
    }

    private static var byId: [String: Track] {
        if let cachedById { return cachedById }
        let map = Dictionary(tracks.map { ($0.videoId, $0) }, uniquingKeysWith: { a, _ in a })
        cachedById = map
        return map
    }

    private static func counts(_ period: StatPeriod) -> [String: Int] {
        if let hit = cachedCounts[period.rawValue] { return hit }
        let since = period.since
        var out: [String: Int] = [:]
        for event in events where event.at >= since {
            out[event.videoId, default: 0] += 1
        }
        if out.isEmpty, period == .all {
            out = UserDefaults.standard.dictionary(forKey: "playCounts") as? [String: Int] ?? [:]
        }
        cachedCounts[period.rawValue] = out
        return out
    }

    static var recent: [Track] {
        let lookup = byId
        var seen = Set<String>()
        var out: [Track] = []
        for event in events.reversed() where !seen.contains(event.videoId) {
            seen.insert(event.videoId)
            if let track = lookup[event.videoId] { out.append(track) }
        }
        for track in tracks where !seen.contains(track.videoId) {
            seen.insert(track.videoId)
            out.append(track)
        }
        return out
    }

    static func mostPlayed(_ period: StatPeriod = .all, limit: Int = 50) -> [Track] {
        let lookup = byId
        return counts(period).sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { lookup[$0.key] }
    }

    static func playCount(_ videoId: String, in period: StatPeriod = .all) -> Int {
        counts(period)[videoId] ?? 0
    }

    static func topArtists(_ period: StatPeriod = .all, limit: Int = 20) -> [(name: String, plays: Int)] {
        let since = period.since
        let lookup = byId
        var counts: [String: Int] = [:]
        for event in events where event.at >= since {
            guard let artist = lookup[event.videoId]?.artist, !artist.isEmpty else { continue }
            for name in artist.split(separator: ",").map({
                $0.trimmingCharacters(in: .whitespaces)
            }) where !name.isEmpty {
                counts[name, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (name: $0.key, plays: $0.value) }
    }

    static var grouped: [(bucket: DateAgo, tracks: [Track])] {
        let lookup = byId
        var buckets: [DateAgo: [Track]] = [:]
        var seen: Set<String> = []

        for event in events.reversed() {
            let bucket = DateAgo.of(event.at)
            let key = "\(bucket.order)_\(event.videoId)"
            guard !seen.contains(key), let track = lookup[event.videoId] else { continue }
            seen.insert(key)
            buckets[bucket, default: []].append(track)
        }
        return buckets
            .map { (bucket: $0.key, tracks: $0.value) }
            .sorted { $0.bucket.order < $1.bucket.order }
    }

    static var topSize: Int {
        let saved = UserDefaults.standard.integer(forKey: "topSize")
        return saved > 0 ? saved : 50
    }

    static var top: [Track] { mostPlayed(.all, limit: topSize) }

    @MainActor
    static func pruneOld() {
        let days = PlaybackPrefs.shared.historyDays
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let current = events
        let kept = current.filter { $0.at >= cutoff }
        guard kept.count != current.count else { return }
        if let data = try? JSONEncoder().encode(kept) {
            UserDefaults.standard.set(data, forKey: eventsKey)
        }
        invalidate()
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: eventsKey)
        UserDefaults.standard.removeObject(forKey: tracksKey)
        UserDefaults.standard.removeObject(forKey: "playCounts")
        invalidate()
    }
}
