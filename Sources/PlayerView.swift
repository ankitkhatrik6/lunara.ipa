import SwiftUI
import UIKit

struct PlayerView: View {
    @ObservedObject var player: Player
    @ObservedObject private var clock: PlaybackClock

    init(player: Player) {
        self.player = player
        _clock = ObservedObject(wrappedValue: player.clock)
    }

    @AppStorage("playerDesign") private var designRaw = PlayerDesign.classic.rawValue
    @Environment(\.palette) private var palette
    @State private var scrub: Double?
    @State private var showQueue = false
    @State private var showSleep = false
    @State private var showAddToPlaylist = false
    @State private var showShare = false
    @StateObject private var videoLoader = SongVideoLoader()
    @State private var showDesign = false
    @State private var showMenu = false
    @State private var showEqualizer = false
    @State private var showLyricsSettings = false
    @State private var showLyricsTiming = false
    @State private var lyricsOffset: Double = 0
    @State private var lyricsMode = false
    @State private var immersive = false
    @State private var askVideoOnMobile = false
    @State private var videoShowing = false
    @ObservedObject private var prefs = PlaybackPrefs.shared
    @ObservedObject private var net = Reachability.shared
    @ObservedObject private var downloads = Downloads.shared

    private var design: PlayerDesign { PlayerDesign(rawValue: designRaw) ?? .classic }

 // MARK: Sheet physics

    private var expandedBound: CGFloat { UIScreen.main.bounds.height }
    private var collapsedBound: CGFloat { 152 }

    private var sheetProgress: Double {
        let span = expandedBound - collapsedBound
        guard span > 0 else { return 1 }
        return min(max(1 - Double(sheetOffset / span), 0), 1)
    }

    private var settleSpring: Animation {
        .interpolatingSpring(mass: 1, stiffness: 1500, damping: 77.46)
    }

    @State private var arrived = false
    private let arriveDrift: CGFloat = 36
    private var fadeIn: Animation { .easeOut(duration: 0.28) }

    @State private var dragFrom: CGFloat?

    @State private var seekFlash: String?
    @State private var flashAt = Date()

    @State private var turningRecord = false

    private var sheetOffset: CGFloat { player.sheetDrag }

