import SwiftUI

extension View {
    func opensArtist(_ player: Player) -> some View {
        modifier(OpensArtist(player: player))
    }
}

private struct OpensArtist: ViewModifier {
    @ObservedObject var player: Player

    @State private var artist: ArtistRoute?
    @State private var looking = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { open() }
            .fullScreenCover(item: $artist) { ArtistView(browseId: $0.browseId, player: player) }
    }

    private func open() {
        guard let track = player.current, !track.artist.isEmpty, !looking else { return }
        if let id = track.artistId, !id.isEmpty {
            artist = ArtistRoute(browseId: id)
            return
        }
        looking = true
        Task {
            let found = await YouTube.resolveArtistId(name: track.artist)
            await MainActor.run {
                looking = false
                artist = found.map(ArtistRoute.init)
            }
        }
    }
}
