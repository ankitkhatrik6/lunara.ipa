import Foundation
import SwiftUI

final class LyricsSecondary: ObservableObject {
    static let shared = LyricsSecondary()

    @Published private(set) var lines: [String: [Int: String]] = [:]
    @Published private(set) var working = false

    private var inFlight: Set<String> = []

    private init() {}

    func text(for videoId: String, line: Int) -> String? {
        lines[videoId]?[line]
    }

    func clear() {
        lines.removeAll()
        inFlight.removeAll()
    }

    func prepare(videoId: String, lyrics: [LyricLine]) {
        guard !videoId.isEmpty, !lyrics.isEmpty else { return }
        let romanize = RomanizePrefs.shared
        let translate = AIPrefs.shared

        if romanize.enabled, romanize.applies(to: lyrics) {
            let key = "rom:\(videoId)"
            guard !inFlight.contains(key), lines[videoId] == nil else { return }
            inFlight.insert(key)
            var out: [Int: String] = [:]
            for (i, line) in lyrics.enumerated() {
                if let latin = Romanize.toLatin(line.text), latin != line.text {
                    out[i] = latin
                }
            }
            lines[videoId] = out
            inFlight.remove(key)
            return
        }

        guard translate.isConfigured else { return }
        let key = "ai:\(videoId)"
        guard !inFlight.contains(key), lines[videoId] == nil else { return }
        inFlight.insert(key)
        working = true

        Task {
            let translated = await AITranslator.translate(
                lyrics.map(\.text),
                into: translate.targetLanguage)
            var out: [Int: String] = [:]
            for (i, text) in translated.enumerated() where !text.isEmpty {
                if text != lyrics[safe: i]?.text { out[i] = text }
            }
            let result = out
            await MainActor.run {
                self.lines[videoId] = result
                self.inFlight.remove(key)
                self.working = false
            }
        }
    }
}

enum Romanize {
    static func toLatin(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let latin = text.applyingTransform(.toLatin, reverse: false)
        return latin?.applyingTransform(.stripDiacritics, reverse: false) ?? latin
    }

    static let scripts: [(code: String, name: String)] = [
        ("Devanagari", "Hindi and Nepali"),
        ("Japanese", "Japanese"),
        ("Korean", "Korean"),
        ("Chinese", "Chinese"),
        ("Cyrillic", "Russian and Cyrillic"),
        ("Urdu", "Urdu and Arabic"),
        ("Bengali", "Bengali"),
        ("Gurmukhi", "Punjabi"),
        ("Gujarati", "Gujarati"),
        ("Tamil", "Tamil"),
        ("Telugu", "Telugu"),
        ("Kannada", "Kannada"),
        ("Malayalam", "Malayalam"),
        ("Odia", "Odia"),
    ]
}

final class RomanizePrefs: ObservableObject {
    static let shared = RomanizePrefs()

    @Published var enabled: Bool { didSet { save(enabled, "lyricsRomanizeEnabled") } }
    @Published var asMain: Bool { didSet { save(asMain, "lyricsRomanizeAsMain") } }
    @Published var scripts: [String] { didSet { save(scripts, "lyricsRomanizeList") } }

    private init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: "lyricsRomanizeEnabled") as? Bool ?? false
        asMain = d.object(forKey: "lyricsRomanizeAsMain") as? Bool ?? false
        scripts = d.stringArray(forKey: "lyricsRomanizeList")
            ?? Romanize.scripts.map(\.code)
    }

    func isOn(_ script: String) -> Bool { scripts.contains(script) }

    func set(_ script: String, on: Bool) {
        if on {
            if !scripts.contains(script) { scripts.append(script) }
        } else {
            scripts.removeAll { $0 == script }
        }
    }

    func applies(to lyrics: [LyricLine]) -> Bool {
        let sample = lyrics.prefix(12).map(\.text).joined(separator: " ")
        guard let script = Lyrics.detectScript(sample) else { return false }
        return isOn(script)
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
