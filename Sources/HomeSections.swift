import SwiftUI

struct ChipsRow: View {
    @Environment(\.palette) private var palette
    let chips: [HomeChip]
    let selected: HomeChip?
    let onSelect: (HomeChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let isSelected = (selected?.title ?? chips.first?.title) == chip.title
                    Text(chip.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? palette.onAccent : palette.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isSelected ? AnyShapeStyle(palette.accent) : AnyShapeStyle(palette.onSurface.opacity(0.06)))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                        .onTapGesture { onSelect(chip) }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }
}

struct QuickPicksGrid: View {
    @Environment(\.palette) private var palette
    let section: HomeSection
    @ObservedObject var player: Player

    private let rows = Array(repeating: GridItem(.fixed(56), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSectionHeader(
                title: section.title,
                onPlayAll: section.items.isEmpty ? nil : {
                    player.play(section.items.map(\.asTrack), startAt: 0)
                },
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 12) {
                    ForEach(0..<section.items.count, id: \.self) { index in
                        let item = section.items[index]
                        let track = item.asTrack
                        HStack(spacing: 4) {
                            Button {
                                player.play(section.items.map(\.asTrack), startAt: index)
                            } label: {
                                cell(item)
                            }
                            .buttonStyle(.plain)

                            SongRowMenu(track: track, player: player, trailingPadding: 2)
                        }
                        .frame(width: 280, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func cell(_ item: HomeItem) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: item.thumbnailURL, size: 50) { palette.onSurface.opacity(0.06) }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(palette.onSurface).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.accent).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct MoodTiles: View {
    @Environment(\.palette) private var palette
    let moods: [MoodItem]
    let onTap: (MoodItem) -> Void

    private let rows = Array(repeating: GridItem(.fixed(52), spacing: 10), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Moods & genres")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 10) {
                    ForEach(moods) { mood in
                        Button { onTap(mood) } label: {
                            Text(mood.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.onSurface)
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                                .frame(width: 150, height: 52, alignment: .leading)
                                .background(Color(hex: mood.colorARGB & 0xFFFFFF))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct PlaylistGridCard: View {
    @Environment(\.palette) private var palette
    let item: HomeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: item.thumbnailURL) {
                palette.onSurface.opacity(0.06)
                    .overlay(Image(systemName: "music.note.list")
                        .font(.system(size: 36))
                        .foregroundStyle(palette.onSurface.opacity(0.35)))
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.onSurface).lineLimit(1)
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
            }
        }
    }
}

struct HomeSectionHeader: View {
    @Environment(\.palette) private var palette
    let title: String
    var onPlayAll: (() -> Void)?
    var onSeeAll: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(palette.accent)
                .frame(width: 3.5, height: 18)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let onPlayAll {
                Button(action: onPlayAll) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(palette.accent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            if let onSeeAll {
                Button(action: onSeeAll) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

struct HomeSectionScreen: View {
    @Environment(\.palette) private var palette
    let section: HomeSection
    @ObservedObject var player: Player
    let onOpen: (HomeItem) -> Void

    @State private var items: [HomeItem] = []
    @State private var loading = true
    @State private var next: String?
    @State private var extending = false
    @State private var confirmStopDownload = false
    @ObservedObject private var downloads = Downloads.shared

    private let wanted = 50

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private var songs: [Track] {
        items.filter { $0.browseId == nil && !($0.videoId ?? "").isEmpty }.map(\.asTrack)
    }

    private var isSongList: Bool {
        !items.isEmpty && items.allSatisfy { $0.browseId == nil && !($0.videoId ?? "").isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !songs.isEmpty {
                    actions
                }
                if isSongList {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { at, item in
                            songRow(item, at: at)
                        }
                    }
                    .padding(.top, 4)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { item in
                            LunaraMusicCard(title: item.title, subtitle: item.subtitle,
                                           thumbnail: item.thumbnail, isCircular: item.isCircular,
                                           fallbackIcon: item.isCircular ? "person.fill" : "music.note") {
                                open(item)
                            }
                        }
                    }
                    .padding(16)
                }

                if loading || extending {
                    LunaraLoader(size: 44)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Stop downloading?", isPresented: $confirmStopDownload) {
            Button("Keep downloading", role: .cancel) {}
            Button("Stop", role: .destructive) { downloads.cancelAll(songs) }
        } message: {
            Text("Songs still waiting or arriving are stopped. Songs that already finished stay on your phone.")
        }
        .task { await load() }
    }

    private func songRow(_ item: HomeItem, at index: Int) -> some View {
        HStack(spacing: 0) {
            Button {
                open(item)
            } label: {
                TrackRow(track: item.asTrack)
                    .padding(.leading, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            SongRowMenu(track: item.asTrack, player: player,
                        onAddToPlaylist: nil, onOpenArtist: nil)
                .padding(.trailing, 8)
        }
        .onAppear {
            if index >= items.count - 5 { Task { await extend() } }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                player.play(songs, startAt: 0)
            } label: {
                label("play.fill", "Play")
                    .foregroundStyle(.black)
                    .background(palette.heroGradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                player.isShuffled = true
                player.play(songs.shuffled(), startAt: 0)
            } label: {
                label("shuffle", "Shuffle")
                    .foregroundStyle(palette.onSurface)
                    .background(palette.onSurface.opacity(0.10))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if anyDownloading {
                Button { confirmStopDownload = true } label: {
                    HStack(spacing: 8) {
                        LunaraDownloadLoader(size: 22)
                        Text("Downloading").font(.lunara(15, .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9.5)
                    .foregroundStyle(palette.onSurface)
                    .background(palette.onSurface.opacity(0.10))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Downloading. Tap to stop")
            } else {
                Button {
                    for track in songs where downloads.state(track.videoId) == .none {
                        downloads.download(track)
                    }
                } label: {
                    label(allKept ? "checkmark.circle.fill" : "arrow.down.circle",
                          allKept ? "Downloaded" : "Download all")
                        .foregroundStyle(allKept ? Lunara.green : palette.onSurface)
                        .background(palette.onSurface.opacity(0.10))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(allKept)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var anyDownloading: Bool {
        songs.contains { downloads.state($0.videoId) == .downloading }
    }

    private var allKept: Bool {
        !songs.isEmpty && songs.allSatisfy { downloads.state($0.videoId) == .done }
    }

    private func label(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold))
            Text(text).font(.lunara(15, .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func load() async {
        await MainActor.run { if items.isEmpty { items = section.items } }
        guard let browseId = section.browseId, !browseId.isEmpty else {
            await MainActor.run { loading = false }
            await topUp()
            return
        }
        let page = await YouTube.shelfPage(browseId: browseId, params: section.params)
        await MainActor.run {
            if !page.items.isEmpty { items = page.items }
            next = page.next
            loading = false
        }
        await topUp()
    }

    private func topUp() async {
        guard next == nil, isSongList, items.count < wanted else { return }
        await MainActor.run { extending = true }

        var gathered = items
        var known = Set(items.compactMap(\.videoId))
        for seed in items.prefix(4) {
            guard gathered.count < wanted, let id = seed.videoId, !id.isEmpty else { break }
            let shelves = await YouTube.related(videoId: id)
            let fresh = shelves
                .flatMap(\.items)
                .filter { $0.browseId == nil }
                .filter { item in
                    guard let v = item.videoId, !v.isEmpty else { return false }
                    return !known.contains(v)
                }
            for item in fresh where gathered.count < wanted {
                if let v = item.videoId { known.insert(v) }
                gathered.append(item)
            }
        }

        let found = gathered
        await MainActor.run {
            items = found
            extending = false
        }
    }

    private func extend() async {
        guard let token = next, !extending, let browseId = section.browseId else { return }
        await MainActor.run { extending = true }
        let page = await YouTube.shelfPage(browseId: browseId, params: section.params,
                                           continuation: token)
        await MainActor.run {
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            next = page.next
            extending = false
        }
    }

    private func open(_ item: HomeItem) {
        guard item.browseId == nil else {
            onOpen(item)
            return
        }
        let playable = items.filter { $0.browseId == nil && !($0.videoId ?? "").isEmpty }
        guard let at = playable.firstIndex(where: { $0.videoId == item.videoId }) else { return }
        player.play(playable.map(\.asTrack), startAt: at)
    }
}
