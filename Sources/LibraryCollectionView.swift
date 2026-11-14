import SwiftUI

struct LibraryCollectionView: View {
    enum Kind {
        case albums, artists, playlists

        var title: String {
            switch self {
            case .albums: String(localized: "Albums")
            case .artists: String(localized: "Artists")
            case .playlists: String(localized: "Playlists")
            }
        }
    }

    @Environment(\.palette) private var palette
    let kind: Kind
    @ObservedObject var player: Player
    @ObservedObject private var localPlaylists = LocalPlaylistStore.shared
    @ObservedObject private var favoriteArtists = FavoriteArtistStore.shared

    @State private var route: LibraryRoute?
    @State private var query = ""
    @State private var searching = false
    @State private var importingSpotify = false

    private var items: [HomeItem] {
        switch kind {
        case .playlists: return localPlaylists.playlists.map(\.asHomeItem)
        case .artists: return favoriteArtists.artists.map(\.asHomeItem)
        case .albums: return []
        }
    }

    private var shown: [HomeItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.title.lowercased().contains(q) }
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if shown.isEmpty {
                    Text("Nothing in your \(kind.title.lowercased()) yet.")
                        .font(.lunara(14))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if kind == .playlists {
                    playlistCards
                } else {
                    grid
                }
            }
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { searching.toggle() }
                    if !searching { query = "" }
                } label: {
                    Image(systemName: searching ? "xmark" : "magnifyingglass")
                        .foregroundStyle(palette.onSurface)
                }
            }
            if kind == .playlists {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importingSpotify = true } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(palette.onSurface)
                    }
                    .accessibilityLabel("Import from Spotify")
                }
            }
        }
        .fullScreenCover(isPresented: $importingSpotify) {
            SpotifyImportDialog(player: player)
                .environment(\.palette, palette)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if searching {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(palette.onSurfaceVariant)
                    TextField("Search \(kind.title.lowercased())", text: $query)
                        .foregroundStyle(palette.onSurface)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(palette.surfaceHigh)
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(palette.scaffold)
            }
        }
        .navigationDestination(item: $route) { LibraryRouteView(route: $0, player: player) }
    }

    private var playlistCards: some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: 0, to: shown.count, by: 2)), id: \.self) { i in
                HStack(spacing: 12) {
                    LunaraPlaylistCard(
                        title: shown[i].title,
                        subtitle: LibraryCardText.subtitle(shown[i].subtitle),
                        thumbnails: [shown[i].thumbnail],
                        seed: LunaraPalette.color(i), aspectRatio: 1.55
                    ) { route = .playlist(shown[i]) }

                    if i + 1 < shown.count {
                        LunaraPlaylistCard(
                            title: shown[i + 1].title,
                            subtitle: LibraryCardText.subtitle(shown[i + 1].subtitle),
                            thumbnails: [shown[i + 1].thumbnail],
                            seed: LunaraPalette.color(i + 1), aspectRatio: 1.55
                        ) { route = .playlist(shown[i + 1]) }
                    } else {
                        Color.clear
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 8)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(shown) { item in
                Button {
                    if kind == .artists, let id = item.browseId {
                        route = .artist(id)
                    } else {
                        route = .playlist(item)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        RemoteImage(url: item.thumbnailURL, size: 180) {
                            palette.onSurface.opacity(0.06)
                                .overlay(Image(systemName: kind == .artists ? "person.fill" : "square.stack")
                                    .font(.lunara(36))
                                    .foregroundStyle(palette.onSurface.opacity(0.35)))
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: kind == .artists ? 999 : 12))

                        Text(item.title)
                            .font(.lunara(14, .semibold))
                            .foregroundStyle(palette.onSurface)
                            .lineLimit(1)
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.lunara(12))
                                .foregroundStyle(palette.onSurfaceVariant)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}
