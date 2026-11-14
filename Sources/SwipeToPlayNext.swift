import SwiftUI

struct PlayNextSwipe: ViewModifier {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    let track: Track

    @State private var offset: CGFloat = 0
    @State private var queued = false

    private let commit: CGFloat = 78

    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            if offset > 2 || queued {
                HStack(spacing: 8) {
                    Image(systemName: queued ? "checkmark" : "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 15, weight: .bold))
                    Text(queued ? "Playing next" : "Play next")
                        .font(.lunara(13, .semibold))
                }
                .foregroundStyle(offset >= commit || queued ? Lunara.green : palette.onSurfaceVariant)
                .padding(.leading, 20)
            }

            content
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 22)
                        .onChanged { g in
                            guard g.translation.width > 0,
                                  abs(g.translation.width) > abs(g.translation.height) * 1.5
                            else { return }
                            offset = min(g.translation.width, commit + 24)
                        }
                        .onEnded { _ in
                            let far = offset >= commit
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
                            guard far else { return }
                            player.playNext(track)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation { queued = true }
                            Task {
                                try? await Task.sleep(nanoseconds: 1_200_000_000)
                                withAnimation { queued = false }
                            }
                        },
                )
        }
    }
}

extension View {
    func swipeToPlayNext(_ track: Track, player: Player) -> some View {
        modifier(PlayNextSwipe(player: player, track: track))
    }
}
