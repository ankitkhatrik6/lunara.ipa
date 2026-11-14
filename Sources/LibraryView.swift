import SwiftUI

struct LibraryView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var localPlaylists = LocalPlaylistStore.shared
    @ObservedObject private var favoriteArtists = FavoriteArtistStore.shared
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var cache = AudioCache.shared
    @ObservedObject private var local = LocalMusic.shared

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case playlists = "Playlists"
        case artists = "Artists"
        case downloaded = "Downloaded"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var showFilterSearch = false
    @State private var filterQuery = ""
    @State private var route: LibraryRoute?
    @State private var importingSpotify = false
    @State private var showCreatePlaylist = false
    @State private var newPlaylistTitle = ""

    private let userRatio: CGFloat = 1.55

    private var trimmedFilter: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func matchesSearch(_ text: String) -> Bool {
        trimmedFilter.isEmpty || text.lowercased().contains(trimmedFilter)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    libraryHeading
                    if showFilterSearch {
                        inlineSearchBar
                    }
                    filterChips

                    VStack(spacing: 12) {
                        if filter == .all || filter == .playlists {
                            if matchesSearch("Liked") {
                                libraryCard(
                                    title: "Liked",
                                    subtitle: likedTracks.count == 1 ? "1 song" : "\(likedTracks.count) songs",
                                    icon: "heart.fill"
                                ) { route = .tracks("Liked", likedTracks) }
                            }

                            if ContentPrefs.shared.showStatsPlaylists && matchesSearch("Your Top") {
                                libraryCard(
                                    title: "Your Top \(PlayHistory.topSize)",
                                    subtitle: "Most played tracks",
                                    icon: "chart.line.uptrend.xyaxis"
                                ) { route = .topPlaylist }
                            }
                        }

                        if filter == .all || filter == .downloaded {
                            if matchesSearch("Downloaded") {
                                libraryCard(
                                    title: "Downloaded",
                                    subtitle: downloads.tracks.isEmpty ? "Downloaded songs" : "\(downloads.tracks.count) songs",
                                    icon: "arrow.down"
                                ) { route = .tracks("Downloaded", downloads.tracks) }
                            }
                        }

                        if filter == .all || filter == .playlists {
                            if matchesSearch("Create playlist") {
                                libraryCard(
                                    title: "Create playlist",
                                    subtitle: "Start a new playlist",
                                    icon: "plus"
                                ) {
                                    newPlaylistTitle = ""
                                    showCreatePlaylist = true
                                }
                            }
                        }

                        if filter == .all || filter == .downloaded {
                            if matchesSearch("Music on this device") {
                                libraryCard(
                                    title: "Music on this device",
                                    subtitle: localSize,
                                    icon: "iphone.gen3"
                                ) { route = .local }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    let visiblePlaylists = localPlaylists.playlists.map(\.asHomeItem).filter { matchesSearch($0.title) }
                    if (filter == .all || filter == .playlists) && !visiblePlaylists.isEmpty {
                        Spacer().frame(height: 8)
                        LunaraSectionHeader(title: "Created by you")
                        createdByYou(visiblePlaylists)
                    }

                    let visibleArtists = favoriteArtists.artists.map(\.asHomeItem).filter { matchesSearch($0.title) }
                    if (filter == .all || filter == .artists) && !visibleArtists.isEmpty {
                        Spacer().frame(height: 8)
                        LunaraSectionHeader(title: "Artists you liked")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(visibleArtists) { artist in
                                    LunaraMusicCard(title: artist.title,
                                                   subtitle: LibraryCardText.subtitle(artist.subtitle),
                                                   thumbnail: artist.thumbnail, isCircular: true,
                                                   fallbackIcon: "person.fill") {
                                        if let id = artist.browseId { route = .artist(id) }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .playerBottomPadding()
            }
            .background(palette.scaffold.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $route) { LibraryRouteView(route: $0, player: player) }
        }
        .fullScreenCover(isPresented: $importingSpotify) {
            SpotifyImportDialog(player: player)
                .environment(\.palette, palette)
        }
        .transaction { if importingSpotify { $0.disablesAnimations = true } }
        .alert("New playlist", isPresented: $showCreatePlaylist) {
            TextField("Playlist name", text: $newPlaylistTitle)
            Button("Create") {
                let title = newPlaylistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return }
                let created = localPlaylists.create(title: title)
                route = .playlist(created.asHomeItem)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a playlist saved on this device.")
        }
    }

    // MARK: Top Header & Controls

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Library")
                .font(.lunara(19, .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Button { importingSpotify = true } label: {
                HStack(spacing: 8) {
                    SpotifyMark()
                        .frame(width: 20, height: 20)
                    Text("Import from Spotify")
                        .font(.lunara(13.5, .semibold))
                        .foregroundStyle(Lunara.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(hex: 0x121A14))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Lunara.green.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var libraryHeading: some View {
        HStack {
            Text("Library")
                .font(.lunara(28, .bold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showFilterSearch.toggle()
                    if !showFilterSearch { filterQuery = "" }
                }
            } label: {
                Image(systemName: showFilterSearch ? "xmark" : "magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter library")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var inlineSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
            TextField("Filter playlists, artists…", text: $filterQuery)
                .font(.lunara(14.5))
                .foregroundStyle(.white)
                .tint(Lunara.green)
                .autocorrectionDisabled()
            if !filterQuery.isEmpty {
                Button { filterQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: 0x161616))
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { item in
                    let active = item == filter
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { filter = item }
                    } label: {
                        Text(item.rawValue)
                            .font(.lunara(13.5, active ? .bold : .semibold))
                            .foregroundStyle(active ? .black : .white.opacity(0.9))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(active ? Lunara.green : Color(hex: 0x181818))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    private func libraryCard(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.lunara(17, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.lunara(13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Lunara.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(hex: 0x141414))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers & Sections

    private var likedTracks: [Track] { player.favoriteTracks }

    private var localSize: String {
        guard !local.tracks.isEmpty else { return String(localized: "Scan local files") }
        let mb = Double(local.sizeBytes) / 1_048_576
        let count = local.tracks.count
        let songs = count == 1 ? String(localized: "1 song") : String(localized: "\(count) songs")
        return mb < 1 ? songs : songs + String(format: " · %.0f MB", mb)
    }

    private func createdByYou(_ items: [HomeItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                HStack(spacing: 12) {
                    LunaraPlaylistCard(
                        title: items[i].title,
                        subtitle: LibraryCardText.subtitle(items[i].subtitle),
                        thumbnails: [items[i].thumbnail],
                        seed: LunaraPalette.color(i), aspectRatio: userRatio,
                    ) { route = .playlist(items[i]) }

                    if i + 1 < items.count {
                        LunaraPlaylistCard(
                            title: items[i + 1].title,
                            subtitle: LibraryCardText.subtitle(items[i + 1].subtitle),
                            thumbnails: [items[i + 1].thumbnail],
                            seed: LunaraPalette.color(i + 1), aspectRatio: userRatio,
                        ) { route = .playlist(items[i + 1]) }
                    } else {
                        Color.clear
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

}

enum LibraryRoute: Hashable {
    case tracks(String, [Track])
    case artist(String)
    case local
    case playlist(HomeItem)
    case songs
    case albums
    case artists
    case playlists
    case history
    case topPlaylist
}

struct LibraryRouteView: View {
    let route: LibraryRoute
    @ObservedObject var player: Player
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var cache = AudioCache.shared

    var body: some View {
        switch route {
        case .tracks(let title, let tracks):
            SongListScreen(title: title, tracks: tracks, player: player)
        case .artist(let id):
            ArtistView(browseId: id, player: player)
        case .local:
            LocalMusicView(player: player)
        case .playlist(let item):
            PlaylistView(item: item, player: player)
        case .songs:
            SongListScreen(title: "Songs", filters: SongCategories.filters(player: player),
                           player: player)
        case .albums:
            LibraryCollectionView(kind: .albums, player: player)
        case .artists:
            LibraryCollectionView(kind: .artists, player: player)
        case .playlists:
            LibraryCollectionView(kind: .playlists, player: player)
        case .history:
            HistoryView(player: player)
        case .topPlaylist:
            SongListScreen(title: "Your Top \(PlayHistory.topSize)",
                           filters: SongCategories.topFilters, player: player)
        }
    }
}

enum SongCategories {
    static func filters(player: Player) -> [SongListFilter] {
        [
            SongListFilter("Library", PlayHistory.recent),
            SongListFilter("Liked", player.favoriteTracks),
            SongListFilter("Downloaded", Downloads.shared.tracks),
            SongListFilter("Cached", AudioCache.shared.tracks),
            SongListFilter("On this phone", LocalMusic.shared.tracks),
        ]
    }

    static var topFilters: [SongListFilter] {
        StatPeriod.topFilters.map {
            SongListFilter($0.title, PlayHistory.mostPlayed($0, limit: PlayHistory.topSize))
        }
    }
}
