import AVFoundation
import AVKit
import SwiftUI

struct SongVideo: Equatable {
    let videoId: String
    let url: URL
    let synced: Bool
    let maxHeight: Int
    var alternate: URL? = nil

    var fallenBack: SongVideo? {
        guard let alternate else { return nil }
        return SongVideo(videoId: videoId, url: alternate, synced: synced, maxHeight: maxHeight)
    }
}

actor SongVideos {
    static let shared = SongVideos()

    private struct Found {
        let video: SongVideo?
        let at: Date
    }

    private var known: [String: Found] = [:]
    private var pending: [String: Task<SongVideo?, Never>] = [:]

    private let keep: TimeInterval = 3 * 60 * 60

    private let keepNone: TimeInterval = 2 * 60

    private let sameCutSeconds: Double = 3

    private let candidates = 5

    func forSong(_ track: Track, maxHeight: Int) async -> SongVideo? {
        let key = "\(track.videoId)@\(maxHeight)"
        if let found = known[key] {
            let age = Date().timeIntervalSince(found.at)
            if age < (found.video == nil ? keepNone : keep) { return found.video }
        }
        if let running = pending[key] { return await running.value }

        let task = Task<SongVideo?, Never> { [track, maxHeight] in
            await Self.find(track, maxHeight: maxHeight,
                            candidates: candidates, sameCutSeconds: sameCutSeconds)
        }
        pending[key] = task
        let found = await task.value
        known[key] = Found(video: found, at: Date())
        pending[key] = nil
        return found
    }

    private static func find(_ track: Track, maxHeight: Int,
                             candidates: Int, sameCutSeconds: Double) async -> SongVideo? {
        if track.isVideo, !LocalMusic.isLocal(track.videoId) {
            guard let found = await YouTube.videoStream(for: track.videoId, maxHeight: maxHeight)
            else { return nil }
            return SongVideo(videoId: track.videoId, url: found.url, synced: true, maxHeight: maxHeight,
                             alternate: found.alternate)
        }

        guard !track.title.isEmpty, !LocalMusic.isLocal(track.videoId) else { return nil }
        let query = track.artist.isEmpty ? track.title : "\(track.title) \(track.artist)"
        let results = await YouTube.search(query, scope: .videos)
        let official = results.prefix(candidates).filter(\.isOfficialVideo)
        VideoArtLog.note("lookup: \"\(query)\" → \(results.count) results, \(official.count) official")
        guard !official.isEmpty else { return nil }

        let closest = track.duration > 0
            ? official.min { abs($0.duration - track.duration) < abs($1.duration - track.duration) }
            : nil
        let candidate = closest ?? official[0]
        let synced = closest.map { $0.duration > 0 && abs($0.duration - track.duration) <= sameCutSeconds } ?? false
        VideoArtLog.note("lookup: chose \(candidate.videoId) (\(Int(candidate.duration))s for a \(Int(track.duration))s song, \(synced ? "in step" : "its own cut"))")
        guard let found = await YouTube.videoStream(for: candidate.videoId, maxHeight: maxHeight)
        else { return nil }
        return SongVideo(videoId: candidate.videoId, url: found.url, synced: synced,
                         maxHeight: maxHeight, alternate: found.alternate)
    }
}

@MainActor
final class SongVideoLoader: ObservableObject {
    @Published private(set) var video: SongVideo?

    @Published private(set) var note: String?

    private var loadedFor: String?

    func load(for track: Track?, allowed: Bool, maxHeight: Int) {
        guard allowed else {
            VideoArtLog.note("load: not allowed on this connection (mobile data, videos off)")
            video = nil
            loadedFor = nil
            note = String(localized: "Videos stay off on mobile data — Settings › Player and audio")
            return
        }
        guard let track else {
            video = nil
            loadedFor = nil
            note = nil
            return
        }
        let key = "\(track.videoId)@\(maxHeight)"
        guard key != loadedFor else { return }
        loadedFor = key
        video = nil
        note = String(localized: "Looking for a video…")
        VideoArtLog.note("load: looking for \(track.videoId) \"\(track.title)\" isVideo=\(track.isVideo) up to \(maxHeight)p")
        Task {
            let found = await SongVideos.shared.forSong(track, maxHeight: maxHeight)
            guard loadedFor == key else { return }
            if let found {
                VideoArtLog.note("load: found \(found.videoId) synced=\(found.synced) "
                    + "\(VideoArtLog.kind(of: found.url)) alternate=\(found.alternate.map(VideoArtLog.kind(of:)) ?? "none")")
            } else {
                VideoArtLog.note("load: nothing found for \(track.videoId)")
            }
            video = found
            note = found == nil ? String(localized: "No video found for this song") : nil
        }
    }

