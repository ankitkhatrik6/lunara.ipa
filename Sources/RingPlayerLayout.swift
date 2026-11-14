import SwiftUI
import UIKit

struct RingPlayerLayout: View {
    @ObservedObject var player: Player
    var onOpenTheme: () -> Void
    var onOpenQueue: () -> Void
    var onOpenSleep: () -> Void
    var onShowLyrics: () -> Void
    var onMore: () -> Void
    @Binding var scrub: Double?

    var body: some View {
        VStack(spacing: 0) {
            topBar

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.92
                SeekableAlbumRing(
                    artURL: player.current?.artURL(size: 1080),
                    progress: scrub ?? player.progress,
                    ringColor: player.artColor,
                    trackColor: .white.opacity(0.16),
                    thumbColor: player.artColor,
                    topLabel: AnyView(times),
                ) { f in
                    scrub = nil
                    player.seek(to: f)
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 10)
            titleRow
            Spacer().frame(height: 14)
            transport
            Spacer(minLength: 10)
            RingLyricsLines(player: player, onTap: onShowLyrics)
            Spacer().frame(height: 8)
            bottomRow
            Spacer().frame(height: 10)
        }
        .foregroundStyle(.white)
    }

    // MARK: Top bar — the heading only

    private var topBar: some View {
        VStack(spacing: 2) {
            Text("Now Playing")
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
            if let from = player.current?.artist, !from.isEmpty {
                Text(from)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: The times, in the gap cut into the top of the ring

    private var times: some View {
        SwiftUI.Group {
            if player.isCurrentLive {
                LiveBadge()
            } else {
                HStack(spacing: 6) {
                    Text(timeString((scrub ?? player.progress) * player.duration))
                        .foregroundStyle(player.artColor)
                    Text("—").foregroundStyle(.white.opacity(0.5))
                    Text(player.duration > 0 ? timeString(player.duration) : "--:--")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .font(.system(size: 13, weight: .semibold))
            }
        }
        .fixedSize()
    }

    // MARK: Title on the left, its keys on the right

    private var titleRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.title ?? "")
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                Text(player.current?.artist ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .opensArtist(player)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ringIcon(player.isCurrentFavorite ? "heart.fill" : "heart", size: 22, box: 40,
                     tint: player.isCurrentFavorite ? .red : .white) { player.toggleFavorite() }
            ringIcon("paintpalette", size: 22, box: 40, action: onOpenTheme)
            ringIcon("ellipsis", size: 22, box: 40, action: onMore)
        }
        .padding(.horizontal, 32)
    }

    // MARK: Transport — shuffle · prev · PLAY · next · repeat

    private var transport: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ringIcon("shuffle", size: 24, box: 42,
                     tint: player.isShuffled ? Lunara.green : .white) { player.toggleShuffle() }
            Spacer(minLength: 0)
            ringIcon("backward.end.fill", size: 34, box: 52) { player.prev() }
            Spacer(minLength: 0)
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(player.artColor)
                    .clipShape(RoundedRectangle(cornerRadius: player.isPlaying ? 22 : 33))
                    .animation(.easeOut(duration: 0.15), value: player.isPlaying)
            }
            Spacer(minLength: 0)
            ringIcon("forward.end.fill", size: 34, box: 52) { player.next() }
            Spacer(minLength: 0)
            ringIcon(player.repeatMode == .one ? "repeat.1" : "repeat", size: 24, box: 42,
                     tint: player.repeatMode != .off ? Lunara.green : .white) { player.cycleRepeat() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
    }

    // MARK: The four keys every design ends with

    private var bottomRow: some View {
        HStack(spacing: 0) {
            key("list.bullet", "Queue", action: onOpenQueue)
            VStack(spacing: 4) {
                RoutePicker(tint: UIColor.white.withAlphaComponent(0.85),
                            activeTint: UIColor(Lunara.green))
                    .frame(width: 26, height: 26)
                Text("AirPlay").font(.system(size: 11)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("AirPlay and Bluetooth")
            key(player.sleepActive ? "moon.zzz.fill" : "moon.zzz", sleepLabel,
                active: player.sleepActive, action: onOpenSleep)
            key("quote.bubble", "Lyrics", action: onShowLyrics)
        }
        .padding(.horizontal, 20)
    }

    private var sleepLabel: String {
        if player.sleepAtEndOfSong { return "End of song" }
        if let r = player.sleepRemaining { return timeString(r) }
        return "Sleep timer"
    }

    private func key(_ icon: String, _ label: String,
                     active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 11)).lineLimit(1)
            }
            .foregroundStyle(active ? Lunara.green : .white.opacity(0.85))
            .frame(maxWidth: .infinity)
        }
    }

    private func ringIcon(_ name: String, size: CGFloat, box: CGFloat,
                          tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size))
                .foregroundStyle(tint)
                .frame(width: box, height: box)
        }
    }
}

struct SeekableAlbumRing: View {
    let artURL: URL?
    let progress: Double
    let ringColor: Color
    let trackColor: Color
    let thumbColor: Color
    var stroke: CGFloat = 7
    var artPadding: CGFloat = 18
    var topLabel: AnyView?
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?
    @State private var labelWidth: CGFloat = 0

