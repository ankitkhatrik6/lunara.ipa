import SwiftUI

struct HomeView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @Binding var tab: LunaraTab
    @ObservedObject private var look = LookFeel.shared
    @ObservedObject private var net = Reachability.shared
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var cache = AudioCache.shared

    @State private var feed = HomeFeed.empty
    @State private var moods: [MoodItem] = []
    @State private var selectedChip: HomeChip?
    @State private var selectedMood: String? = nil
    @State private var loading = true
    @State private var loadingMore = false
    @State private var localSections: [HomeSection] = []
    @State private var path = NavigationPath()
    @State private var showSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    quickGrid
                    moodPillsRow

                    if !net.isOnline {
                        offlineFeed
                    } else {

                        if loading {
                            SkeletonRail()
                            SkeletonRail()
                        } else {
                            ForEach(localSections) { section in
                                row(section)
                            }

                            ForEach(feed.sections) { section in
                                row(section)
                            }

                            if !moods.isEmpty {
                                MoodTiles(moods: moods) { path.append($0) }
                            }

                            if let token = feed.continuation {
                                LunaraLoader(size: 44)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                                    .id(token)
                                    .onAppear { loadMore() }
                            }
                        }
                    }
                }
                .playerBottomPadding()
            }
            .refreshable { await load(reshuffle: true) }
            .background(palette.scaffold.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeItem.self) { item in
                PlaylistView(item: item, player: player)
            }
            .navigationDestination(for: HomeSection.self) { section in
                if section.isSongs {
                    SongListScreen(title: section.title,
                                   tracks: section.items.map(\.asTrack), player: player)
                } else {
                    HomeSectionScreen(section: section, player: player) { path.append($0) }
                }
            }
            .navigationDestination(for: MoodItem.self) { mood in
                MoodDetailView(mood: mood, player: player)
            }
            .navigationDestination(for: SearchRoute.self) { _ in
                SearchView(player: player, pushed: true)
            }
        }
        .task {
            if feed.sections.isEmpty { await load() }
        }
        .onChange(of: net.isOnline) {
            if net.isOnline { Task { await load() } }
        }
        .sheet(isPresented: $showSettings) { SettingsView(player: player) }
    }

    @ViewBuilder private func row(_ section: HomeSection) -> some View {
        if section.isSongs {
            QuickPicksGrid(section: section, player: player)
        } else {
            HomeRail(section: section,
                     onTap: { tap($0, within: $1) },
                     onSeeAll: { path.append(section) })
        }
    }

    private func tap(_ item: HomeItem, within row: [HomeItem] = []) {
        guard item.browseId == nil else {
            path.append(item)
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

    private func load(reshuffle: Bool = false) async {
        guard net.isOnline else {
            await MainActor.run { loading = false }
            return
        }
        if !reshuffle { loading = true }
        let seeds = Self.seedPool(player: player)
        async let feedTask = YouTube.home(params: selectedChip?.params)
        async let moodsTask = YouTube.moods()
        async let dynamicTask = Self.buildDynamicSections(seeds: seeds)
        let (f, m, dynamic) = await (feedTask, moodsTask, dynamicTask)
        await MainActor.run {
            if !f.sections.isEmpty {
                var kept = f
                kept.sections = f.sections.withoutShorts()
                feed = kept
            }
            let shuffle = ContentPrefs.shared.randomizeHomeOrder
            if !m.isEmpty { moods = shuffle ? m.shuffled() : m }
            let local = Self.buildLocalSections(player: player) + dynamic
            localSections = shuffle ? local.shuffled() : local
            loading = false
        }
    }

    private func loadMore() {
        guard PlaybackPrefs.shared.autoLoadMore else { return }
        guard let token = feed.continuation, !loadingMore else { return }
        loadingMore = true
        Task {
            let next = await YouTube.home(continuation: token)
            await MainActor.run {
                let existing = Set(feed.sections.map(\.title))
                feed.sections += next.sections.withoutShorts().filter { !existing.contains($0.title) }
                feed.continuation = next.continuation
                loadingMore = false
            }
        }
    }

    @MainActor
    private static func seedPool(player: Player) -> [Track] {
        var pool = player.favoriteTracks + PlayHistory.recent
        var seenIds = Set<String>()
        pool = pool.filter {
            !$0.videoId.isEmpty && !LocalMusic.isLocal($0.videoId)
                && seenIds.insert($0.videoId).inserted
        }
        return Array(pool.shuffled().prefix(3))
    }

    private static func buildDynamicSections(seeds: [Track]) async -> [HomeSection] {
        guard !seeds.isEmpty else { return [] }
        var sections: [HomeSection] = []
        var discover: [HomeItem] = []

        await withTaskGroup(of: (Track, [HomeSection]).self) { group in
            for seed in seeds {
                group.addTask { (seed, await YouTube.related(videoId: seed.videoId)) }
            }
            for await (seed, related) in group {
                guard let songs = related.first(where: { $0.isSongs }), songs.items.count >= 4 else { continue }
                let picked = songs.items.shuffled()
                discover += picked.prefix(5)
                sections.append(HomeSection(title: "Similar to \(seed.title)",
                                            items: Array(picked.prefix(12)), isSongs: false))
            }
        }

        if discover.count >= 4 {
            var unique = Set<String>()
            let mixed = discover.shuffled().filter { unique.insert($0.videoId ?? $0.title).inserted }
            sections.insert(HomeSection(title: "Daily discover",
                                        items: Array(mixed.prefix(16)), isSongs: true), at: 0)
        }
        return sections
    }

    private static func buildLocalSections(player: Player) -> [HomeSection] {
        var out: [HomeSection] = []

        func catalogue(_ tracks: [Track]) -> [Track] {
            tracks.filter { !LocalMusic.isLocal($0.videoId) }.withoutBlockedArtists()
        }

        let quick = catalogue(PlayHistory.mostPlayed(.month1, limit: 40)).shuffled().prefix(20)
        if quick.count >= 4 {
            out.append(HomeSection(title: "Quick picks",
                                   items: quick.map(\.asHomeItem), isSongs: true))
        }

        let keep = catalogue(PlayHistory.recent).prefix(40).shuffled().prefix(15)
        if keep.count >= 4 {
            out.append(HomeSection(title: "Keep listening",
                                   items: keep.map(\.asHomeItem), isSongs: false))
        }

        let recentIds = Set(PlayHistory.recent.prefix(20).map(\.videoId))
        let forgotten = catalogue(player.favoriteTracks)
            .filter { !recentIds.contains($0.videoId) }
            .shuffled().prefix(15)
        if forgotten.count >= 4 {
            out.append(HomeSection(title: "Forgotten favourites",
                                   items: forgotten.map(\.asHomeItem), isSongs: false))
        }
        return out
    }

    // MARK: - Offline

    @ViewBuilder private var offlineFeed: some View {
        OfflineNotice { Task { await load() } }

        let sections = Self.offlineSections(player: player)
        if sections.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(palette.accent)
                Text("Nothing saved yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                Text("Download songs while you're online and they'll be waiting here.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 56)
        } else {
            ForEach(sections) { section in
                row(section)
            }
        }
    }

    @MainActor
    private static func offlineSections(player: Player) -> [HomeSection] {
        func playable(_ tracks: [Track]) -> [Track] {
            var seen = Set<String>()
            return tracks.filter {
                guard !$0.videoId.isEmpty, seen.insert($0.videoId).inserted else { return false }
                return Downloads.shared.isDownloaded($0.videoId)
                    || AudioCache.shared.isCached($0.videoId)
            }
        }

        var out: [HomeSection] = []

        let downloaded = Downloads.shared.tracks
        if !downloaded.isEmpty {
            out.append(HomeSection(title: "Downloaded",
                                   items: downloaded.map(\.asHomeItem), isSongs: true))
        }

        let own = LocalMusic.shared.tracks
        if !own.isEmpty {
            out.append(HomeSection(title: "On this phone",
                                   items: own.map(\.asHomeItem), isSongs: true))
        }

        let recent = Array(playable(PlayHistory.recent).prefix(20))
        if !recent.isEmpty {
            out.append(HomeSection(title: "Recently played",
                                   items: recent.map(\.asHomeItem), isSongs: false))
        }

        let liked = Array(playable(player.favoriteTracks).prefix(20))
        if !liked.isEmpty {
            out.append(HomeSection(title: "Your favourites",
                                   items: liked.map(\.asHomeItem), isSongs: false))
        }

        let top = Array(playable(PlayHistory.mostPlayed(.all, limit: 80)).prefix(20))
        if !top.isEmpty {
            out.append(HomeSection(title: "Most played",
                                   items: top.map(\.asHomeItem), isSongs: false))
        }
        return out
    }

    private func selectChip(_ chip: HomeChip) {
        guard chip.title != selectedChip?.title else { return }
        selectedChip = chip
        Task {
            loading = true
            let f = await YouTube.home(params: chip.params)
            await MainActor.run {
                var kept = f
                kept.sections = f.sections.withoutShorts()
                feed = kept
                loading = false
            }
        }
    }

    // MARK: - Header (Lunara Logo · Lunara Wordmark · Settings)

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                LunaraMark(size: 38, accent: Lunara.green)
                Text("Lunara")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(palette.onSurface)
            }

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22))
                    .foregroundStyle(palette.onSurface)
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    // MARK: - Quick 2x2 Grid (Liked songs, For You, Speed Dial, History)

    private var quickGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                quickTile(
                    title: "Liked songs",
                    icon: "heart.fill",
                    iconColor: .white,
                    iconBg: Color(hex: 0x6435C9)
                ) {
                    path.append(HomeSection(title: "Liked songs",
                                            items: player.favoriteTracks.map(\.asHomeItem),
                                            isSongs: true))
                }

                quickTile(
                    title: "For You",
                    icon: "music.note",
                    iconColor: .black,
                    iconBg: Color(hex: 0x1DB954)
                ) {
                    if let first = feed.sections.first(where: { $0.isSongs })?.items, !first.isEmpty {
                        player.play(first.map(\.asTrack), startAt: 0)
                        player.openFullPlayer()
                    } else if !player.favoriteTracks.isEmpty {
                        player.play(player.favoriteTracks.shuffled(), startAt: 0)
                        player.openFullPlayer()
                    }
                }
            }

            HStack(spacing: 10) {
                quickTile(
                    title: "Speed Dial",
                    icon: "dot.radiowaves.left.and.right",
                    iconColor: .white,
                    iconBg: Color(hex: 0x262626)
                ) {
                    let songs = SpeedDial.shared.songs
                    if !songs.isEmpty {
                        player.play(songs, startAt: 0)
                        player.openFullPlayer()
                    }
                }

                quickTile(
                    title: "History",
                    icon: "clock.arrow.circlepath",
                    iconColor: .white,
                    iconBg: Color(hex: 0x1E3A8A)
                ) {
                    path.append(HomeSection(title: "History",
                                            items: PlayHistory.recent.map(\.asHomeItem),
                                            isSongs: true))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func quickTile(title: String, icon: String, iconColor: Color, iconBg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    iconBg
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(iconColor)
                }
                .frame(width: 56, height: 56)

                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color(hex: 0x141414))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mood pills row (Energise, Feel good, Relax, Commute)

    private var moodPillsRow: some View {
        let pills = ["Energise", "Feel good", "Relax", "Commute"]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pills, id: \.self) { pill in
                    let isSelected = selectedMood == pill
                    Button {
                        selectedMood = (selectedMood == pill ? nil : pill)
                        if let chip = feed.chips.first(where: { $0.title.lowercased().contains(pill.lowercased()) }) {
                            selectChip(chip)
                        }
                    } label: {
                        Text(pill)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(isSelected ? .black : .white.opacity(0.9))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(isSelected ? Color(hex: 0x1DB954) : Color(hex: 0x151515))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Search pill (opens full search)

    private var searchPill: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(palette.onSurfaceVariant)
            Text("Search songs, albums, artists…")
                .font(.system(size: 15))
                .foregroundStyle(palette.onSurfaceVariant)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(palette.onSurface.opacity(0.10))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture { tab = .explore }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

struct SearchRoute: Hashable {}

// MARK: - Greeting card

struct GreetingCard: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var dial = SpeedDial.shared
    @ObservedObject private var net = Reachability.shared
    @ObservedObject var player: Player
    @State private var speedCover: String?
    @State private var forYouCover: String?
    @State private var supermix: [Track] = []

    private var greeting: (line1: String, line2: String) {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return ("Good", "Morning 🌅")
        case 12..<17: return ("Good", "Afternoon ☀️")
        case 17..<21: return ("Good", "Evening 🌆")
        default: return ("Good", "Night 🌙")
        }
    }

    private let photoWidth: CGFloat = 200

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(palette.heroGradient)
            .frame(height: 160)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let clear = max(geo.size.width - photoWidth - 20, 120)
                    VStack(alignment: .leading, spacing: 6) {
                        words(geo.size.width)
                        buttons(clear: clear).padding(.top, 8)
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 20)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .task { await loadSupermix() }
    }

    private func words(_ cardWidth: CGFloat) -> some View {
        let fadeFrom = max(cardWidth - photoWidth - 4, 100)
        return VStack(alignment: .leading, spacing: 6) {
            Text(greeting.line1)
                .font(.system(size: 24, weight: .bold))
            Text(greeting.line2)
                .font(.system(size: 24, weight: .bold))
            Text("Music Lover")
                .font(.system(size: 22, weight: .bold))
                .opacity(0.95)
                .padding(.top, 2)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
        .frame(width: cardWidth - 20, alignment: .leading)
        .mask(
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: min(fadeFrom / max(cardWidth - 20, 1), 0.95)),
                .init(color: .clear, location: min((fadeFrom + 40) / max(cardWidth - 20, 1), 1)),
            ], startPoint: .leading, endPoint: .trailing),
        )
    }

    private func buttons(clear: CGFloat) -> some View {
        let forYou = CardOrder.order(forYouPool, id: \.videoId, from: forYouCover)
        let speed = CardOrder.order(speedPool, id: \.videoId, from: speedCover)
        return HStack(spacing: 8) {
            if let cover = forYou.first {
                cardButton(cover, label: "For you") { play(forYou, cover: $forYouCover) }
            }
            if let cover = speed.first {
                cardButton(cover, label: nil) { play(speed, cover: $speedCover) }
            }
        }
        .frame(maxWidth: clear, alignment: .leading)
    }

    private func cardButton(_ track: Track, label: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                ZStack {
                    Color.white.opacity(0.12)
                    RemoteImage(url: track.artURL(size: 96), size: 32) { Color.clear }
                    if label != nil {
                        Circle().fill(.black.opacity(0.55))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white),
                            )
                    }
                }
                .frame(width: 32, height: 32)
                .clipped()

                if let label {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.leading, 8)
                        .padding(.trailing, 12)
                }
            }
            .frame(height: 32)
            .background(.white.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? "Play \(track.title)")
    }

    private var speedPool: [Track] {
        if !net.isOnline {
            let pinned = Set(dial.songs.map(\.videoId))
            let saved = savedTracks
            return saved.filter { pinned.contains($0.videoId) } + saved.filter { !pinned.contains($0.videoId) }
        }
        let pinned = dial.songs.filter { !LocalMusic.isLocal($0.videoId) }
        if !pinned.isEmpty { return pinned }
        return PlayHistory.mostPlayed(.all, limit: 40)
            .filter { !LocalMusic.isLocal($0.videoId) }
            .withoutBlockedArtists()
    }

    private var forYouPool: [Track] {
        if !net.isOnline { return savedTracks }
        let mix = supermix.filter { !LocalMusic.isLocal($0.videoId) }.withoutBlockedArtists()
        if !mix.isEmpty { return mix }
        return Array(PlayHistory.recent.prefix(40))
            .filter { !LocalMusic.isLocal($0.videoId) }
            .withoutBlockedArtists()
    }

    private var savedTracks: [Track] {
        var seen = Set<String>()
        let kept = (PlayHistory.recent + PlayHistory.mostPlayed(.all, limit: 200) + player.favoriteTracks)
            .filter { Downloads.shared.isDownloaded($0.videoId) || AudioCache.shared.isCached($0.videoId) }
        return (Downloads.shared.tracks + LocalMusic.shared.tracks + kept)
            .filter { !$0.videoId.isEmpty && seen.insert($0.videoId).inserted }
            .withoutBlockedArtists()
    }

    private func play(_ order: [Track], cover: Binding<String?>) {
        guard !order.isEmpty else { return }
        let queue = net.isOnline ? order : [order[0]] + order.dropFirst().shuffled()
        player.play(queue, startAt: 0)
        cover.wrappedValue = CardOrder.next(after: order, id: \.videoId)
    }

    private func loadSupermix() async {
        guard supermix.isEmpty else { return }
        let mix = await YouTube.mix(playlistId: YouTube.supermixPlaylistId)
        guard !mix.isEmpty else { return }
        await MainActor.run { supermix = mix }
    }
}

// MARK: - Rail

struct HomeRail: View {
    @Environment(\.palette) private var palette
    let section: HomeSection
    let onTap: (HomeItem, [HomeItem]) -> Void
    var onSeeAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSectionHeader(title: section.title, onSeeAll: onSeeAll)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(section.items) { item in
                        MusicCard(item: item) { onTap(item, section.items) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct MusicCard: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var look = LookFeel.shared
    let item: HomeItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                RemoteImage(url: item.thumbnailURL, size: look.gridItemSize.cardWidth) {
                    palette.onSurface.opacity(0.06)
                }
                .frame(width: look.gridItemSize.cardWidth, height: look.gridItemSize.cardWidth)
                .clipShape(RoundedRectangle(cornerRadius: item.isCircular ? 70 : 12))
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)

                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(width: look.gridItemSize.cardWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct OfflineNotice: View {
    @Environment(\.palette) private var palette
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're offline")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                Text("Showing music saved on this device")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            Button(action: retry) {
                Text("Retry")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(palette.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}