    func prepareNext(_ track: Track?, allowed: Bool, maxHeight: Int) {
        guard allowed, let track, !track.videoId.isEmpty, !LocalMusic.isLocal(track.videoId)
        else { return }
        Task {
            guard let found = await SongVideos.shared.forSong(track, maxHeight: maxHeight) else { return }
            VideoArtPlayers.shared.prepare(found)
        }
    }

    func trouble(_ reason: String) {
        VideoArtLog.note("trouble: \(reason)")
        guard video != nil else { return }
        video = nil
        note = reason
    }
}

final class VideoArtPlayers {
    static let shared = VideoArtPlayers()

    private var url: URL?
    private var kept: AVPlayer?
    private var output: AVPlayerItemVideoOutput?

    private var nextURL: URL?
    private var nextPlayer: AVPlayer?
    private var nextOutput: AVPlayerItemVideoOutput?

    private static let buffer: TimeInterval = 0.8

    static let deepBuffer: TimeInterval = 45

    func player(for video: SongVideo) -> (player: AVPlayer, output: AVPlayerItemVideoOutput?, fresh: Bool) {
        if url == video.url, let kept, kept.currentItem?.status != .failed { return (kept, output, false) }

        if nextURL == video.url, let ready = nextPlayer, ready.currentItem?.status != .failed {
            release()
            url = video.url
            kept = ready
            output = nextOutput
            nextURL = nil
            nextPlayer = nil
            nextOutput = nil
            return (ready, output, true)
        }

        release()
        let (made, videoOutput) = build(video)
        url = video.url
        kept = made
        output = videoOutput
        return (made, videoOutput, true)
    }

    func prepare(_ video: SongVideo) {
        guard url != video.url, nextURL != video.url else { return }
        nextPlayer?.pause()
        nextPlayer?.replaceCurrentItem(with: nil)
        let (made, videoOutput) = build(video)
        made.pause()
        nextURL = video.url
        nextPlayer = made
        nextOutput = videoOutput
    }

