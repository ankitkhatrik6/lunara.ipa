import SwiftUI
import UIKit

enum SongSort: String, CaseIterable, Identifiable {
    case createDate, name, artist, playTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createDate: String(localized: "Date added")
        case .name: String(localized: "Name")
        case .artist: String(localized: "Artist")
        case .playTime: String(localized: "Play time")
        }
    }
}

struct SongListFilter: Identifiable, Equatable {
    let id: String
    let title: String
    let tracks: [Track]

    init(_ title: String, _ tracks: [Track]) {
        id = title
        self.title = title
        self.tracks = tracks
    }
}

struct SongListScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.playerBottomInset) private var bottomInset

    let title: String
    var filters: [SongListFilter] = []
    var tracks: [Track] = []
    @ObservedObject var player: Player
    var emptyMessage: String?
    var emptyActionTitle: String?
    var emptyAction: (() -> Void)?

    @State private var filterIndex = 0
    @State private var sort: SongSort = .createDate
    @State private var descending = true
    @State private var searching = false
    @State private var query = ""
    @State private var showMenu = false
    @State private var showShare = false
    @State private var playlistTrack: Track?
    @State private var artist: ArtistRoute?

    private var source: [Track] {
        filters.isEmpty ? tracks : (filters[safe: filterIndex]?.tracks ?? [])
    }

    private var shown: [Track] {
        var list = source

        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
            }
        }

        switch sort {
        case .createDate: break
        case .name: list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist: list.sort { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .playTime: list.sort { PlayHistory.playCount($0.videoId) > PlayHistory.playCount($1.videoId) }
        }
        if sort == .createDate || sort == .playTime {
            if !descending { list.reverse() }
        } else if descending {
            list.reverse()
        }
        return list
    }

    private var totalDuration: String {
        let seconds = Int(source.reduce(0) { $0 + $1.duration })
        guard seconds > 0 else { return "" }
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? " • \(h)h \(m)m" : " • \(m) min"
    }

    var body: some View {
        ScrollViewReader { scroller in
        ScrollView {
            LazyVStack(spacing: 0) {
                if !filters.isEmpty { filterChips }
                header
                sortHeader

                ForEach(Array(shown.enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: 0) {
                        Button {
                            player.play(shown, startAt: index)
                        } label: {
                            TrackRow(track: track)
                                .padding(.leading, 16)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)

                        SongRowMenu(track: track, player: player,
                                    onAddToPlaylist: { playlistTrack = track },
                                    onOpenArtist: { openArtist(track) })
                            .padding(.trailing, 8)
                    }
                    .swipeToPlayNext(track, player: player)
                    .id(track.videoId)
                }

                if shown.isEmpty {
                    VStack(spacing: 12) {
                        Text(query.isEmpty ? "Nothing here yet" : "No matches")
                            .font(.lunara(15, .semibold))
                            .foregroundStyle(palette.onSurface)
                        if query.isEmpty, let emptyMessage {
                            Text(emptyMessage)
                                .font(.lunara(13))
                                .foregroundStyle(palette.onSurfaceVariant)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 36)
                        }
                        if query.isEmpty, let emptyActionTitle, let emptyAction {
                            Button(action: emptyAction) {
                                Text(emptyActionTitle)
                                    .font(.lunara(15, .semibold))
                                    .foregroundStyle(palette.onAccent)
                                    .padding(.horizontal, 26)
                                    .padding(.vertical, 12)
                                    .background(palette.accent)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                }
            }
            .playerBottomPadding()
        }
        .onAppear {
            guard let id = player.current?.videoId, shown.contains(where: { $0.videoId == id }) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scroller.scrollTo(id, anchor: .center)
            }
        }
        }
        .sheet(isPresented: $showShare) {
            SharePlaylistSheet(
                name: title,
                songIds: source.map(\.videoId),
                kindLabel: "PLAYLIST",
                artworkURL: source.first?.artURL(size: 544)
            )
            .environment(\.palette, palette)
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle(searching ? "" : title)
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
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if searching { searchField }
        }
        .confirmationDialog(title, isPresented: $showMenu, titleVisibility: .visible) {
            Button("Add to queue") { player.addToQueue(source) }
            if !source.allSatisfy({ Downloads.shared.isDownloaded($0.videoId) }) {
                Button("Download all") { Downloads.shared.downloadAll(source) }
            }
            if source.contains(where: { Downloads.shared.state($0.videoId) == .downloading }) {
                Button("Stop downloading", role: .destructive) { Downloads.shared.cancelAll(source) }
            }
            Button("Export playlist") { export() }
            if !source.isEmpty {
                Button("Share as a link") { showShare = true }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $playlistTrack) { AddToPlaylistSheet(track: $0) }
        .fullScreenCover(item: $artist) { ArtistView(browseId: $0.browseId, player: player) }
    }

    // MARK: Filter capsules

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(filters.enumerated()), id: \.element.id) { index, filter in
                    let active = index == filterIndex
                    Text(filter.title)
                        .font(.lunara(13, .semibold))
                        .foregroundStyle(active ? palette.onAccent : palette.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(active ? AnyShapeStyle(palette.accent)
                                           : AnyShapeStyle(palette.onSurface.opacity(0.06)))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                        .onTapGesture { filterIndex = index }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    // MARK: Cover · title · transport

    private var header: some View {
        VStack(spacing: 0) {
            RemoteImage(url: source.first?.artURL(size: 720), size: 240) {
                palette.onSurface.opacity(0.06)
            }
            .frame(width: 240, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: palette.accent.opacity(0.3), radius: 24, x: 0, y: 10)
            .padding(.top, 8)
            .padding(.bottom, 20)

            Text(title)
                .font(.lunara(26, .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 32)

            Text("\(source.count) song\(source.count == 1 ? "" : "s")\(totalDuration)")
                .font(.lunara(14))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.top, 12)

            HStack(spacing: 16) {
                circleButton("shuffle", size: 48, filled: false) {
                    let shuffled = source.shuffled()
                    guard !shuffled.isEmpty else { return }
                    player.play(shuffled, startAt: 0)
                    player.openFullPlayer()
                }
                circleButton("play.fill", size: 72, filled: true) {
                    guard !source.isEmpty else { return }
                    player.play(source, startAt: 0)
                    player.openFullPlayer()
                }
                circleButton("ellipsis", size: 48, filled: false) { showMenu = true }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
    }

    private func circleButton(_ icon: String, size: CGFloat, filled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: filled ? 32 : 22, weight: filled ? .bold : .regular))
                .foregroundStyle(filled ? palette.onAccent : palette.onSurface)
                .frame(width: size, height: size)
                .background(filled ? AnyShapeStyle(palette.accent)
                                   : AnyShapeStyle(palette.surfaceHigh))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Sort

    private var sortHeader: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(SongSort.allCases) { option in
                    Button {
                        if sort == option { descending.toggle() } else { sort = option }
                    } label: {
                        Label(option.title, systemImage: sort == option
                              ? (descending ? "arrow.down" : "arrow.up") : "")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sort.title)
                        .font(.lunara(13, .semibold))
                    Image(systemName: descending ? "arrow.down" : "arrow.up")
                        .font(.lunara(11, .bold))
                }
                .foregroundStyle(palette.accent)
            }
            Spacer()
            Text("\(shown.count)")
                .font(.lunara(13))
                .foregroundStyle(palette.onSurfaceVariant)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.onSurfaceVariant)
            TextField("Search in \(title)", text: $query)
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

    private func openArtist(_ track: Track) {
        if let id = track.artistId {
            artist = ArtistRoute(browseId: id)
            return
        }
        Task {
            let id = await YouTube.resolveArtistId(name: track.artist)
            await MainActor.run {
                artist = id.map(ArtistRoute.init)
            }
        }
    }

    private func export() {
        var text = "#EXTM3U\n"
        for track in source {
            text += "#EXTINF:\(Int(track.duration)),\(track.artist) - \(track.title)\n"
            text += "https://music.youtube.com/watch?v=\(track.videoId)\n"
        }
        let name = title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).m3u")
        try? text.write(to: url, atomically: true, encoding: .utf8)

        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController?
            .present(share, animated: true)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct SongRowMenu: View {
    @Environment(\.palette) private var palette
    let track: Track
    @ObservedObject var player: Player
    var onAddToPlaylist: (() -> Void)?
    var onOpenArtist: (() -> Void)?
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var dial = SpeedDial.shared

    @State private var playlistTrack: Track?
    @State private var artist: ArtistRoute?

    private var isFavorite: Bool { player.favorites.contains(track.videoId) }
    private var isDownloaded: Bool { downloads.isDownloaded(track.videoId) }

    var body: some View {
        Menu {
            ControlGroup {
                Button { player.playNext(track) } label: {
                    Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button {
                    if let onAddToPlaylist { onAddToPlaylist() } else { playlistTrack = track }
                } label: {
                    Label("Add to playlist", systemImage: "plus.circle")
                }
                if LocalMusic.isLocal(track.videoId) {
                    Button { player.addToQueue([track]) } label: {
                        Label("Add to queue", systemImage: "text.badge.plus")
                    }
                } else {
                    switch downloads.state(track.videoId) {
                    case .done:
                        Button(role: .destructive) { downloads.remove(track.videoId) } label: {
                            Label("Remove download", systemImage: "checkmark.circle.fill")
                        }
                    case .downloading:
                        Button { downloads.cancel(track.videoId) } label: {
                            Label("Stop downloading", systemImage: "xmark.circle")
                        }
                    case .none:
                        Button { downloads.download(track) } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                    }
                    Button { share() } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }

            if !LocalMusic.isLocal(track.videoId) {
                Button { player.addToQueue([track]) } label: {
                    Label("Add to queue", systemImage: "text.badge.plus")
                }
            }
            Button { player.setFavorite(track, liked: !isFavorite) } label: {
                Label(isFavorite ? "Remove from favourites" : "Add to favourites",
                      systemImage: isFavorite ? "heart.slash" : "heart")
            }
            Button { dial.toggle(track) } label: {
                Label(dial.isPinned(track.videoId)
                      ? "Unpin from speed dial" : "Pin to speed dial",
                      systemImage: dial.isPinned(track.videoId) ? "pin.slash" : "pin")
            }

            Divider()

            if LocalMusic.isLocal(track.videoId) {
                Button(role: .destructive) { LocalMusic.shared.remove(track.videoId) } label: {
                    Label("Remove from this phone", systemImage: "trash")
                }
            } else {
                Button {
                    if let onOpenArtist { onOpenArtist() } else { openArtist() }
                } label: {
                    Label("View artist", systemImage: "person")
                }
                if !track.artist.isEmpty {
                    let name = track.artist
                        .components(separatedBy: CharacterSet(charactersIn: ",&"))
                        .first?.trimmingCharacters(in: .whitespaces) ?? track.artist
                    let blocked = BlockedArtists.shared.isBlocked(id: track.artistId, name: name)
                    Button(role: blocked ? nil : .destructive) {
                        if blocked {
                            BlockedArtists.shared.unblock(id: track.artistId, name: name)
                        } else {
                            BlockedArtists.shared.block(id: track.artistId, name: name)
                        }
                    } label: {
                        Label(blocked ? "Unblock \(name)" : "Block \(name)",
                              systemImage: blocked ? "person.crop.circle.badge.checkmark" : "nosign")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.lunara(16))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .sheet(item: $playlistTrack) { AddToPlaylistSheet(track: $0) }
        .fullScreenCover(item: $artist) { ArtistView(browseId: $0.browseId, player: player) }
    }

    private func openArtist() {
        if let id = track.artistId {
            artist = ArtistRoute(browseId: id)
            return
        }
        Task {
            let id = await YouTube.resolveArtistId(name: track.artist)
            await MainActor.run {
                artist = id.map(ArtistRoute.init)
            }
        }
    }

    private func share() {
        guard let url = URL(string: "https://music.youtube.com/watch?v=\(track.videoId)") else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController?
            .present(sheet, animated: true)
    }
}
