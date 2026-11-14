import SwiftUI
import UIKit

struct RootView: View {
    @ObservedObject private var theme = AppTheme.shared
    @ObservedObject private var look = LookFeel.shared
    @StateObject private var player = Player()
    @State private var tab: LunaraTab = LookFeel.shared.defaultTab.tab
    @Environment(\.colorScheme) private var scheme

    @State private var safeBottom: CGFloat = 34

    private var bottomInset: CGFloat {
        (player.hasTrack ? 72 : 0) + (look.slimNavBar ? 54 : 70) + safeBottom
    }

    @State private var sharedPlaylist: PlaylistLink.Shared?
    @State private var visited: Set<LunaraTab> = [LookFeel.shared.defaultTab.tab]

    private var palette: Palette { Palette(dark: theme.isDark(scheme)) }

    @ViewBuilder
    private func tabContent(_ t: LunaraTab) -> some View {
        switch t {
        case .home: HomeView(player: player, tab: $tab)
        case .explore: NavigationStack { SearchView(player: player) }
        case .library: LibraryView(player: player)
        }
    }

    private var keepPlaylistBinding: Binding<Bool> {
        Binding(get: { sharedPlaylist != nil }, set: { if !$0 { sharedPlaylist = nil } })
    }

    private func keepSharedPlaylist() {
        guard let shared = sharedPlaylist else { return }
        sharedPlaylist = nil
        Task {
            var resolved = [String: Track]()
            await withTaskGroup(of: (String, Track?).self) { group in
                for id in shared.songIds {
                    group.addTask { (id, await YouTube.trackMetadata(videoId: id)) }
                }
                for await (id, track) in group {
                    if let track { resolved[id] = track }
                }
            }
            let tracks = shared.songIds.map { id in
                resolved[id] ?? Track(
                    videoId: id,
                    title: "Song",
                    artist: "",
                    thumbnail: Downloads.fallbackArt(id),
                    duration: 0
                )
            }
            await MainActor.run {
                _ = LocalPlaylistStore.shared.create(title: shared.name, tracks: tracks)
            }
        }
    }

    private func performPendingRequest() {
        guard let request = LunaraRequest.take() else { return }
        switch request {
        case .resume:
            if player.hasTrack, !player.isPlaying { player.toggle() }
            player.openFullPlayer()
        case .favourites:
            let songs = player.favoriteTracks.shuffled()
            guard !songs.isEmpty else {
                tab = .library
                return
            }
            player.isShuffled = true
            player.play(songs, startAt: 0)
            player.openFullPlayer()
        case .downloads:
            let songs = Downloads.shared.tracks.shuffled()
            guard !songs.isEmpty else {
                tab = .library
                return
            }
            player.isShuffled = true
            player.play(songs, startAt: 0)
            player.openFullPlayer()
        case .search:
            tab = .explore
        case .play(let videoId):
            Task { @MainActor in
                let related = await YouTube.related(videoId: videoId)
                    .flatMap(\.items)
                    .filter { $0.browseId == nil }
                    .map(\.asTrack)
                let named = related.first { $0.videoId == videoId }
                let track = named ?? Track(videoId: videoId, title: "Song",
                                           artist: "", thumbnail: "", duration: 0)
                var queue = [track]
                queue += related.filter { $0.videoId != videoId }
                player.play(queue, startAt: 0)
                player.openFullPlayer()
            }
        }
    }

