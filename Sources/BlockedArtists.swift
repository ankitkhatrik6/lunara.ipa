import Foundation

@MainActor
final class BlockedArtists: ObservableObject {
    static let shared = BlockedArtists()

    @Published private(set) var entries: [String] = []

    private let key = "blockedArtists"

    private init() {
        entries = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func entry(id: String?, name: String) -> String { "\(id ?? "")|\(name)" }
    static func id(of entry: String) -> String? {
        let head = entry.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return head.isEmpty ? nil : head
    }

    static func name(of entry: String) -> String {
        let parts = entry.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count > 1 ? String(parts[1]) : entry
    }

    var isEmpty: Bool { entries.isEmpty }

    func isBlocked(id: String?, name: String) -> Bool {
        guard !entries.isEmpty else { return false }
        return entries.contains { entry in
            if let blockedId = Self.id(of: entry), let id, blockedId == id { return true }
            return Self.name(of: entry).caseInsensitiveCompare(name) == .orderedSame
        }
    }

    func blocks(_ track: Track) -> Bool {
        guard !entries.isEmpty, !track.artist.isEmpty else { return false }
        let names = track.artist
            .components(separatedBy: CharacterSet(charactersIn: ",&"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return names.contains { isBlocked(id: track.artistId, name: $0) }
    }

    func block(id: String?, name: String) {
        let entry = Self.entry(id: id, name: name)
        guard !entries.contains(entry) else { return }
        entries.append(entry)
        save()
    }

    func unblock(id: String?, name: String) {
        entries.removeAll { entry in
            if let blockedId = Self.id(of: entry), let id, blockedId == id { return true }
            return Self.name(of: entry).caseInsensitiveCompare(name) == .orderedSame
        }
        save()
    }

    func remove(_ entry: String) {
        entries.removeAll { $0 == entry }
        save()
    }

    private func save() {
        UserDefaults.standard.set(entries, forKey: key)
    }
}

extension Array where Element == Track {
    @MainActor
    func withoutBlockedArtists() -> [Track] {
        let blocked = BlockedArtists.shared
        guard !blocked.isEmpty else { return self }
        return filter { !blocked.blocks($0) }
    }
}
