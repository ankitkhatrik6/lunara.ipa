import Foundation

enum LibraryCardText {
    static func subtitle(_ raw: String) -> String {
        let parts = raw
            .components(separatedBy: "•")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let count = parts.first(where: { looksLikeCount($0) }) { return count }
        let kinds = ["playlist", "album", "single", "ep", "artist", "podcast"]
        if let rest = parts.first(where: { !kinds.contains($0.lowercased()) }) { return rest }
        return parts.first ?? raw
    }

    private static func looksLikeCount(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count == 2, let first = words.first, let unit = words.last else { return false }
        let number = first.replacingOccurrences(of: ",", with: "")
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return false }
        return ["song", "songs", "track", "tracks", "episode", "episodes"].contains(unit.lowercased())
    }
}
