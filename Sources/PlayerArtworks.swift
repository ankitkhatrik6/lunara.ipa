import SwiftUI

struct ArtPlaceholder: View {
    @Environment(\.palette) private var palette

    var body: some View {
        palette.onSurface.opacity(0.06)
            .overlay { ArtLogoMark() }
    }
}

struct SquareArtwork: View {
    @ObservedObject var player: Player
    @ObservedObject private var look = LookFeel.shared
    let side: CGFloat

    var body: some View {
        Group {
            if look.hidePlayerThumbnail {
                ArtPlaceholder()
            } else {
                RemoteImage(url: player.current?.artURL(size: 1080),
                            fill: look.cropAlbumArt, crossfade: true) { ArtPlaceholder() }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .gesture(swipe, isEnabled: look.swipeThumbnail)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                if value.translation.width < -40 { _ = player.next() }
                else if value.translation.width > 40 { player.prev() }
            }
    }
}
