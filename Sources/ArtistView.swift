import SwiftUI

struct ArtistView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var favoriteArtists = FavoriteArtistStore.shared
    let browseId: String
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    @State private var page: ArtistPage?
    @State private var loading = true
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    if loading {
                        VStack(alignment: .leading, spacing: 0) {
                            SkeletonBox(height: 360, corner: 0)
                            SkeletonTrackList(rows: 4).padding(.top, 20)
                            SkeletonRail()
                        }
                    } else if let page {
                        VStack(alignment: .leading, spacing: 0) {
                            hero(page)
                            actionRow(page)
                            aboutSection(page)
                            ForEach(page.sections) { section in
                                sectionView(section)
                            }
                        }
                        .playerBottomPadding()
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "person.slash").font(.lunara(36))
                                .foregroundStyle(palette.onSurfaceVariant)
                            Text("Couldn't load this artist")
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                        .padding(.top, 100)
                    }
                }
                .ignoresSafeArea(edges: .top)

                floatingTopBar
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showShare) {
                if let page {
                    SharePlaylistSheet(
                        name: page.name,
                        songIds: firstSongs?.map(\.videoId) ?? [],
                        kindLabel: "ARTIST",
                        artworkURL: page.thumbnailURL,
                        customLink: "https://music.youtube.com/channel/\(page.channelId ?? browseId)"
                    )
                    .environment(\.palette, palette)
                }
            }
        }
        .task { await load() }
    }

    private var floatingTopBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()

            if page != nil {
                Button { showShare = true } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share artist")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func hero(_ page: ArtistPage) -> some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { g in
                RemoteImage(url: page.thumbnailURL, size: 640) { ArtPlaceholder() }
                    .frame(width: g.size.width, height: g.size.width * 0.96)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.25), location: 0),
                                .init(color: .clear, location: 0.3),
                                .init(color: .black.opacity(0.65), location: 0.78),
                                .init(color: .black, location: 1.0),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            .aspectRatio(1.04, contentMode: .fit)

            Text(page.name)
                .font(.lunara(32, .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    private func actionRow(_ page: ArtistPage) -> some View {
        let isFollowing = favoriteArtists.contains(browseId)
        return HStack(spacing: 10) {
            Button {
                favoriteArtists.toggle(
                    browseId: browseId,
                    name: page.name,
                    thumbnail: page.thumbnail,
                    subscribers: page.subscribers
                )
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isFollowing ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isFollowing ? Lunara.green : .white)
                    Text(isFollowing ? "Favorited" : "Favorite")
                        .font(.lunara(14, .semibold))
                        .foregroundStyle(isFollowing ? Lunara.green : .white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isFollowing ? Color(hex: 0x0A2413) : Color(hex: 0x161616))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isFollowing ? Lunara.green.opacity(0.5) : Color.white.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if let songs = firstSongs, let first = songs.first {
                Button {
                    player.playWithRadio(first)
                    player.openFullPlayer()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Radio")
                            .font(.lunara(14, .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: 0x161616))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if let songs = firstSongs, !songs.isEmpty {
                Button {
                    player.isShuffled = true
                    player.play(songs.shuffled(), startAt: 0)
                    player.openFullPlayer()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(Lunara.green)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shuffle")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func aboutSection(_ page: ArtistPage) -> some View {
        if !page.subscribers.isEmpty && ContentPrefs.shared.showSubscriberCount {
            VStack(alignment: .leading, spacing: 6) {
                Text("About")
                    .font(.lunara(18, .bold))
                    .foregroundStyle(.white)
                Text(page.subscribers)
                    .font(.lunara(14))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
    }

    private var firstSongs: [Track]? {
        page?.sections.first(where: { !$0.songs.isEmpty })?.songs
    }

    @ViewBuilder private func sectionView(_ section: ArtistSection) -> some View {
        if !section.title.isEmpty {
            HStack(spacing: 10) {
                Capsule()
                    .fill(Lunara.green)
                    .frame(width: 3.5, height: 18)
                Text(section.title)
                    .font(.lunara(20, .bold))
                    .foregroundStyle(.white)
                Spacer()
                if !section.songs.isEmpty {
                    Button {
                        player.play(section.songs, startAt: 0)
                        player.openFullPlayer()
                    } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
        }

        if !section.songs.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(Array(section.songs.enumerated()), id: \.element.id) { pair in
                    artistSongRow(pair.element) {
                        player.play(section.songs, startAt: pair.offset)
                        player.openFullPlayer()
                    }
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(section.cards) { card in
                        MusicCard(item: card) {
                            if let vid = card.videoId, !vid.isEmpty {
                                player.play([card.asTrack], startAt: 0)
                                player.openFullPlayer()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func artistSongRow(_ track: Track, onTap: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    RemoteImage(url: track.thumbnailURL, size: 52) {
                        Color.white.opacity(0.08)
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            if track.isExplicit {
                                Text("E")
                                    .font(.system(size: 9.5, weight: .heavy))
                                    .foregroundStyle(.black)
                                    .frame(width: 14, height: 14)
                                    .background(Color.white.opacity(0.65))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            Text(subtitle(for: track))
                                .font(.system(size: 13))
                                .foregroundStyle(Lunara.green)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    DownloadRing(videoId: track.videoId)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SongRowMenu(track: track, player: player)
                .padding(.trailing, 8)
        }
        .padding(.leading, 16)
    }

    private func subtitle(for track: Track) -> String {
        guard track.duration > 0 else { return track.artist }
        let mins = Int(track.duration) / 60
        let secs = Int(track.duration) % 60
        return track.artist.isEmpty
            ? String(format: "%d:%02d", mins, secs)
            : "\(track.artist) • \(String(format: "%d:%02d", mins, secs))"
    }

    private func load() async {
        loading = true
        let p = await YouTube.artist(browseId: browseId)
        await MainActor.run {
            page = p
            loading = false
        }
    }
}