    private func gapFraction(_ side: CGFloat) -> Double {
        guard topLabel != nil, labelWidth > 0, side > 0 else { return 0 }
        let circumference = Double.pi * Double(side - stroke)
        guard circumference > 0 else { return 0 }
        return min(Double(labelWidth + 12 + stroke) / circumference, 0.33)
    }

    var body: some View {
        let shown = min(max(dragFraction ?? progress, 0), 1)

        ZStack {
            RemoteImage(url: artURL) { ArtPlaceholder() }
                .clipShape(Circle())
                .padding(artPadding + stroke)

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let d = min(w, h) - stroke
                let r = d / 2
                let center = CGPoint(x: w / 2, y: h / 2)

                let gap = gapFraction(min(w, h))
                let span = 1 - gap
                let start = gap / 2

                ZStack {
                    Circle()
                        .trim(from: start, to: 1 - start)
                        .stroke(trackColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(stroke / 2)
                    Circle()
                        .trim(from: start, to: start + max(shown * span, 0.0001))
                        .stroke(ringColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(stroke / 2)

                    let a = (-90.0 + 360.0 * (start + shown * span)) * .pi / 180.0
                    let knob = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
                    Circle().fill(.white)
                        .frame(width: stroke * 1.8, height: stroke * 1.8)
                        .position(knob)
                    Circle().fill(thumbColor)
                        .frame(width: stroke * 1.2, height: stroke * 1.2)
                        .position(knob)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            dragFraction = Self.seekFraction(g.location, w, h, gap)
                        }
                        .onEnded { g in
                            let f = Self.seekFraction(g.location, w, h, gap)
                            dragFraction = nil
                            onSeek(f)
                        },
                )
            }

            if let topLabel {
                topLabel
                    .background(
                        GeometryReader { g in
                            Color.clear.onAppear { labelWidth = g.size.width }
                                .onChange(of: g.size.width) { labelWidth = g.size.width }
                        },
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .offset(y: -stroke / 2)
            }
        }
    }

    private static func seekFraction(_ p: CGPoint, _ w: CGFloat, _ h: CGFloat, _ gap: Double) -> Double {
        let angle = atan2(Double(p.y - h / 2), Double(p.x - w / 2)) * 180 / .pi
        let raw = ((angle + 90 + 360).truncatingRemainder(dividingBy: 360)) / 360
        let span = 1 - gap
        guard span > 0 else { return 0 }
        return min(max((raw - gap / 2) / span, 0), 1)
    }
}

struct RingLyricsLines: View {
    @ObservedObject var player: Player
    let onTap: () -> Void
    @ObservedObject private var clock: PlaybackClock

    init(player: Player, onTap: @escaping () -> Void) {
        self.player = player
        self.onTap = onTap
        _clock = ObservedObject(wrappedValue: player.clock)
    }

    @State private var lines: [LyricLine] = []
    @State private var loading = true

    private let areaHeight: CGFloat = 88

    var body: some View {
        Group {
            if loading {
                LyricsSkeleton()
                    .padding(.horizontal, 32)
                    .frame(height: areaHeight)
            } else if lines.isEmpty {
                Color.clear.frame(height: 0)
            } else {
                VStack(spacing: 4) {
                    let i = activeIndex
                    Text(i != nil && i! > 0 ? lines[i! - 1].text : " ")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                    Text(currentLine)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(player.artColor)
                        .lineLimit(2)
                    Text(i != nil && i! + 1 < lines.count ? lines[i! + 1].text : " ")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: areaHeight)
                .padding(.horizontal, 24)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { g in if g.translation.height < -20 { onTap() } },
                )
            }
        }
        .task(id: player.current?.videoId) { await load() }
    }

    private var currentLine: String {
        guard let i = activeIndex else { return "♪" }
        return lines[i].text.isEmpty ? "♪" : lines[i].text
    }

    private var knownDuration: Double {
        player.duration > 0 ? player.duration : (player.current?.duration ?? 0)
    }

    private var activeIndex: Int? {
        guard !lines.isEmpty else { return nil }
        let t = player.currentTime + 0.2
        var idx: Int?
        for (i, line) in lines.enumerated() {
            if line.time <= t { idx = i } else { break }
        }
        return idx
    }

    private func load() async {
        loading = true
        lines = []
        guard let track = player.current else { loading = false; return }
        let found = await LyricsCache.shared.warm(videoId: track.videoId, title: track.title,
                                                  artist: track.artist, duration: knownDuration)
        let floor = LocalMusic.isLocal(track.videoId)
            ? Lyrics.importedFloor(artist: track.artist) : 0
        await MainActor.run {
            lines = Lyrics.best(found, floor: floor)?.lines ?? []
            loading = false
        }
    }
}

struct LyricsSkeleton: View {
    @State private var bright = false

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array([0.55, 0.8, 0.5].enumerated()), id: \.offset) { i, frac in
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity((bright ? 0.6 : 0.25) * (i == 1 ? 1 : 0.7)))
                        .frame(width: g.size.width * frac, height: 11)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 11)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: true)) { bright = true }
        }
    }
}
