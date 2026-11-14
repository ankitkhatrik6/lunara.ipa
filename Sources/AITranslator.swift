import Foundation

enum AITranslator {
    static func translate(_ lines: [String], into language: String) async -> [String] {
        guard !lines.isEmpty else { return [] }
        let prefs = await MainActor.run {
            let p = AIPrefs.shared
            return (provider: p.provider, key: p.apiKey, base: p.baseURL,
                    model: p.model, prompt: p.systemPrompt, mode: p.mode,
                    formality: p.formality)
        }
        guard !prefs.key.isEmpty else { return [] }

        let body = lines.enumerated().map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        let raw: String?
        if prefs.provider.isDeepL {
            raw = await deepL(lines, into: language, key: prefs.key,
                              base: prefs.base, formality: prefs.formality)
        } else {
            let instruction = """
                \(prefs.prompt)

                \(prefs.mode == .transcribed
                    ? "Instead of translating the meaning, write how each line SOUNDS using the script of \(language)."
                    : "Translate into \(language).")

                Return exactly \(lines.count) lines, numbered 1 to \(lines.count), \
                one per input line, nothing else.
                """
            raw = await chat(system: instruction, user: body, prefs: prefs)
        }
        guard let raw, !raw.isEmpty else { return [] }
        return align(raw, count: lines.count)
    }

    private static func align(_ text: String, count: Int) -> [String] {
        var out = [String](repeating: "", count: count)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let dot = trimmed.firstIndex(of: "."),
                  let index = Int(trimmed[trimmed.startIndex..<dot]),
                  index >= 1, index <= count else { continue }
            out[index - 1] = trimmed[trimmed.index(after: dot)...]
                .trimmingCharacters(in: .whitespaces)
        }
        if out.allSatisfy(\.isEmpty) {
            let plain = text.split(separator: "\n").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard plain.count == count else { return [] }
            return plain
        }
        return out
    }

    // MARK: Chat providers

    private typealias Prefs = (provider: AIProvider, key: String, base: String,
                               model: String, prompt: String, mode: TranslationMode,
                               formality: DeepLFormality)

    private static func chat(system: String, user: String, prefs: Prefs) async -> String? {
        switch prefs.provider {
        case .claude: return await claude(system: system, user: user, prefs: prefs)
        default: return await openAICompatible(system: system, user: user, prefs: prefs)
        }
    }

    private static func openAICompatible(system: String, user: String,
                                         prefs: Prefs) async -> String? {
        guard var req = request("\(prefs.base)/chat/completions") else { return nil }
        req.setValue("Bearer \(prefs.key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": prefs.model,
            "messages": [["role": "system", "content": system],
                         ["role": "user", "content": user]],
            "temperature": 0.2,
        ]
        guard let json = await send(req, body) else { return nil }
        let choices = json["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return message?["content"] as? String
    }

    private static func claude(system: String, user: String, prefs: Prefs) async -> String? {
        guard var req = request("\(prefs.base)/messages") else { return nil }
        req.setValue(prefs.key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": prefs.model,
            "max_tokens": 4096,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        guard let json = await send(req, body) else { return nil }
        let content = json["content"] as? [[String: Any]]
        return content?.compactMap { $0["text"] as? String }.joined()
    }

    // MARK: DeepL — a translation API, not a chat one

    private static func deepL(_ lines: [String], into language: String, key: String,
                              base: String, formality: DeepLFormality) async -> String? {
        guard var req = request("\(base)/translate") else { return nil }
        req.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "text": lines,
            "target_lang": language.uppercased(),
        ]
        if formality != .default { body["formality"] = formality == .more ? "more" : "less" }
        guard let json = await send(req, body),
              let translations = json["translations"] as? [[String: Any]] else { return nil }
        return translations.enumerated()
            .map { "\($0.offset + 1). \(($0.element["text"] as? String) ?? "")" }
            .joined(separator: "\n")
    }

    // MARK: Transport

    private static func request(_ url: String) -> URLRequest? {
        guard let url = URL(string: url) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 45
        return req
    }

    private static func send(_ req: URLRequest, _ body: [String: Any]) async -> [String: Any]? {
        var req = req
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = payload
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }
}
