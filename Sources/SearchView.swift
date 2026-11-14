import SwiftUI

struct SearchView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    var pushed = false
    @ObservedObject private var history = SearchHistory.shared
    @ObservedObject private var browseArt = BrowseArt.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Track] = []
    @State private var cards: [HomeItem] = []
    @State private var scope: YouTube.SearchScope = .everything
    @State private var cardRoute: CardRoute?
    @State private var artistRoute: ArtistRoute?
    private var pastedLink: YouTubeLink? { YouTubeLink.parse(query) }
    @State private var suggestions: [String] = []
    @State private var suggestedSongs: [Track] = []
    @State private var moods: [MoodItem] = []
    @ObservedObject private var taste = GenreTaste.shared
    @State private var showAllGenres = false
    @State private var showContentRegion = false
    @State private var searching = false
    @State private var didSearch = false
    @State private var suggestTask: Task<Void, Never>?
    @State private var suppressSuggest = false

    @FocusState private var fieldFocused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let link = pastedLink {
                        linkRow(link)
                    }
                    if didSearch, !trimmed.isEmpty, pastedLink == nil {
                        scopePicker
                    }
                    if searching {
                        SkeletonTrackList(rows: 8).padding(.top, 8)
                    } else if scope == .everything, !results.isEmpty || !cards.isEmpty {
                        mixedResults
                    } else if scope.isPlayable, !results.isEmpty {
                        resultRows
                    } else if !scope.isPlayable, !cards.isEmpty {
                        cardRows
                    } else if didSearch, !trimmed.isEmpty {
                        Text("No results")
                            .font(.lunara(14))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if !trimmed.isEmpty {
                        suggestionList
                    } else {
                        idleContent
                    }
                }
                .playerBottomPadding()
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(palette.scaffold.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: MoodItem.self) { MoodDetailView(mood: $0, player: player) }
        .navigationDestination(for: HomeItem.self) { PlaylistView(item: $0, player: player) }
        .navigationDestination(item: $cardRoute) { PlaylistView(item: $0.item, player: player) }
        .navigationDestination(item: $artistRoute) {
            ArtistView(browseId: $0.browseId, player: player)
        }
        .sheet(isPresented: $showContentRegion) {
            NavigationStack { ContentSettingsView() }
                .environment(\.palette, palette)
        }
        .task {
            if moods.isEmpty { moods = await YouTube.moods() }
            browseArt.warm(for: moods)
            await taste.refresh(moods)
        }
    }

    // MARK: Field

    private var searchField: some View {
        HStack(spacing: 12) {
            if pushed || !query.isEmpty || didSearch || fieldFocused {
                Button {
                    if pushed && query.isEmpty && !didSearch {
                        dismiss()
                    } else {
                        fieldFocused = false
                        clearSearch()
                    }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.onSurface)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            } else {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.onSurface.opacity(0.65))
                    .frame(width: 28, height: 28)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                    .foregroundStyle(palette.onSurfaceVariant)

                TextField("Search song, title, artist...", text: $query)
                    .font(.lunara(15.5))
                    .foregroundStyle(palette.onSurface)
                    .tint(Lunara.green)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($fieldFocused)
                    .onSubmit { run(trimmed) }
                    .onChange(of: query) {
                        if trimmed.isEmpty, didSearch { clearSearch() }
                        if suppressSuggest { suppressSuggest = false } else { suggest() }
                    }

                if !query.isEmpty {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .accessibilityLabel("Clear search")
                            .font(.system(size: 17))
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                }

                Button { showContentRegion = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: 0x133820))
                            .frame(width: 32, height: 32)
                        Image(systemName: "globe")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Lunara.green)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Content language and region")
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Color(hex: 0x181818))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    // MARK: Idle — recent searches, then Browse

    @ViewBuilder private var idleContent: some View {
        if !history.queries.isEmpty {
            HStack {
                Text("Recent Searches")
                    .font(.lunara(17, .bold))
                    .foregroundStyle(palette.onSurface)
                Spacer()
                Button("Clear") { history.clear() }
                    .font(.lunara(13.5, .semibold))
                    .foregroundStyle(Lunara.green)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            RecentSearchRows(queries: Array(history.queries.prefix(20))) { entry in
                run(entry)
            } onDelete: { entry in
                history.remove(entry)
            }
            .padding(.bottom, 22)
        }

        if !moods.isEmpty {
            let tiles = taste.order(moods)
            let moodTiles = tiles.filter { !$0.isGenre }
            let genreTiles = tiles.filter(\.isGenre)
            let shown = showAllGenres ? genreTiles.count : max(6, min(genreTiles.count, taste.count(of: genreTiles) + 2))
            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

            Text("Browse")
                .font(.lunara(20, .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(moodTiles) { mood in
                    browseTile(mood)
                }
            }
            .padding(.horizontal, 16)

            if !genreTiles.isEmpty {
                Text("Genres")
                    .font(.lunara(18, .bold))
                    .foregroundStyle(palette.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.top, 22)
                    .padding(.bottom, 10)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(genreTiles.prefix(shown)) { genre in
                        browseTile(genre)
                    }
                }
                .padding(.horizontal, 16)

                if genreTiles.count > 6 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showAllGenres.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showAllGenres ? "Fewer genres" : "All genres")
                            Image(systemName: showAllGenres ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .font(.lunara(14, .semibold))
                        .foregroundStyle(Lunara.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if history.queries.isEmpty {
            Text("Search for a song, artist or album")
                .font(.lunara(14))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        }
    }

    private func browseTile(_ mood: MoodItem) -> some View {
        let seed = Color(hex: mood.colorARGB & 0xFFFFFF)
        let covers = browseArt.art[BrowseArt.key(mood)] ?? []

        return NavigationLink(value: mood) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [seed.mixed(with: .white, 0.14), seed],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                    if let cover = covers.first {
                        RemoteImage(url: URL(string: cover), size: 70) {
                            Color.black.opacity(0.2)
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 6, x: -2, y: 3)
                        .rotationEffect(.degrees(20))
                        .offset(x: 12, y: 12)
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.18))
                            .frame(width: 64, height: 64)
                            .rotationEffect(.degrees(20))
                            .offset(x: 12, y: 12)
                    }
                }

                Text(mood.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 118, alignment: .leading)
                    .padding(14)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { taste.noteOpened(mood) })
    }

    // MARK: Typing — songs first, then queries

    @ViewBuilder private var suggestionList: some View {
        let matches = history.matching(trimmed)

        ForEach(matches, id: \.self) { entry in
            suggestionRow(entry, icon: "clock.arrow.circlepath") { run(entry) }
        }

        ForEach(suggestedSongs.prefix(6)) { song in
            SongRow(track: song, player: player) {
                history.add(trimmed)
                player.playWithRadio(song)
                player.openFullPlayer()
            }
            .padding(.leading, 16)
            .padding(.vertical, 6)
            .buttonStyle(.plain)
        }

        if !suggestedSongs.isEmpty, !suggestions.isEmpty {
            Divider().overlay(palette.separator)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }

        ForEach(suggestions.filter { s in !matches.contains(s) }, id: \.self) { suggestion in
            suggestionRow(suggestion, icon: "magnifyingglass") { run(suggestion) }
        }

        if suggestedSongs.isEmpty, suggestions.isEmpty, didSearch {
            Text("No results")
                .font(.lunara(14))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        }
    }

    private func suggestionRow(_ text: String, icon: String,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.lunara(17))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(width: 24)
            Text(text)
                .font(.lunara(15))
                .foregroundStyle(palette.onSurface)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                query = text
                suggest()
            } label: {
                Image(systemName: "arrow.up.left")
                    .font(.lunara(14))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    @ViewBuilder
    private var mixedResults: some View {
        if !results.isEmpty {
            resultRows
        }
        if !cards.isEmpty {
            if !results.isEmpty {
                Text("Albums, artists and playlists")
                    .font(.lunara(12, .semibold))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
            }
            cardRows
        }
    }

    private var resultRows: some View {
        ForEach(Array(results.enumerated()), id: \.element.id) { _, track in
            SongRow(track: track, player: player) {
                player.playWithRadio(track)
                player.openFullPlayer()
            }
            .padding(.leading, 16)
            .padding(.vertical, 6)
        }
    }

    // MARK: Actions

    private func clearSearch() {
        query = ""
        results = []
        cards = []
        suggestions = []
        suggestedSongs = []
        didSearch = false
    }

    private func suggest() {
        suggestTask?.cancel()
        results = []
        let q = trimmed
        guard !q.isEmpty else {
            suggestions = []
            suggestedSongs = []
            didSearch = false
            return
        }
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            let found = await YouTube.searchSuggestions(q)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                suggestions = found.queries
                suggestedSongs = found.songs
                didSearch = true
            }
        }
    }

    private func run(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        suggestTask?.cancel()
        suppressSuggest = true
        query = q
        history.add(q)
        fieldFocused = false
        searching = true
        didSearch = true
        scope = .everything
        cards = []
        Task {
            let found = await YouTube.search(q)
            await MainActor.run {
                results = found.withoutBlockedArtists()
                searching = false
            }
        }
    }
}