    var body: some View {
        ZStack {
            Color.black.opacity(sheetProgress)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ZStack {
                LinearGradient(
                    colors: [player.artColor, player.artColor.opacity(0.45), .black],
                    startPoint: .top, endPoint: .bottom,
                )
                .overlay(Color.black.opacity(0.2))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: player.artColor)

                if design == .fullArt, !lyricsMode {
                    fullArtBackground
                }

                if design == .video, !lyricsMode {
                    videoArtBackground
                }

                content
                    .padding(.bottom, 16)
                    .foregroundStyle(.white)
                    .opacity(min(max((sheetProgress - 0.15) * 4, 0), 1))
                    .animation(.easeInOut(duration: 0.25), value: lyricsMode)
                    .animation(.easeInOut(duration: 0.25), value: immersive)
            }
            .overlay {
                if let seekFlash {
                    Text(seekFlash)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.45), in: Capsule())
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.18), value: seekFlash)
            .offset(y: sheetOffset + (arrived ? 0 : arriveDrift))
        }
        .opacity(arrived ? 1 : 0)
        .gesture(sheetGesture)
        .statusBarHidden(lyricsMode && LyricsPrefs.shared.hideStatusBarFullscreen)
        .onAppear {
            player.sheetDrag = 0
            withAnimation(fadeIn) { arrived = true }
            UIApplication.shared.isIdleTimerDisabled = PlaybackPrefs.shared.keepScreenOn
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .fullScreenCover(isPresented: $showDesign) { PlayerDesignPicker(player: player) }
        .fullScreenCover(isPresented: $showQueue) {
            QueueView(player: player).environment(\.palette, palette)
        }
        .sheet(isPresented: $showEqualizer) {
            NavigationStack { EqualizerView(player: player) }
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showLyricsTiming) {
            LyricsTimingSheet(offset: $lyricsOffset) {
                LyricsOffsets.save(lyricsOffset, for: player.current?.videoId ?? "")
            }
            .environment(\.palette, palette)
        }
        .sheet(isPresented: $showLyricsSettings) {
            NavigationStack { LyricsSettingsView() }
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showSleep) {
            SleepTimerView(player: player).environment(\.palette, palette)
        }
        .sheet(isPresented: $showMenu) {
            PlayerMenuSheet(
                player: player,
                onQueue: { showQueue = true },
                onSleep: { showSleep = true },
                onLyrics: { lyricsMode = true },
                onLyricsSettings: { showLyricsSettings = true },
                onLyricsTiming: {
                    lyricsOffset = LyricsOffsets.load(for: player.current?.videoId ?? "")
                    showLyricsTiming = true
                },
                onEqualizer: { showEqualizer = true },
            )
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let track = player.current {
                AddToPlaylistSheet(track: track)
                    .environment(\.palette, palette)
            }
        }
        .sheet(isPresented: $showShare) {
            if let track = player.current {
                SharePlaylistSheet(
                    name: track.title,
                    songIds: [track.videoId],
                    kindLabel: "SONG",
                    artworkURL: track.artURL(size: 544),
                    customLink: "https://music.youtube.com/watch?v=\(track.videoId)"
                )
                .environment(\.palette, palette)
            }
        }
    }

    private var sheetGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                guard !turningRecord else { dragFrom = nil; return }
                if dragFrom == nil { dragFrom = player.sheetDrag }
                player.sheetDrag = max(0, (dragFrom ?? 0) + g.translation.height)
            }
            .onEnded { g in
                dragFrom = nil
                guard !turningRecord else { return }
                let vy = g.velocity.height
                let value = expandedBound - player.sheetDrag
                let midpoint = (expandedBound - collapsedBound) / 2

                if vy < -250 {
                    springBack()
                } else if vy > 250 {
                    close(velocity: vy)
                } else if value > midpoint {
                    springBack()
                } else {
                    close(velocity: vy)
                }
            }
    }

    private func jump(back: Bool) {
        let step = Double(PlaybackPrefs.shared.seekSeconds)
        guard player.duration > 0 else { return }
        player.seek(by: back ? -step : step)
        seekFlash = back ? "−\(Int(step))s" : "+\(Int(step))s"
        flashAt = Date()
        let mine = flashAt
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            if flashAt == mine { seekFlash = nil }
        }
    }

    private func springBack() {
        withAnimation(settleSpring) { player.sheetDrag = 0 }
    }

    private func close(velocity vy: CGFloat = 0) {
        let left = max(expandedBound - player.sheetDrag, 1)
        let carryOn = Animation.interpolatingSpring(
            mass: 1, stiffness: 180, damping: 26,
            initialVelocity: Double(max(vy, 0) / left),
        )
        withAnimation(carryOn) { player.sheetDrag = expandedBound }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { player.showFullPlayer = false }
        }
    }

    // MARK: Layout dispatch

    @ViewBuilder private var content: some View {
        if lyricsMode {
            standardLayout {
                LyricsPane(player: player, immersive: immersive)
                    .transition(.opacity)
            }
        } else {
            switch design {
            case .ring:
                RingPlayerLayout(
                    player: player,
                    onOpenTheme: { showDesign = true },
                    onOpenQueue: { showQueue = true },
                    onOpenSleep: { showSleep = true },
                    onShowLyrics: { lyricsMode = true },
                    onMore: { showMenu = true },
                    scrub: $scrub,
                )
            case .cassette:
                CassettePlayerLayout(
                    player: player,
                    clock: clock,
                    onLyrics: { lyricsMode = true },
                    onQueue: { showQueue = true },
                    onSleep: { showSleep = true },
                    onTheme: { showDesign = true },
                    onMore: { showMenu = true },
                )
            case .classic:
                standardLayout {
                    SquareArtwork(player: player, side: stageHeight)
                }
            case .record:
                standardLayout(tapToSeek: false) {
                    VinylTurntableView(
                        artURL: player.current?.artURL(size: 1080),
                        isPlaying: player.isPlaying,
                        progress: player.progress,
                        fallback: Lunara.gradient,
                        onSeek: { back in jump(back: back) },
                        onTurning: { hand in
                            if hand {
                                turningRecord = true
                                if player.sheetDrag != 0 { springBack() }
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    turningRecord = false
                                }
                            }
                        },
                    )
                    .frame(height: stageHeight)
                    .padding(.horizontal, 32)
                }
            case .fullArt, .video:
                standardLayout { Color.clear.frame(height: stageHeight) }
            }
        }
    }

    private var stageHeight: CGFloat { min(UIScreen.main.bounds.width - 96, 320) }

    @ViewBuilder private func standardLayout<Stage: View>(
        tapToSeek: Bool = true,
        @ViewBuilder stage: () -> Stage,
    ) -> some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 12)
            stage()
                .overlay {
                    if tapToSeek {
                        GeometryReader { geo in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { where_ in
                                    jump(back: where_.x < geo.size.width / 2)
                                }
                        }
                    }
                }
            Spacer(minLength: 18)
            titleAndProgress
            if !immersive {
                Spacer(minLength: 28)
                transport
                Spacer(minLength: 22)
                bottomRow
            } else {
                Spacer(minLength: 16)
            }
        }
        .padding(.top, 6)
    }

    // MARK: Full-art background (5-stop scrim, ported exactly)

    private static let videoStageShare: CGFloat = 0.70

    @ViewBuilder private var videoArtBackground: some View {
        GeometryReader { geo in
            let stage = geo.size.height * Self.videoStageShare
            ZStack(alignment: .top) {
                Color.black
                ZStack {
                    RemoteImage(url: player.current?.artURL(size: 1280)) {
                        Color.black
                    }
                    .frame(width: geo.size.width, height: stage)
                    .clipped()

                    if let v = videoLoader.video {
                        VideoArtView(video: v,
                                     position: player.currentTime,
                                     isPlaying: player.isPlaying,
                                     songLength: player.duration,
                                     onTrouble: { videoLoader.trouble($0) },
                                     onFirstFrame: { videoShowing = true })
                            .frame(width: geo.size.width, height: stage)
                            .clipped()
                            .opacity(videoShowing ? 1 : 0)
                    }
                }
                .frame(width: geo.size.width, height: stage)
                .clipped()
                .animation(.easeInOut(duration: 0.6), value: videoShowing)
                .onChange(of: player.current?.videoId) { videoShowing = false }
                .onChange(of: videoLoader.video) { if videoLoader.video == nil { videoShowing = false } }
                .overlay(
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.50),
                        .init(color: .black.opacity(0.85), location: 0.85),
                        .init(color: .black, location: 1.0),
                    ], startPoint: .top, endPoint: .bottom),
                )
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .ignoresSafeArea()
        .task(id: player.current?.videoId) { videoWanted = true; loadVideoIfComfortable() }
        .onChange(of: player.currentTime) { loadVideoIfComfortable() }
        .onChange(of: player.isPlaying) { loadVideoIfComfortable() }
        .onChange(of: prefs.videoOnMobile) { videoWanted = true; loadVideoIfComfortable() }
        .onChange(of: net.isUnmetered) { videoWanted = true; loadVideoIfComfortable() }
        .onAppear {
            videoWanted = true
            loadVideoIfComfortable()
            offerVideoOnMobile()
        }
        .alert("Videos on mobile data", isPresented: $askVideoOnMobile) {
            Button("Not now", role: .cancel) {}
            Button("Play videos") { prefs.videoOnMobile = true }
        } message: {
            Text("The Video player fetches a picture as well as the song, which costs far "
                 + "more data. On mobile data it shows the cover instead. You can change "
                 + "this any time in Settings › Player and audio.")
        }
    }

    private func offerVideoOnMobile() {
        guard design == .video, !net.isUnmetered, !prefs.videoOnMobile else { return }
        let key = "videoOnMobileAsked"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        askVideoOnMobile = true
    }

    @State private var videoWanted = false
    @State private var videoWaitingSince: Date?

    private func loadVideoIfComfortable() {
        guard videoWanted, design == .video else { return }
        let waited = videoWaitingSince.map { Date().timeIntervalSince($0) } ?? 0
        guard player.songComfortable || waited >= 3 else {
            if videoWaitingSince == nil {
                videoWaitingSince = Date()
                VideoArtLog.note("gate: waiting for the song — loading=\(player.isLoading) "
                    + "playing=\(player.isPlaying) ahead=\(Int(player.bufferedAhead))s")
            }
            return
        }
        VideoArtLog.note("gate: open after \(Int(waited))s — loading=\(player.isLoading) "
            + "playing=\(player.isPlaying) ahead=\(Int(player.bufferedAhead))s")
        videoWanted = false
        videoWaitingSince = nil
        loadVideo()
    }

    private func loadVideo() {
        let allowed = Reachability.shared.isUnmetered || PlaybackPrefs.shared.videoOnMobile
        let height = Reachability.shared.isUnmetered ? 480 : 360
        videoLoader.load(for: player.current, allowed: allowed, maxHeight: height)
        videoLoader.prepareNext(player.upNext, allowed: allowed, maxHeight: height)
    }

    private var fullArtBackground: some View {
        GeometryReader { geo in
            RemoteImage(url: player.current?.artURL(size: 1280)) { Color.black }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.40), location: 0.0),
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.55), location: 0.60),
                        .init(color: .black.opacity(0.80), location: 0.80),
                        .init(color: .black.opacity(0.95), location: 1.0),
                    ], startPoint: .top, endPoint: .bottom),
                )
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        ZStack {
            VStack(spacing: 3) {
                if !lyricsMode {
                    Text("Now Playing")
                        .font(.system(size: 16, weight: .bold))
                        .shadow(color: design == .fullArt ? .black.opacity(0.7) : .clear,
                                radius: 3, y: 2)
                    if let title = player.current?.title, !title.isEmpty {
                        Text("\(title) mix")
                            .font(.system(size: 13, weight: .medium))
                            .opacity(0.72)
                            .lineLimit(1)
                            .shadow(color: design == .fullArt ? .black.opacity(0.7) : .clear,
                                    radius: 3, y: 2)
                    }
                }
            }
            .padding(.horizontal, 48)
        }
    }

    // MARK: Title + progress

    private var titleAndProgress: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if lyricsMode {
                    RemoteImage(url: player.current?.artURL(size: 144), size: 42) {
                        ArtPlaceholder()
                    }
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(player.current?.title ?? "")
                        .font(.system(size: lyricsMode ? 18 : 21, weight: .bold))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if player.current?.isExplicit == true {
                            Text("E")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 15, height: 15)
                                .background(Color.white.opacity(0.72))
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                        Text(player.current?.artist ?? "")
                            .font(.system(size: lyricsMode ? 14 : 15))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                            .opensArtist(player)
                    }
                }
                Spacer(minLength: 6)

                if lyricsMode {
                    Button { immersive.toggle() } label: {
                        Image(systemName: immersive
                              ? "arrow.down.right.and.arrow.up.left"
                              : "viewfinder")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(Color.white)
                            .clipShape(Circle())
                    }

                    if !immersive {
                        Button { showMenu = true } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: 36, height: 36)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                    }
                } else {
                    Button { player.toggleFavorite() } label: {
                        Image(systemName: player.isCurrentFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(player.isCurrentFavorite ? Lunara.green : .white)
                            .frame(width: 34, height: 34)
                    }

                    Button { showAddToPlaylist = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 34)
                            .background(Color.white)
                            .clipShape(Circle())
                    }

                    if let track = player.current {
                        let dlState = downloads.state(track.videoId)
                        Button { downloads.toggle(track) } label: {
                            Image(systemName: dlState == .done ? "checkmark" : "arrow.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: 34, height: 34)
                                .background(dlState == .done ? Lunara.green : Color.white)
                                .clipShape(Circle())
                        }
                        .disabled(player.isCurrentLive)
                    }

                    Button { showShare = true } label: {
                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 34)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 24)

            if let err = player.lastError {
                Text(err)
                    .font(.caption2).foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32).padding(.top, 8)
            }

            Spacer().frame(height: 22)

            if player.isCurrentLive {
                LiveBadge()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            } else {
                SlimSlider(
                    value: Binding(get: { scrub ?? player.progress }, set: { scrub = $0 }),
                    active: Lunara.green,
                    duration: player.duration,
                    isPlaying: player.isPlaying,
                ) { v in
                    player.seek(to: v)
                    scrub = nil
                }
                .padding(.horizontal, 24)
                .transaction { $0.animation = nil }
                .onChange(of: player.current?.videoId) { scrub = nil }

                HStack {
                    Text(timeString((scrub ?? player.progress) * player.duration))
                    Spacer()
                    Text(timeString(player.duration))
                }
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 28)
                .padding(.top, 6)
            }
        }
    }

    // MARK: Transport — shuffle · prev · PLAY · next · repeat

    private var transport: some View {
        HStack(spacing: 0) {
            sideButton("shuffle", active: player.isShuffled,
                       label: player.isShuffled ? "Shuffle on" : "Shuffle off") {
                player.toggleShuffle()
            }
            sideButton("backward.end.fill", label: "Previous song") { player.prev() }

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 68, height: 68)
                    .background(Lunara.green)
                    .clipShape(Circle())
            }
            .padding(.horizontal, 8)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            sideButton("forward.end.fill", label: "Next song") { _ = player.next() }
            sideButton(player.repeatMode == .one ? "repeat.1" : "repeat",
                       active: player.repeatMode != .off,
                       label: repeatLabel) { player.cycleRepeat() }
        }
        .padding(.horizontal, 24)
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: return "Repeat off"
        case .all: return "Repeat all"
        case .one: return "Repeat one"
        }
    }

    private func sideButton(_ icon: String, active: Bool = false, label: String = "",
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(active ? Lunara.green : .white)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(label)
    }

    // MARK: Bottom row

    private var bottomRow: some View {
        HStack(spacing: 0) {
            bottomButton("text.line.first.and.arrowtriangle.forward", "Queue") { showQueue = true }
            bottomButton("waveform", "Lyrics", active: lyricsMode) {
                lyricsMode.toggle()
                if !lyricsMode { immersive = false }
            }
        }
        .padding(.horizontal, 48)
    }

    private func bottomButton(_ icon: String, _ label: String,
                              active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19))
                Text(label).font(.system(size: 11.5, weight: active ? .semibold : .regular)).lineLimit(1)
            }
            .foregroundStyle(active ? Lunara.green : .white.opacity(0.85))
            .frame(maxWidth: .infinity)
        }
    }

    private var sleepLabel: String {
        if player.sleepAtEndOfSong { return "End of song" }
        if let r = player.sleepRemaining { return timeString(r) }
        return "Sleep timer"
    }

}