    private func build(_ video: SongVideo) -> (AVPlayer, AVPlayerItemVideoOutput) {
        let onWiFi = Reachability.shared.isUnmetered
        let asset = AVURLAsset(url: video.url, options: [
            AVURLAssetHTTPUserAgentKey: YouTube.visionUA,
            AVURLAssetAllowsCellularAccessKey: !onWiFi,
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = Self.buffer
        if VideoArtLog.kind(of: video.url) == "hls" {
            item.preferredMaximumResolution = CGSize(width: video.maxHeight * 2, height: video.maxHeight)
        }
        let made = AVPlayer(playerItem: item)
        made.isMuted = true
        made.actionAtItemEnd = .none
        made.automaticallyWaitsToMinimizeStalling = false
        VideoArtLog.note("player: built for \(VideoArtLog.kind(of: video.url)) \(video.videoId) wifi=\(onWiFi)")

        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(videoOutput)
        return (made, videoOutput)
    }

    func rest() { kept?.pause() }

    func release() {
        kept?.pause()
        kept?.replaceCurrentItem(with: nil)
        kept = nil
        output = nil
        url = nil
    }

    func releaseAll() {
        release()
        nextPlayer?.pause()
        nextPlayer?.replaceCurrentItem(with: nil)
        nextPlayer = nil
        nextOutput = nil
        nextURL = nil
    }
}

struct VideoArtView: UIViewRepresentable {
    let video: SongVideo
    let position: Double
    let isPlaying: Bool
    var songLength: Double = 0
    var onTrouble: (String) -> Void = { _ in }
    var onFirstFrame: () -> Void = { }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .clear
        context.coordinator.onTrouble = onTrouble
        context.coordinator.onFirstFrame = onFirstFrame
        context.coordinator.attach(to: view, video: video)
        return view
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        context.coordinator.onTrouble = onTrouble
        context.coordinator.onFirstFrame = onFirstFrame
        context.coordinator.update(video: video, position: position, songLength: songLength,
                                   isPlaying: isPlaying, view: view)
    }

    static func dismantleUIView(_ view: PlayerContainerView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var player: AVPlayer?
        private var current: SongVideo?
        var onTrouble: (String) -> Void = { _ in }
        var onFirstFrame: () -> Void = { }

        private var statusObs: NSKeyValueObservation?
        private var readyObs: NSKeyValueObservation?
        private var controlObs: NSKeyValueObservation?
        private var keepUpObs: NSKeyValueObservation?
        private var endObs: NSObjectProtocol?
        private var stallObs: NSObjectProtocol?
        private var errorLogObs: NSObjectProtocol?
        private var stalled = false
        private var wanted = false
        private var watchdog: Task<Void, Never>?
        private var output: AVPlayerItemVideoOutput?
        private var bandsLook: Task<Void, Never>?
        private var bands: Double = 1

        private let inStep: Double = 0.08

        private let jumpBeyond: Double = 2

        private var lead: Double = 0.8
        private var justJumped = false
        private let maxLead: Double = 4

        private var placed = false
        private var lastPosition: Double = 0

        private let openingTitles: Double = 6

        private let patience: UInt64 = 15

        private var fellBack = false

        func attach(to view: PlayerContainerView, video: SongVideo, fallingBack: Bool = false) {
            let playing = fallingBack ? (video.fallenBack ?? video) : video
            let lent = VideoArtPlayers.shared.player(for: playing)
            let player = lent.player
            self.player = player
            self.current = video
            self.output = lent.output
            view.playerLayer.player = player
            view.playerLayer.videoGravity = .resizeAspectFill
            view.setZoom(1, animated: false)
            player.play()
            stalled = false
            VideoArtLog.note("attach: \(fallingBack ? "fallback " : "")\(VideoArtLog.kind(of: playing.url)) "
                + "\(playing.videoId) fresh=\(lent.fresh) itemStatus=\(player.currentItem?.status.rawValue ?? -1)")

            let item = player.currentItem
            statusObs = item?.observe(\.status, options: [.new]) { [weak self, weak view] item, _ in
                if item.status == .readyToPlay {
                    VideoArtLog.note("item: ready, duration=\(item.duration.seconds.isFinite ? Int(item.duration.seconds) : -1)s")
                }
                guard item.status == .failed else { return }
                let reason = item.error?.localizedDescription ?? "the video would not load"
                if let error = item.error as NSError? {
                    VideoArtLog.note("item: FAILED \(error.domain) \(error.code) — \(error.localizedDescription)"
                        + (error.userInfo[NSUnderlyingErrorKey].map { " / under: \($0)" } ?? ""))
                    if let asset = item.asset as? AVURLAsset { VideoArtLog.probe(asset.url) }
                } else {
                    VideoArtLog.note("item: FAILED with no error")
                }
                Task { @MainActor [weak self, weak view] in
                    guard let self else { return }
                    if !self.fellBack, video.alternate != nil, let view {
                        self.fellBack = true
                        VideoArtLog.note("item: trying the alternate address")
                        self.stopWatching()
                        self.attach(to: view, video: video, fallingBack: true)
                        return
                    }
                    self.onTrouble(reason)
                }
            }
            readyObs = view.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self, weak player, weak view] layer, _ in
                guard layer.isReadyForDisplay else { return }
                VideoArtLog.note("layer: first frame, rate=\(player?.rate ?? -1)")
                self?.watchdog?.cancel()
                player?.currentItem?.preferredForwardBufferDuration = VideoArtPlayers.deepBuffer
                Task { @MainActor [weak self, weak view] in
                    if let self, let view { await self.lookForBands(in: view, animated: false) }
                    self?.onFirstFrame()
                    if let view { self?.startBandLooks(in: view) }
                }
            }
            controlObs = player.observe(\.timeControlStatus, options: [.new]) { player, _ in
                let why = player.reasonForWaitingToPlay.map { " (\($0.rawValue))" } ?? ""
                VideoArtLog.note("player: \(player.timeControlStatus.rawValue == 0 ? "paused" : player.timeControlStatus.rawValue == 1 ? "waiting" : "playing")\(why) rate=\(player.rate)")
            }
            if let errorLogObs { NotificationCenter.default.removeObserver(errorLogObs) }
            errorLogObs = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemNewErrorLogEntry, object: item, queue: .main,
            ) { [weak player] _ in
                guard let event = player?.currentItem?.errorLog()?.events.last else { return }
                VideoArtLog.note("item: error \(event.errorDomain) \(event.errorStatusCode)"
                    + (event.errorComment.map { " — \($0.prefix(80))" } ?? "")
                    + " at \(Int(player?.currentTime().seconds ?? 0))s")
            }
            if let stallObs { NotificationCenter.default.removeObserver(stallObs) }
            stallObs = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main,
            ) { [weak self, weak player] _ in
                self?.stalled = true
                VideoArtLog.note("item: stalled at \(Int(player?.currentTime().seconds ?? 0))s")
            }
            keepUpObs = item?.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self, weak player] item, _ in
                guard item.isPlaybackLikelyToKeepUp, let self, self.stalled else { return }
                self.stalled = false
                VideoArtLog.note("item: buffer back, \(self.wanted ? "playing again" : "left paused")")
                if self.wanted { player?.play() }
            }
            self.bands = 1
            bandsLook?.cancel()

            watchdog?.cancel()
            watchdog = Task { [weak self, weak view, weak player] in
                try? await Task.sleep(nanoseconds: (self?.patience ?? 15) * 1_000_000_000)
                guard !Task.isCancelled, let view, !view.playerLayer.isReadyForDisplay else { return }
                let item = player?.currentItem
                VideoArtLog.note("watchdog: no frame after 15s — itemStatus=\(item?.status.rawValue ?? -1) "
                    + "bufferEmpty=\(item?.isPlaybackBufferEmpty ?? false) keepUp=\(item?.isPlaybackLikelyToKeepUp ?? false) "
                    + "loaded=\(item?.loadedTimeRanges.count ?? 0) rate=\(player?.rate ?? -1)")
                await MainActor.run { self?.onTrouble("The video never started playing") }
            }

            if let endObs { NotificationCenter.default.removeObserver(endObs) }
            endObs = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem, queue: .main,
            ) { [weak self, weak player] _ in
                let length = player?.currentItem?.duration.seconds ?? 0
                let from = length.isFinite && length > 0 ? min(6, length / 4) : 0
                VideoArtLog.note("item: reached its end at \(Int(length))s, going round again from \(Int(from))s")
                self?.stalled = false
                player?.seek(to: CMTime(seconds: from, preferredTimescale: 600))
                player?.play()
            }
        }

        func update(video: SongVideo, position: Double, songLength: Double,
                    isPlaying: Bool, view: PlayerContainerView) {
            if current != video {
                stop()
                placed = false
                lead = 0.8
                fellBack = false
                attach(to: view, video: video)
            }
            guard let player else { return }
            defer { lastPosition = position }
            wanted = isPlaying

            guard isPlaying else {
                if player.rate != 0 { player.pause() }
                return
            }
            if stalled {
                guard let item = player.currentItem else { return }
                let length = item.duration.seconds
                let atEnd = length.isFinite && length > 0 && player.currentTime().seconds >= length - 0.5
                guard item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull || !item.isPlaybackBufferEmpty || atEnd
                else { return }
                stalled = false
                VideoArtLog.note("item: buffer back at \(Int(player.currentTime().seconds))s, playing again")
                player.play()
                return
            }
            if player.rate == 0 { player.play() }
            guard player.currentItem?.status == .readyToPlay else { return }

            let moved = abs(position - lastPosition) > jumpBeyond

            guard video.synced else {
                if !placed || moved { place(player, at: position, songLength: songLength) }
                let length = player.currentItem?.duration.seconds ?? 0
                let at = player.currentTime().seconds
                if length.isFinite, length > 1, at.isFinite, at >= length - 0.25, player.rate == 0 {
                    let from = min(6, length / 4)
                    VideoArtLog.note("item: at its end (\(Int(at))/\(Int(length))s) with no notice, going round again")
                    player.seek(to: CMTime(seconds: from, preferredTimescale: 600))
                    player.play()
                }
                return
            }

            let at = player.currentTime().seconds
            guard at.isFinite else { return }
            let drift = position - at

            if justJumped {
                lead = min(max(lead + drift / 2, 0), maxLead)
                justJumped = false
            }

            if abs(drift) > jumpBeyond {
                player.rate = 1
                player.seek(to: CMTime(seconds: position + lead, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero)
                justJumped = true
            } else if abs(drift) > inStep {
                player.rate = Float(1 + min(max(drift / 4, -0.25), 0.25))
            } else if player.rate != 1 {
                player.rate = 1
            }
        }

        private func place(_ player: AVPlayer, at position: Double, songLength: Double) {
            let length = player.currentItem?.duration.seconds ?? 0
            guard length.isFinite, length > 0 else { return }
            let along = songLength > 0 ? position / songLength : 0
            let target = max(along * length, min(openingTitles, length / 4))
            player.seek(to: CMTime(seconds: min(target, length - 1), preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
            placed = true
        }

        @MainActor
        private func startBandLooks(in view: PlayerContainerView) {
            bandsLook?.cancel()
            bandsLook = Task { [weak self, weak view] in
                for wait in [1.0, 2.0, 4.0, 8.0] {
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    guard !Task.isCancelled, let self, let view else { return }
                    await self.lookForBands(in: view)
                }
            }
        }

        @MainActor
        private func lookForBands(in view: PlayerContainerView, animated: Bool = true) async {
            self.output?.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.1)
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let output = self.output else { return }
            let time = output.itemTime(forHostTime: CACurrentMediaTime())
            guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
                VideoArtLog.note("bands: no frame to read at \(Int(time.seconds))s (new=\(output.hasNewPixelBuffer(forItemTime: time)))")
                return
            }

            guard let rows = Self.brightness(of: buffer),
                  let share = Letterbox.share(rows: rows)
            else {
                VideoArtLog.note("bands: frame too dark to judge at \(Int(time.seconds))s")
                return
            }

            bands = min(bands, share)
            let zoom = Letterbox.zoom(for: bands == 1 ? 0 : bands)
            VideoArtLog.note("bands: \(Int(share * 100))% at \(Int(time.seconds))s, least \(Int(bands * 100))% → zoom \(String(format: "%.2f", zoom))")
            guard abs(view.zoom - CGFloat(zoom)) > 0.001 else { return }
            view.setZoom(CGFloat(zoom), animated: animated)
        }

        private static func brightness(of buffer: CVPixelBuffer) -> [[Double]]? {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            guard width > 8, height > 8 else { return nil }

            let columns = 48, lines = 54
            var rows: [[Double]] = []
            rows.reserveCapacity(lines)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for line in 0..<lines {
                let y = line * (height - 1) / (lines - 1)
                var row: [Double] = []
                row.reserveCapacity(columns)
                for column in 0..<columns {
                    let x = column * (width - 1) / (columns - 1)
                    let at = y * stride + x * 4
                    let blue = Double(bytes[at]), green = Double(bytes[at + 1]), red = Double(bytes[at + 2])
                    row.append((red * 299 + green * 587 + blue * 114) / 1000)
                }
                rows.append(row)
            }
            return rows
        }

        func stop() {
            stopWatching()
            output = nil
            player = nil
            current = nil
            VideoArtPlayers.shared.rest()
        }

        private func stopWatching() {
            if let endObs { NotificationCenter.default.removeObserver(endObs) }
            endObs = nil
            if let stallObs { NotificationCenter.default.removeObserver(stallObs) }
            stallObs = nil
            if let errorLogObs { NotificationCenter.default.removeObserver(errorLogObs) }
            errorLogObs = nil
            statusObs = nil
            readyObs = nil
            controlObs = nil
            keepUpObs = nil
            stalled = false
            watchdog?.cancel()
            watchdog = nil
            bandsLook?.cancel()
            bandsLook = nil
        }
    }
}