// MARK: - Shared links

extension SearchView {
    @ViewBuilder func linkRow(_ link: YouTubeLink) -> some View {
        Button {
            open(link)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.lunara(18, .semibold))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 44, height: 44)
                    .background(palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.browseId == nil ? "Open this song" : "Open this playlist")
                        .font(.lunara(15, .semibold))
                        .foregroundStyle(palette.onSurface)
                    Text("From the link you pasted")
                        .font(.lunara(12))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.lunara(12, .semibold))
                    .foregroundStyle(palette.onSurfaceVariant.opacity(0.6))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func open(_ link: YouTubeLink) {
        fieldFocused = false
        switch link {
        case .song(let videoId):
            searching = true
            Task {
                let found = await YouTube.related(videoId: videoId)
                    .flatMap(\.items)
                    .compactMap { $0.videoId == videoId ? $0.asTrack : nil }
                    .first
                let track = found ?? Track(videoId: videoId, title: "Shared song",
                                           artist: "", thumbnail: "", duration: 0)
                await MainActor.run {
                    searching = false
                    query = ""
                    player.play([track], startAt: 0)
                    player.openFullPlayer()
                }
            }
        case .playlist:
            guard let browseId = link.browseId else { return }
            query = ""
            cardRoute = CardRoute(item: HomeItem(title: "Shared playlist", subtitle: "",
                                                 thumbnail: "", videoId: nil,
                                                 browseId: browseId, isCircular: false))
        }
    }
}

