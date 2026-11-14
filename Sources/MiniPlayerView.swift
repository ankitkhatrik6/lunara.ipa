import SwiftUI

struct MiniPlayerView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var look = LookFeel.shared
    var onOpenPlayer: (() -> Void)?
    @ObservedObject private var clock: PlaybackClock
    @State private var artist: ArtistRoute?
    @State private var dragDown: CGFloat = 0
    @State private var showAddToPlaylist = false

    init(player: Player, onOpenPlayer: (() -> Void)? = nil) {
        self.player = player
        self.onOpenPlayer = onOpenPlayer
        _clock = ObservedObject(wrappedValue: player.clock)
    }

    var body: some View {
        if let track = player.current {
            HStack(spacing: 0) {
                if look.miniPlayerDesign == .flat {
                    RemoteImage(url: track.artURL(size: 144), size: 48) { ArtPlaceholder() }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    playControl(track)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ink).lineLimit(1)
                    HStack(spacing: 5) {
                        if player.liveBroadcasts.contains(track.videoId) {
                            LiveBadge()
                        } else if track.isExplicit {
                            Text("E")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 14, height: 14)
                                .background(ink.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                        Text(track.artist)
                            .font(.system(size: 12.5))
                            .foregroundStyle(ink.opacity(0.7)).lineLimit(1)
                    }
                }
                .padding(.leading, 12)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    switch look.miniPlayerDesign {
                    case .flat:
                        plainButton(player.isPlaying ? "pause.fill" : "play.fill") {
                            player.toggle()
                        }
                        plainButton("forward.end.fill") { player.next() }
                    case .rounded:
                        plainButton("backward.end.fill", size: 18) { player.prev() }
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: 40, height: 40)
                                .background(Lunara.green)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        plainButton("forward.end.fill", size: 18) { player.next() }
                    default:
                        circleButton("person.crop.circle.badge.checkmark",
                                     tint: Lunara.green) { openArtist(track) }
                        circleButton("plus") { showAddToPlaylist = true }
                        circleButton(player.isCurrentFavorite ? "heart.fill" : "heart",
                                     tint: player.isCurrentFavorite ? Lunara.green : ink) {
                            player.toggleFavorite()
                        }
                    }
                }
            }
            .padding(8)
            .frame(height: 64)
            .background(background)
            .clipShape(shape)
            .overlay(
                shape.stroke(ink.opacity(0.18), lineWidth: look.miniPlayerDesign == .flat ? 0 : 1),
            )
            .overlay(alignment: .bottom) {
                if look.miniPlayerDesign == .flat {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(ink.opacity(0.2))
                            Rectangle().fill(palette.accent)
                                .frame(width: g.size.width * max(player.progress, 0.002))
                        }
                    }
                    .frame(height: 2)
                }
            }
            .shadow(color: look.miniPlayerDesign == .floating ? .black.opacity(0.35) : .clear,
                    radius: 10, y: 4)
            .padding(.horizontal, look.miniPlayerDesign == .flat ? 0 : 12)
            .contentShape(Rectangle())
            .onTapGesture { openPlayer() }
            .offset(y: dragDown)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { g in
                        guard abs(g.translation.height) > abs(g.translation.width) else { return }
                        dragDown = max(0, g.translation.height)
                    }
                    .onEnded { g in
                        let vertical = abs(g.translation.height) > abs(g.translation.width)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragDown = 0 }
                        if vertical {
                            if g.translation.height < -40 {
                                openPlayer()
                            } else if g.translation.height > 60 {
                                player.dismissPlayback()
                            }
                        } else if g.translation.width < -50 {
                            player.next()
                        } else if g.translation.width > 50 {
                            player.prev()
                        }
                    },
            )
            .fullScreenCover(item: $artist) { ArtistView(browseId: $0.browseId, player: player) }
            .sheet(isPresented: $showAddToPlaylist) {
                AddToPlaylistSheet(track: track)
            }
        }
    }

    private var ink: Color {
        guard look.miniPlayerDesign.usesArtBackground else { return palette.onSurface }
        switch look.miniPlayerBackground {
        case .followTheme, .transparent: return palette.onSurface
        default: return .white
        }
    }

    private var shape: AnyShape {
        switch look.miniPlayerDesign {
        case .flat:
            AnyShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        case .modern, .rounded:
            AnyShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        case .floating:
            AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func plainButton(_ icon: String, size: CGFloat = 20,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(ink)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.label(for: icon))
    }

    static func label(for icon: String) -> String {
        switch icon {
        case "play.fill": return "Play"
        case "pause.fill": return "Pause"
        case "forward.end.fill", "forward.fill": return "Next song"
        case "backward.end.fill", "backward.fill": return "Previous song"
        case "heart", "heart.fill": return "Favourite"
        case "text.badge.plus": return "Add to queue"
        case "person": return "View artist"
        case "plus": return "Add to playlist"
        default: return ""
        }
    }

    @ViewBuilder private var background: some View {
        if !look.miniPlayerDesign.usesArtBackground {
            palette.surface
        } else {
            switch look.miniPlayerBackground {
            case .followTheme: palette.surface
            case .transparent: Color.clear
            case .pureBlack: Color.black
            case .blur:
                ZStack {
                    RemoteImage(url: player.current?.artURL(size: 240), size: 120) {
                        player.artColor
                    }
                    .blur(radius: 22)
                    Color.black.opacity(0.30)
                }
            case .gradient:
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [Color(hex: 0x282828).opacity(0.85), Color(hex: 0x161616).opacity(0.92)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
        }
    }

    private func openPlayer() {
        if let onOpenPlayer {
            onOpenPlayer()
        } else {
            player.openFullPlayer()
        }
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

    private func playControl(_ track: Track) -> some View {
        ZStack {
            Circle().stroke(ink.opacity(0.18), lineWidth: 2.8)
            Circle()
                .trim(from: 0, to: max(player.progress, 0.0001))
                .stroke(Lunara.green, style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            RemoteImage(url: track.artURL(size: 240), size: 40) { ArtPlaceholder() }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay {
                    if !player.isPlaying {
                        ZStack {
                            Circle().fill(.black.opacity(0.4))
                            Image(systemName: "play.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                        }
                    }
                }
        }
        .frame(width: 48, height: 48)
        .contentShape(Circle())
        .onTapGesture { player.toggle() }
    }

    private func circleButton(_ icon: String, tint: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        let colour = tint ?? ink
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colour)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())
                .overlay(Circle().stroke(tint == Lunara.green ? Lunara.green.opacity(0.5) : ink.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.label(for: icon))
    }
}
