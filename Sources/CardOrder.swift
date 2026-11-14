import Foundation

enum CardOrder {
    static func place(_ id: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Double(hash % 1_000_003) / 1_000_003
    }

    static func order<T>(_ items: [T], id: (T) -> String, from cover: String?) -> [T] {
        let sorted = items.sorted { place(id($0)) < place(id($1)) }
        guard let cover, !sorted.isEmpty else { return sorted }
        let coverPlace = place(cover)
        let start = sorted.firstIndex { place(id($0)) >= coverPlace } ?? 0
        return Array(sorted[start...]) + Array(sorted[..<start])
    }

    static func next<T>(after order: [T], id: (T) -> String) -> String? {
        order.dropFirst().first.map(id)
    }
}