// MARK: - Scope

extension SearchView {
    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(YouTube.SearchScope.allCases) { option in
                    let active = option == scope
                    Text(option.title)
                        .font(.system(size: 13, weight: active ? .bold : .medium))
                        .foregroundStyle(active ? palette.onAccent : palette.onSurfaceVariant)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(active ? AnyShapeStyle(palette.accent)
                                           : AnyShapeStyle(palette.surfaceHigh))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                        .onTapGesture {
                            guard option != scope else { return }
                            scope = option
                            runScopeSearch()
                        }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
    }

    private var cardRows: some View {
        LazyVStack(spacing: 0) {
            ForEach(cards) { card in
                Button {
                    if scope == .artists, let id = card.browseId {
                        artistRoute = ArtistRoute(browseId: id)
                    } else {
                        cardRoute = CardRoute(item: card)
                    }
                } label: {
                    HStack(spacing: 12) {
                        RemoteImage(url: card.thumbnailURL, size: 52) {
                            palette.onSurface.opacity(0.10)
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(card.isCircular
                                   ? AnyShape(Circle())
                                   : AnyShape(RoundedRectangle(cornerRadius: 8)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.title)
                                .font(.subheadline).foregroundStyle(palette.onSurface)
                                .lineLimit(1)
                            if !card.subtitle.isEmpty {
                                Text(card.subtitle)
                                    .font(.caption).foregroundStyle(palette.onSurfaceVariant)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.lunara(12, .semibold))
                            .foregroundStyle(palette.onSurfaceVariant.opacity(0.6))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func runScopeSearch() {
        let q = trimmed
        guard !q.isEmpty else { return }
        searching = true
        Task {
            if scope.isPlayable {
                let found = await YouTube.search(q, scope: scope)
                await MainActor.run { results = found.withoutBlockedArtists(); cards = []; searching = false }
            } else if scope == .everything {
                async let songs = YouTube.search(q, scope: .everything)
                async let pages = YouTube.searchCards(q, scope: .everything)
                let (found, browsable) = await (songs, pages)
                await MainActor.run { results = found; cards = browsable; searching = false }
            } else {
                let found = await YouTube.searchCards(q, scope: scope)
                await MainActor.run { cards = found; results = []; searching = false }
            }
        }
    }
}

struct RecentSearchRows: View {
    @Environment(\.palette) private var palette
    let queries: [String]
    let onTap: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { chip(for: $0) }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: rows.count > 1 ? 78 : 40)
    }

    private var rows: [[String]] {
        var top: [String] = []
        var bottom: [String] = []
        var topWidth = 0
        var bottomWidth = 0
        for q in queries {
            let w = q.count + 6
            if topWidth <= bottomWidth {
                top.append(q); topWidth += w
            } else {
                bottom.append(q); bottomWidth += w
            }
        }
        return bottom.isEmpty ? [top] : [top, bottom]
    }

    private func chip(for entry: String) -> some View {
        HStack(spacing: 8) {
            Text(entry)
                .font(.lunara(13.5, .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
            Button { onDelete(entry) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(Color(hex: 0x09160E))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Lunara.green.opacity(0.6), lineWidth: 1)
        )
        .contentShape(Capsule())
        .onTapGesture { onTap(entry) }
    }
}

struct FlowChips: View {
    @Environment(\.palette) private var palette
    let items: [String]
    let onTap: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows().enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { chip(for: $0) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chip(for entry: String) -> some View {
        HStack(spacing: 6) {
            Text(entry)
                .font(.lunara(13, .medium))
                .foregroundStyle(palette.onSurface)
                .lineLimit(1)
            Button { onDelete(entry) } label: {
                Image(systemName: "xmark")
                    .font(.lunara(10, .bold))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(Color(hex: 0x09160E))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Lunara.green.opacity(0.6), lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture { onTap(entry) }
    }

    private func rows() -> [[String]] {
        var out: [[String]] = []
        var current: [String] = []
        var width = 0
        for entry in items {
            let cost = entry.count + 5
            if width + cost > 38, !current.isEmpty {
                out.append(current)
                current = []
                width = 0
            }
            current.append(entry)
            width += cost
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

struct TrackRow: View {
    @Environment(\.palette) private var palette
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: track.thumbnailURL, size: 52) {
                palette.onSurface.opacity(0.10)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
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
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(Lunara.green)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            DownloadRing(videoId: track.videoId)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct DownloadRing: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var downloads = Downloads.shared
    let videoId: String

    var body: some View {
        if downloads.state(videoId) == .downloading {
            let value = downloads.progress[videoId] ?? 0
            ZStack {
                Circle()
                    .stroke(palette.onSurfaceVariant.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(value, 0.03))
                    .stroke(palette.accent,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.25), value: value)
            }
            .frame(width: 18, height: 18)
            .padding(.leading, 6)
            .transition(.opacity)
        }
    }
}

struct SongRow: View {
    let track: Track
    @ObservedObject var player: Player
    var trailingPadding: CGFloat = 8
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) { TrackRow(track: track) }
                .buttonStyle(.plain)
            SongRowMenu(track: track, player: player)
                .padding(.trailing, trailingPadding)
        }
    }
}

struct ArtistRoute: Identifiable, Hashable {
    let browseId: String
    var id: String { browseId }
}

struct CardRoute: Hashable, Identifiable {
    let item: HomeItem
    var id: HomeItem.ID { item.id }
}
