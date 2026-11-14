import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var showStorage = false
    @State private var showLyrics = false
    @State private var showPlayerSettings = false
    @State private var showStreams = false
    @State private var showContent = false
    @State private var showEqualizer = false
    @State private var showAbout = false

    private struct Row: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
        var action: Action
        enum Action { case player, equalizer, streams, content, lyrics, storage, about }
    }

    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let rows: [Row]
    }

    private var groups: [Group] {
        [
            Group(title: "Playback & Audio", rows: [
                Row(icon: "play.circle", title: "Player and audio",
                    subtitle: "Quality, crossfade, sleep timer, queue",
                    action: .player),
                Row(icon: "slider.horizontal.3", title: "Equaliser",
                    subtitle: "Ten bands, bass and stereo width",
                    action: .equalizer),
                Row(icon: "antenna.radiowaves.left.and.right", title: "Stream sources",
                    subtitle: "Which clients resolve a song, and in what order",
                    action: .streams),
            ]),
            Group(title: "Content & Lyrics", rows: [
                Row(icon: "globe", title: "Content",
                    subtitle: "Language, region, explicit and video filters",
                    action: .content),
                Row(icon: "quote.bubble", title: "Lyrics",
                    subtitle: "Sources, priority, style, display",
                    action: .lyrics),
            ]),
            Group(title: "Storage", rows: [
                Row(icon: "internaldrive", title: "Storage",
                    subtitle: "Cache, downloads, clear data",
                    action: .storage),
            ]),
            Group(title: "Lunara", rows: [
                Row(icon: "info.circle", title: "About Lunara",
                    subtitle: "The story, principles, and people behind the player",
                    action: .about),
            ]),
        ]
    }

    private var filtered: [Group] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return groups }
        return groups.compactMap { group in
            let rows = group.rows.filter {
                $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
            }
            return rows.isEmpty ? nil : Group(title: group.title, rows: rows)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    searchField
                    if query.isEmpty {
                        Spacer().frame(height: 12)
                        quickToggles
                    }

                    ForEach(filtered) { group in
                        Spacer().frame(height: 18)
                        HStack {
                            Text(group.title.uppercased())
                                .font(.lunara(12, .bold))
                                .tracking(1.2)
                                .foregroundStyle(palette.onSurfaceVariant)
                                .padding(.leading, 6)
                            Spacer()
                        }
                        .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { i, row in
                                settingRow(row)
                                if i < group.rows.count - 1 {
                                    Divider().overlay(palette.onSurface.opacity(0.06))
                                        .padding(.leading, 68)
                                }
                            }
                        }
                        .background(palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(palette.accent)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.current != nil {
                    MiniPlayerView(player: player) {
                        dismiss()
                        player.openFullPlayer()
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .preferredColorScheme(theme.preferredColorScheme)
        .environment(\.palette, Palette(dark: theme.resolvedDark))
        .sheet(isPresented: $showStorage) {
            NavigationStack { StorageSettingsView().settingsMiniPlayer(player) }
                .preferredColorScheme(theme.preferredColorScheme)
                .environment(\.palette, Palette(dark: theme.resolvedDark))
        }
        .sheet(isPresented: $showLyrics) {
            NavigationStack { LyricsSettingsView().settingsMiniPlayer(player) }
                .preferredColorScheme(theme.preferredColorScheme)
                .environment(\.palette, Palette(dark: theme.resolvedDark))
        }
        .sheet(isPresented: $showPlayerSettings) {
            NavigationStack { PlayerSettingsView().settingsMiniPlayer(player) }
                .preferredColorScheme(theme.preferredColorScheme)
                .environment(\.palette, Palette(dark: theme.resolvedDark))
        }
        .sheet(isPresented: $showStreams) {
            NavigationStack { StreamSourcesView().settingsMiniPlayer(player) }
                .preferredColorScheme(theme.preferredColorScheme)
                .environment(\.palette, Palette(dark: theme.resolvedDark))
        }
        .sheet(isPresented: $showContent) {
            NavigationStack { ContentSettingsView().settingsMiniPlayer(player) }
                .preferredColorScheme(theme.preferredColorScheme)
                .environment(\.palette, Palette(dark: theme.resolvedDark))
        }
        .sheet(isPresented: $showEqualizer) {
            NavigationStack { EqualizerView(player: player).settingsMiniPlayer(player) }
                .preferredColorScheme(theme.preferredColorScheme)
                .environment(\.palette, Palette(dark: theme.resolvedDark))
        }
        .sheet(isPresented: $showAbout) {
            NavigationStack { AboutLunaraView() }
                .preferredColorScheme(theme.preferredColorScheme)
                .environment(\.palette, Palette(dark: theme.resolvedDark))
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.lunara(16)).foregroundStyle(palette.onSurfaceVariant)
            TextField("Search settings", text: $query)
                .font(.lunara(15))
                .foregroundStyle(palette.onSurface)
                .tint(palette.accent)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.onSurface.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(palette.onSurface.opacity(0.06))
        .clipShape(Capsule())
    }

    // MARK: Quick toggles

    private var quickToggles: some View {
        HStack(spacing: 8) {
            quickChip(icon: themeModeIcon, label: theme.darkMode.title,
                      active: theme.darkMode != .auto) { cycleDarkMode() }
            quickChip(icon: "paintpalette", label: "Dynamic", active: theme.dynamicTheme) {
                theme.setDynamicTheme(!theme.dynamicTheme)
            }
            quickChip(icon: "circle.fill", label: "Pure black", active: theme.pureBlack) {
                theme.setPureBlack(!theme.pureBlack)
            }
        }
    }

    private var themeModeIcon: String {
        switch theme.darkMode {
        case .auto: "circle.lefthalf.filled"
        case .on: "moon.stars"
        case .off: "sun.max"
        }
    }

    private func cycleDarkMode() {
        switch theme.darkMode {
        case .auto: theme.setDarkMode(.on)
        case .on: theme.setDarkMode(.off)
        case .off: theme.setDarkMode(.auto)
        }
    }

    private func quickChip(icon: String, label: String, active: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.lunara(20))
                Text(label).font(.system(size: 11, weight: active ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? palette.accent : palette.onSurfaceVariant)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12).padding(.horizontal, 8)
            .background(active ? palette.accent.opacity(0.18) : palette.onSurface.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(active ? palette.accent : .clear, lineWidth: 1.5),
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Rows

    private func settingRow(_ row: Row) -> some View {
        Button {
            switch row.action {
            case .player: showPlayerSettings = true
            case .equalizer: showEqualizer = true
            case .streams: showStreams = true
            case .content: showContent = true
            case .lyrics: showLyrics = true
            case .storage: showStorage = true
            case .about: showAbout = true
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: row.icon)
                    .font(.lunara(19))
                    .foregroundStyle(palette.accent)
                    .frame(width: 40, height: 40)
                    .background(palette.accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.lunara(15, .semibold))
                        .foregroundStyle(palette.onSurface).lineLimit(1)
                    Text(row.subtitle)
                        .font(.lunara(12.5))
                        .foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.lunara(13)).foregroundStyle(palette.onSurface.opacity(0.35))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AboutLunaraView: View {
    @Environment(\.palette) private var palette

    var body: some View {
        SettingsPage(title: "About Lunara") {
            VStack(spacing: 14) {
                Image(bundleImage: "icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)

                Text("Lunara for iOS")
                    .font(.lunara(24, .bold))
                    .foregroundStyle(palette.onSurface)

                Text("A focused music player for discovery, playback, lyrics, and your local library.")
                    .font(.lunara(14))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            SettingsGroup(title: "What Lunara is") {
                aboutText("Lunara brings streaming discovery, background playback, synchronized lyrics, downloads, local music, playlists, equalizer controls, and a home screen widget together in one calm, personal listening space.")
                SettingsDivider()
                aboutText("The app is designed to feel fast and tactile while keeping your library, preferences, playback history, and cached content on your device.")
            }

            SettingsGroup(title: "Built with care") {
                aboutText("Lunara is developed by Ankit Khatri KC with SwiftUI for iOS. The project is shaped around thoughtful interaction design, reliable playback, accessible controls, and a clear visual identity.")
                SettingsDivider()
                aboutText("Lunara is an independent project and is not affiliated with Apple, YouTube, Spotify, or any of the services it can connect to.")
            }

            SettingsGroup(title: "Version") {
                HStack {
                    SettingsIcon("app.badge")
                    Text("Lunara for iOS")
                        .font(.lunara(15, .medium))
                        .foregroundStyle(palette.onSurface)
                    Spacer()
                    Text(version)
                        .font(.lunara(13, .semibold))
                        .foregroundStyle(palette.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            Text("Thank you for listening with Lunara.")
                .font(.lunara(13, .medium))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let number = info?["CFBundleShortVersionString"] as? String ?? "0.5.1"
        let build = info?["CFBundleVersion"] as? String ?? "6"
        return "\(number) (\(build))"
    }

    private func aboutText(_ text: String) -> some View {
        Text(text)
            .font(.lunara(13))
            .foregroundStyle(palette.onSurfaceVariant)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }
}
