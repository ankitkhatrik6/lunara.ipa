import SwiftUI
import WidgetKit

struct LunaraEntry: TimelineEntry { let date: Date }

struct LunaraProvider: TimelineProvider {
    func placeholder(in context: Context) -> LunaraEntry { LunaraEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (LunaraEntry) -> Void) {
        completion(LunaraEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LunaraEntry>) -> Void) {
        completion(Timeline(entries: [LunaraEntry(date: Date())], policy: .never))
    }
}

private struct Shortcut: Identifiable {
    let id: String
    let symbol: String
    let title: LocalizedStringKey
    let url: URL
}

private let shortcuts: [Shortcut] = [
    Shortcut(id: "play", symbol: "play.fill", title: "Play", url: LunaraLink.resume),
    Shortcut(id: "liked", symbol: "heart.fill", title: "Liked", url: LunaraLink.favourites),
    Shortcut(id: "offline", symbol: "arrow.down.circle.fill", title: "Offline",
             url: LunaraLink.downloads),
    Shortcut(id: "search", symbol: "magnifyingglass", title: "Search", url: LunaraLink.search),
]

struct LunaraWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    var entry: LunaraEntry

    private var dark: Bool { scheme == .dark }

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .systemLarge: large
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(spacing: 8) {
            row(0..<2, icon: 19, label: 11)
            row(2..<4, icon: 19, label: 11)
        }
        .padding(12)
        .containerBackground(for: .widget) { Sleeve.paper(dark) }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            SleeveHeader(dark: dark, size: 20)
            row(0..<4, icon: 18, label: 10.5)
        }
        .padding(14)
        .containerBackground(for: .widget) { Sleeve.paper(dark) }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 14) {
            SleeveHeader(dark: dark, size: 26)
            row(0..<2, icon: 30, label: 14)
            row(2..<4, icon: 30, label: 14)
        }
        .padding(18)
        .containerBackground(for: .widget) { Sleeve.paper(dark) }
    }

    private func row(_ range: Range<Int>, icon: CGFloat, label: CGFloat) -> some View {
        HStack(spacing: 8) {
            ForEach(shortcuts[range]) { item in
                SleeveTile(symbol: item.symbol, title: item.title, url: item.url,
                           dark: dark, icon: icon, label: label)
            }
        }
    }

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5).padding(3)
            Image(systemName: "music.note")
                .font(.system(size: 19, weight: .semibold))
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(LunaraLink.resume)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Lunara", systemImage: "music.note").font(.headline)
            Text("Tap to play").font(.caption)
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(LunaraLink.resume)
    }

    private var inline: some View {
        Label("Lunara", systemImage: "music.note")
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(LunaraLink.resume)
    }
}

struct LunaraWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LunaraWidget", provider: LunaraProvider()) { entry in
            LunaraWidgetView(entry: entry)
        }
        .configurationDisplayName("Lunara")
        .description("Play, search, liked songs, and offline music.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

@main
struct LunaraWidgetBundle: WidgetBundle {
    var body: some Widget { LunaraWidget() }
}