final class PlayerContainerView: UIView {
    let playerLayer = AVPlayerLayer()
    private(set) var zoom: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = zoomedFrame
        CATransaction.commit()
    }

    func setZoom(_ zoom: CGFloat, animated: Bool) {
        self.zoom = zoom
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.6)
        } else {
            CATransaction.setDisableActions(true)
        }
        playerLayer.frame = zoomedFrame
        CATransaction.commit()
    }

    private var zoomedFrame: CGRect {
        bounds.insetBy(dx: -bounds.width * (zoom - 1) / 2, dy: -bounds.height * (zoom - 1) / 2)
    }
}

enum Letterbox {
    static let dark: Double = 24

    static let printShare = 0.25

    static let smallest = 0.04
    static let largest = 0.22

    static func share(rows: [[Double]]) -> Double? {
        guard let width = rows.first?.count, width > 0, rows.count > 4 else { return nil }
        func isBand(_ row: [Double]) -> Bool {
            row.filter { $0 >= dark }.count <= Int(Double(width) * printShare)
        }
        var top = 0
        while top < rows.count / 2, isBand(rows[top]) { top += 1 }
        var bottom = 0
        while bottom < rows.count / 2, isBand(rows[rows.count - 1 - bottom]) { bottom += 1 }
        let share = Double(min(top, bottom)) / Double(rows.count)
        if share > largest { return nil }
        return share >= smallest ? share : 0
    }

    static func zoom(for share: Double) -> Double {
        share > 0 ? 1 / (1 - 2 * share) : 1
    }
}
