import SwiftUI

struct HistoryView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player

    @State private var query = ""
    @State private var searching = false

    private var sections: [(title: String, tracks: [Track])] {
        let raw = PlayHistory.grouped.map { ($0.bucket.title, $0.tracks) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return raw.map { (title: $0.0, tracks: $0.1) } }
        return raw.compactMap { title, tracks in
            let hits = tracks.filter {
                $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
            }
            return hits.isEmpty ? nil : (title: title, tracks: hits)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if sections.isEmpty {
                    Text("Nothing played yet — your history will appear here.")
                        .font(.lunara(14))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 32)
                        .padding(.top, 60)
                }

                ForEach(sections, id: \.title) { section in
                    Text(section.title)
                        .font(.lunara(18, .bold))
                        .foregroundStyle(palette.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                    ForEach(Array(section.tracks.enumerated()), id: \.element.id) { index, track in
                        SongRow(track: track, player: player) {
                            player.play(section.tracks, startAt: index)
                            player.openFullPlayer()
                        }
                        .padding(.leading, 16)
                        .padding(.vertical, 6)
                        .buttonStyle(.plain)
                    }
                }
            }
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle("History")
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
            if searching {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(palette.onSurfaceVariant)
                    TextField("Search history", text: $query)
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
    }
}
