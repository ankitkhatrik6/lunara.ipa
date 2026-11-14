import Foundation

enum VideoArtLog {
    private static var lines: [String] = []
    private static let keep = 300
    private static let lock = NSLock()
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func note(_ message: String) {
        let line = "\(clock.string(from: Date())) \(message)"
        lock.lock()
        lines.append(line)
        if lines.count > keep { lines.removeFirst(lines.count - keep) }
        lock.unlock()
        #if DEBUG
        print("[VideoArt] \(message)")
        #endif
    }

    static func kind(of url: URL) -> String {
        url.absoluteString.contains("/hls_") || url.absoluteString.contains("manifest") ? "hls" : "file"
    }

    static func probe(_ url: URL) {
        var req = URLRequest(url: url)
        req.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        req.setValue(YouTube.visionUA, forHTTPHeaderField: "User-Agent")
        req.allowsCellularAccess = false
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error {
                note("probe: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                note("probe: HTTP \(http.statusCode) from the same address, wifi only")
            }
        }.resume()
    }

    static var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.isEmpty ? "Nothing recorded yet." : lines.joined(separator: "\n")
    }
}