    var body: some View {
        ZStack {
            ForEach(LunaraTab.allCases, id: \.self) { t in
                if visited.contains(t) {
                    tabContent(t)
                        .opacity(tab == t ? 1 : 0)
                        .allowsHitTesting(tab == t)
                        .zIndex(tab == t ? 1 : 0)
                }
            }
        }
        .onChange(of: tab) { visited.insert(tab) }
        .background(palette.scaffold.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if player.hasTrack {
                    MiniPlayerView(player: player)
                        .padding(.bottom, 8)
                }
                LunaraTabBar(selection: $tab, palette: palette, look: look)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .onAppear {
            performPendingRequest()
            PlayHistory.pruneOld()
            safeBottom = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first?.safeAreaInsets.bottom ?? 34
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            performPendingRequest()
        }
        .onOpenURL { url in
            if let shared = PlaylistLink.parse(url) {
                sharedPlaylist = shared
                return
            }
            guard let request = LunaraLink.request(for: url) else { return }
            request.store()
            performPendingRequest()
        }
        .alert("Keep this playlist?", isPresented: keepPlaylistBinding) {
            Button("Not now", role: .cancel) { sharedPlaylist = nil }
            Button("Save") { keepSharedPlaylist() }
        } message: {
            if let shared = sharedPlaylist {
                Text("\"\(shared.name)\" has \(shared.songIds.count) song\(shared.songIds.count == 1 ? "" : "s").")
            }
        }
        .environment(\.palette, palette)
        .environment(\.playerBottomInset, bottomInset)
        .preferredColorScheme(theme.preferredColorScheme)
        .tint(palette.accent)
        .fullScreenCover(isPresented: $player.showFullPlayer) {
            PlayerView(player: player)
                .environment(\.palette, palette)
                .presentationBackground(.clear)
        }
    }
}

enum LunaraTab: CaseIterable {
    case home, explore, library

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .explore: "magnifyingglass"
        case .library: "rectangle.stack.fill"
        }
    }
    var label: String {
        switch self {
        case .home: "Home"
        case .explore: "Search"
        case .library: "Library"
        }
    }
}

struct LunaraTabBar: View {
    @Binding var selection: LunaraTab
    let palette: Palette
    @ObservedObject var look: LookFeel

    var body: some View {
        HStack {
            ForEach(LunaraTab.allCases, id: \.self) { t in
                let active = t == selection
                Button {
                    selection = t
                } label: {
                    item(t, active: active)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: look.slimNavBar ? 54 : 66)
        .background(palette.dark ? Color.black.opacity(0.95) : palette.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.separator).frame(height: 0.5)
        }
    }

    private var idle: Color { palette.onSurfaceVariant }

    @ViewBuilder private func item(_ t: LunaraTab, active: Bool) -> some View {
        switch look.navBarStyle {
        case .pill:
            VStack(spacing: 4) {
                Image(systemName: t.icon)
                    .font(.system(size: 19, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? palette.onSurface : idle)
                    .frame(width: 56, height: 32)
                    .background(active ? AnyShapeStyle(palette.onSurface.opacity(0.14))
                                       : AnyShapeStyle(Color.clear))
                    .clipShape(Capsule())
                if !look.slimNavBar {
                    Text(t.label)
                        .font(.system(size: 11, weight: active ? .bold : .medium))
                        .foregroundStyle(active ? palette.onSurface : idle)
                }
            }

        case .gradient:
            VStack(spacing: 2) {
                Image(systemName: t.icon)
                    .font(.system(size: 20))
                if !look.slimNavBar {
                    Text(t.label).font(.system(size: 11))
                }
            }
            .foregroundStyle(active ? palette.onAccent : idle)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(
                            colors: [palette.accent.opacity(0.85),
                                     palette.accent.mixed(with: .black, 0.3).opacity(0.85)],
                            startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(palette.accent.opacity(0.55), lineWidth: 1))
                }
            }

        case .outlined:
            VStack(spacing: 2) {
                Image(systemName: t.icon)
                    .font(.system(size: 20))
                if !look.slimNavBar {
                    Text(t.label).font(.system(size: 11))
                }
            }
            .foregroundStyle(active ? palette.accent : idle)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.accent.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(palette.accent.opacity(0.7), lineWidth: 1))
                }
            }

        case .underline:
            VStack(spacing: 4) {
                Image(systemName: t.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(active ? palette.accent : idle)
                if !look.slimNavBar {
                    Text(t.label)
                        .font(.system(size: 11))
                        .foregroundStyle(active ? palette.accent : idle)
                }
                Capsule().fill(active ? palette.accent : .clear)
                    .frame(width: 22, height: 2.5)
            }
        }
    }
}
