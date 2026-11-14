import SwiftUI

struct MoodDetailView: View {
    @Environment(\.palette) private var palette
    let mood: MoodItem
    @ObservedObject var player: Player

    @State private var forYou: [HomeSection] = []
    @State private var playlists: [HomeItem] = []
    @State private var loading = true
    @State private var openCard: CardRoute?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if loading {
                SkeletonGrid()
            } else if playlists.isEmpty, forYou.isEmpty {
                Text("Nothing here")
                    .foregroundStyle(palette.onSurfaceVariant)
                    .padding(.top, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(forYou) { section in
                        if section.isSongs {
                            QuickPicksGrid(section: section, player: player)
                        } else {
                            HomeRail(section: section, onTap: { tap($0, within: $1) })
                        }
                    }

                    if !playlists.isEmpty {
                        if !forYou.isEmpty {
                            HomeSectionHeader(title: String(localized: "Playlists"))
                        }
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(playlists) { item in
                                NavigationLink(value: item) { PlaylistGridCard(item: item) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .playerBottomInsetArea()
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle(mood.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openCard) { PlaylistView(item: $0.item, player: player) }
        .task {
            async let shelves = YouTube.moodShelves(for: mood.title)
            async let grid = YouTube.moodPlaylists(browseId: mood.browseId ?? "", params: mood.params)
            let (s, g) = await (shelves, grid)
            await MainActor.run {
                forYou = s
                playlists = g
                loading = false
            }
        }
    }

    private func tap(_ item: HomeItem, within row: [HomeItem]) {
        guard item.browseId == nil else {
            openCard = CardRoute(item: item)
            return
        }
        guard let vid = item.videoId, !vid.isEmpty else { return }
        let songs = row.filter { $0.browseId == nil && !($0.videoId ?? "").isEmpty }
        if songs.isEmpty {
            player.playWithRadio(item.asTrack)
        } else {
            let start = songs.firstIndex { $0.videoId == vid } ?? 0
            player.play(songs.map(\.asTrack), startAt: start)
        }
    }
}
