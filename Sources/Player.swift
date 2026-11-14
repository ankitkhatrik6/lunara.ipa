import AVFoundation
import MediaPlayer
import UIKit
import Foundation
import SwiftUI

final class Player: ObservableObject {

    enum RepeatMode: Int { case off, all, one }

    @Published var queue: [Track] = []
    @Published var index = 0
    @Published var isPlaying = false
    @Published var isLoading = false
    let clock = PlaybackClock()
    var currentTime: Double {
        get { clock.currentTime }
        set { clock.currentTime = newValue }
    }
    @Published var duration = 0.0

    @Published private(set) var liveBroadcasts: Set<String> = []
    private var liveRestartedAt: [String: Date] = [:]

    var isCurrentLive: Bool {
        guard let id = current?.videoId else { return false }
        return liveBroadcasts.contains(id)
    }

    @Published private(set) var repeatTimesLeft = 0
    private var repeatModeBeforeCount: RepeatMode = .off

    private var sponsorSegments: [SponsorBlock.Segment] = []
    private var sponsorTask: Task<Void, Never>?
    private var lastSponsorSkip: (end: Double, at: Date)?
    @Published private(set) var sponsorSkipped = 0.0
    @Published var showFullPlayer = false

    func openFullPlayer() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { showFullPlayer = true }
    }

    @Published var sheetDrag: CGFloat = 0

    @Published var lastError: String?

    @Published var isShuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var favorites: Set<String> = []
    @Published var favoriteTracks: [Track] = []
    @Published var artColor: Color = Lunara.green

    private var originalQueue: [Track] = []

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var hasTrack: Bool { current != nil }

    var upNext: Track? {
        queue.indices.contains(index + 1) ? queue[index + 1] : nil
    }

    private(set) var bufferedAhead: TimeInterval = 0

    static let comfortableAhead: TimeInterval = 6

    var songComfortable: Bool {
        !isLoading && (!isPlaying || isCurrentLive || bufferedAhead >= Self.comfortableAhead)
    }

    func waitUntilSongComfortable(upTo seconds: TimeInterval = 30) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !songComfortable, Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private static func bufferedAhead(of item: AVPlayerItem?, at time: CMTime) -> TimeInterval {
        guard let item, time.isNumeric else { return 0 }
        let now = time.seconds
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let start = range.start.seconds, end = range.end.seconds
            guard start.isFinite, end.isFinite else { continue }
            if start <= now + 0.5, end > now { return end - now }
        }
        return 0
    }
    var progress: Double {
        guard duration > 0, currentTime.isFinite, duration.isFinite else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    private var avPlayer: AVPlayer?
    private var timeObserver: Any?
    private var volumeObs: NSKeyValueObservation?
    private var pausedByMute = false
    private var statusObs: NSKeyValueObservation?
    private var rateObs: NSKeyValueObservation?
    private var isSeeking = false
    private var fadePlayer: AVPlayer?
    private var fadeTimer: Timer?
    private var crossfading = false
    private var preparedPlayer: AVPlayer?
    private var preparedDuration: Double = 0
    private var fadeDuration: Double = 0
    private var preparedIndex: Int?
    private var preparedVideoId: String?
    private var endHandled = false
    private var artwork: MPMediaItemArtwork?
    @Published private(set) var artworkImage: UIImage?

    init() {
        configureSession()
        setupRemoteCommands()
        loadFavorites()
        restoreModes()
        restoreQueue()
        observeRouteChanges()
        observeInterruptions()
        observeVolume()
        NotificationCenter.default.addObserver(
            forName: .lunaraAudioPrefsChanged, object: nil, queue: .main,
        ) { [weak self] _ in self?.applyAudioPrefs() }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            self?.saveQueue()
            self?.backgroundedAt = Date()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            guard let self, let away = self.backgroundedAt else { return }
            self.backgroundedAt = nil
            guard Date().timeIntervalSince(away) >= 10 * 60 else { return }
            self.lastFreshStart = Date()
            YouTube.freshStart()
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main,
        ) { [weak self] _ in self?.mediaServicesWereReset() }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            self?.saveQueue()
            self?.avPlayer?.pause()
            self?.avPlayer?.replaceCurrentItem(with: nil)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main,
        ) { [weak self] note in
            guard let self,
                  let ended = note.object as? AVPlayerItem,
                  ended === self.avPlayer?.currentItem
            else { return }
            self.trackEnded()
        }
    }

    // MARK: - Persistence of the session

    private struct SavedQueue: Codable {
        let tracks: [Track]
        let index: Int
        let position: Double
    }

    private func saveQueue() {
        guard PlaybackPrefs.shared.persistentQueue else { return }
        let saved = SavedQueue(tracks: queue, index: index, position: currentTime)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "savedQueue")
        }
    }

    private func restoreQueue() {
        guard PlaybackPrefs.shared.persistentQueue,
              let data = UserDefaults.standard.data(forKey: "savedQueue"),
              let saved = try? JSONDecoder().decode(SavedQueue.self, from: data),
              !saved.tracks.isEmpty else { return }
        queue = saved.tracks
        originalQueue = saved.tracks
        index = min(max(saved.index, 0), saved.tracks.count - 1)
        resumePosition = saved.position
        resumeVideoId = saved.tracks[index].videoId
        if let track = current {
            duration = Downloads.shared.duration(for: track.videoId) ?? track.duration
            currentTime = saved.position
        }
    }

    private var resumePosition: Double = 0
    private var resumeVideoId: String?
    private var playWhenReady = false

    private func saveModes() {
        guard PlaybackPrefs.shared.rememberShuffleRepeat else { return }
        UserDefaults.standard.set(isShuffled, forKey: "shuffleOn")
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
    }

    private func restoreModes() {
        guard PlaybackPrefs.shared.rememberShuffleRepeat else { return }
        isShuffled = UserDefaults.standard.bool(forKey: "shuffleOn")
        repeatMode = RepeatMode(rawValue: UserDefaults.standard.integer(forKey: "repeatMode")) ?? .off
    }

    private func observeVolume() {
        volumeObs = AVAudioSession.sharedInstance().observe(
            \.outputVolume, options: [.new],
        ) { [weak self] session, _ in
            DispatchQueue.main.async {
                guard let self, PlaybackPrefs.shared.pauseOnMute else { return }
                if session.outputVolume <= 0.001 {
                    if self.isPlaying {
                        self.pausedByMute = true
                        self.pause()
                    }
                } else if self.pausedByMute {
                    self.pausedByMute = false
                    self.resume()
                }
            }
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main,
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.isPlaying = false
                self.updateNowPlaying()
            case .ended:
                let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
                guard options.contains(.shouldResume) else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                self.avPlayer?.play()
                self.avPlayer?.rate = Float(PlaybackPrefs.shared.speed)
            @unknown default:
                break
            }
        }
    }

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main,
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            switch reason {
            case .oldDeviceUnavailable:
                self.avPlayer?.pause()
                self.isPlaying = false
                self.updateNowPlaying()
            case .newDeviceAvailable:
                guard PlaybackPrefs.shared.resumeOnBluetooth,
                      self.hasTrack, !self.isPlaying else { return }
                self.toggle()
            default:
                break
            }
        }
    }

    // MARK: - Queue control

    func play(_ tracks: [Track], startAt: Int) {
        failedInARow = 0
        originalQueue = tracks
        queue = tracks
        index = startAt
        if isShuffled { applyShuffle() }
        loadCurrent()
    }

    func playWithRadio(_ track: Track) {
        play([track], startAt: 0)
        guard PlaybackPrefs.shared.autoplay, PlaybackPrefs.shared.autoRadioQueue else { return }
        guard !LocalMusic.isLocal(track.videoId), !track.videoId.isEmpty else { return }

        Task { @MainActor in
            var fresh = await self.radioTracks(for: track)
            if fresh.isEmpty {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                fresh = await self.radioTracks(for: track)
            }
            guard self.current?.videoId == track.videoId else {
                VideoArtLog.note("radio \(track.videoId): moved on, \(fresh.count) not added")
                return
            }
            let known = Set(self.queue.map(\.videoId))
            let add = fresh.filter { !known.contains($0.videoId) }
            VideoArtLog.note("radio \(track.videoId): \(fresh.count) found, \(add.count) added to \(self.queue.count)")
            guard !add.isEmpty else { return }
            self.queue.append(contentsOf: add)
            self.originalQueue = self.queue
            self.saveQueue()
        }
    }

    private func radioTracks(for track: Track) async -> [Track] {
        let mix = await YouTube.mix(playlistId: "RDAMVM" + track.videoId)
            .filter { !$0.videoId.isEmpty && $0.videoId != track.videoId }
        if !mix.isEmpty { return mix }
        return await YouTube.related(videoId: track.videoId)
            .flatMap(\.items)
            .filter { $0.browseId == nil }
            .map(\.asTrack)
            .filter { !$0.videoId.isEmpty && $0.videoId != track.videoId }
    }

    @discardableResult
    func next(auto: Bool = false) -> Bool {
        if !auto { repeatCurrentSong(times: 0) }
        if index < queue.count - 1 {
            if !auto, adoptPreparedPlayer(byHand: true) { return true }
            index += 1
            loadCurrent()
            return true
        } else if repeatMode == .all {
            index = 0
            loadCurrent()
            return true
        }
        return false
    }

    // MARK: - Shuffle / repeat / favorite

    func toggleShuffle() {
        defer { saveModes() }
        isShuffled.toggle()
        guard let cur = current else { return }
        if isShuffled {
            applyShuffle()
        } else {
            queue = originalQueue
            index = originalQueue.firstIndex(of: cur) ?? 0
        }
    }

    private func applyShuffle() {
        guard let cur = current else { return }
        var rest = queue
        rest.removeAll { $0 == cur }
        rest.shuffle()
        queue = [cur] + rest
        index = 0
    }

    func cycleRepeat() {
        defer { saveModes() }
        repeatTimesLeft = 0
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func toggleFavorite() {
        guard let track = current else { return }
        setFavorite(track, liked: !favorites.contains(track.videoId))
    }

    func setFavorite(_ track: Track, liked: Bool) {
        if liked, PlaybackPrefs.shared.autoDownloadOnLike {
            Downloads.shared.download(track)
        }
        apply(track, liked: liked)
    }

    private func apply(_ track: Track, liked: Bool) {
        if liked {
            favorites.insert(track.videoId)
            if !favoriteTracks.contains(where: { $0.videoId == track.videoId }) {
                favoriteTracks.insert(track, at: 0)
            }
        } else {
            favorites.remove(track.videoId)
            favoriteTracks.removeAll { $0.videoId == track.videoId }
        }
        saveFavorites()
    }

    var isCurrentFavorite: Bool {
        guard let id = current?.videoId else { return false }
        return favorites.contains(id)
    }

    private func saveFavorites() {
        guard let data = try? JSONEncoder().encode(favoriteTracks) else { return }
        UserDefaults.standard.set(data, forKey: "favoriteTracks")
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: "favoriteTracks"),
              let saved = try? JSONDecoder().decode([Track].self, from: data) else { return }
        favoriteTracks = saved
        favorites = Set(saved.map(\.videoId))
    }

    private func countPlay(_ track: Track) {
        PlayHistory.record(track)
    }

    func moveInQueue(from offsets: IndexSet, to destination: Int) {
        guard let playing = current else { return }
        queue.move(fromOffsets: offsets, toOffset: destination)
        originalQueue = queue
        if let now = queue.firstIndex(where: { $0.videoId == playing.videoId }) {
            index = now
        }
        saveQueue()
    }

    func removeFromQueue(at position: Int) {
        guard queue.indices.contains(position) else { return }
        let wasPlaying = position == index
        let removed = queue.remove(at: position)
        originalQueue.removeAll { $0.videoId == removed.videoId }

        if queue.isEmpty {
            avPlayer?.pause()
            isPlaying = false
            index = 0
            saveQueue()
            return
        }
        if wasPlaying {
            index = min(position, queue.count - 1)
            loadCurrent()
        } else if position < index {
            index -= 1
        }
        saveQueue()
    }

    func jump(to i: Int) {
        cancelCrossfade()
        discardPrepared()
        guard queue.indices.contains(i) else { return }
        index = i
        loadCurrent()
    }

    func playNext(_ track: Track) {
        guard hasTrack else {
            play([track], startAt: 0)
            return
        }
        guard !admissible([track]).isEmpty else { return }
        let at = playNextSlot()
        queue.insert(track, at: min(at, queue.count))
        originalQueue.insert(track, at: min(at, originalQueue.count))
        notePlayNextPick(track.videoId)
    }

    private var pendingPlayNextIds: [String] = []

    private func playNextSlot() -> Int {
        var slot = index + 1
        var matched = 0
        while slot < queue.count, matched < pendingPlayNextIds.count,
              queue[slot].videoId == pendingPlayNextIds[matched] {
            slot += 1
            matched += 1
        }
        return slot
    }

    func notePlayNextPick(_ videoId: String) {
        pendingPlayNextIds.removeAll { $0 == videoId }
        pendingPlayNextIds.append(videoId)
    }

    func moveToPlayNext(from: Int) {
        guard hasTrack, queue.indices.contains(from), from != index else { return }
        let track = queue[from]
        pendingPlayNextIds.removeAll { $0 == track.videoId }
        let target = playNextSlot()
        guard from != target else {
            notePlayNextPick(track.videoId)
            return
        }
        let to = from > target ? target : max(target - 1, index)
        guard from != to else {
            notePlayNextPick(track.videoId)
            return
        }
        moveInQueue(from: IndexSet(integer: from), to: from > to ? to : to + 1)
        notePlayNextPick(track.videoId)
    }

    private func admissible(_ tracks: [Track]) -> [Track] {
        guard PlaybackPrefs.shared.preventDuplicates else { return tracks }
        let known = Set(queue.map(\.videoId))
        var seen = Set<String>()
        return tracks.filter {
            !known.contains($0.videoId) && seen.insert($0.videoId).inserted
        }
    }

    func addToQueue(_ tracks: [Track]) {
        let fresh = admissible(tracks)
        guard !fresh.isEmpty else { return }
        if queue.isEmpty {
            play(fresh, startAt: 0)
        } else {
            queue.append(contentsOf: fresh)
            originalQueue.append(contentsOf: fresh)
        }
    }

    private func seekSilently(to seconds: Double) {
        guard let avPlayer, seconds.isFinite, seconds >= 0 else { return }
        currentTime = seconds
        avPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                      toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    // MARK: - Sleep timer

    @Published var sleepEndDate: Date?
    @Published var sleepAtEndOfSong = false
    @Published var sleepSongsRemaining: Int?
    private var sleepTimer: Timer?

    var sleepActive: Bool { sleepEndDate != nil || sleepAtEndOfSong || sleepSongsRemaining != nil }
    var sleepRemaining: TimeInterval? {
        guard let end = sleepEndDate else { return nil }
        return max(0, end.timeIntervalSinceNow)
    }

    func startSleepTimer(minutes: Int) {
        sleepAtEndOfSong = false
        sleepEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let end = self.sleepEndDate else { return }
            if Date() >= end {
                self.stopForSleep()
            } else {
                self.objectWillChange.send()
            }
        }
    }

    func setSleepAtEndOfSong() {
        cancelSleepTimer()
        sleepAtEndOfSong = true
    }

    func startSleepAfterSongs(_ count: Int) {
        cancelSleepTimer()
        sleepSongsRemaining = max(1, count)
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepEndDate = nil
        sleepAtEndOfSong = false
        sleepSongsRemaining = nil
    }

    func dismissPlayback() {
        discardPlayer()
        sleepAtEndOfSong = false
        sleepSongsRemaining = nil
        cancelSleepTimer()
        queue = []
        originalQueue = []
        index = 0
        duration = 0
        lastError = nil
        showFullPlayer = false
        saveQueue()
        updateNowPlaying()
    }

    private func stopForSleep() {
        cancelSleepTimer()
        guard PlaybackPrefs.shared.sleepFadeOut, let player = avPlayer, isPlaying else {
            avPlayer?.pause()
            isPlaying = false
            updateNowPlaying()
            return
        }
        let startVolume = player.volume
        let steps = 25
        let interval = 5.0 / Double(steps)
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(step)) { [weak self] in
                guard let self, let player = self.avPlayer else { return }
                player.volume = startVolume * Float(1 - Double(step) / Double(steps))
                guard step == steps else { return }
                player.pause()
                player.volume = startVolume
                self.isPlaying = false
                self.updateNowPlaying()
            }
        }
    }

    func prev() {
        if currentTime > 3 || index == 0 {
            seek(to: 0)
        } else {
            repeatCurrentSong(times: 0)
            index -= 1
            loadCurrent()
        }
    }

    private func allowLiveRestart(_ videoId: String) -> Bool {
        let now = Date()
        if let last = liveRestartedAt[videoId], now.timeIntervalSince(last) <= 30 { return false }
        liveRestartedAt[videoId] = now
        return true
    }

    func repeatCurrentSong(times: Int) {
        guard times > 0 else {
            if repeatTimesLeft > 0 { repeatMode = repeatModeBeforeCount }
            repeatTimesLeft = 0
            return
        }
        if repeatTimesLeft == 0 { repeatModeBeforeCount = repeatMode }
        repeatTimesLeft = times
        repeatMode = .one
    }

    private func countRepeat() {
        guard repeatTimesLeft > 0 else { return }
        repeatTimesLeft -= 1
        if repeatTimesLeft == 0 { repeatMode = repeatModeBeforeCount }
    }

    private func warmVideoArt(for track: Track) {
        guard UserDefaults.standard.string(forKey: "playerDesign") == "video" else { return }
        let unmetered = Reachability.shared.isUnmetered
        guard unmetered || PlaybackPrefs.shared.videoOnMobile else { return }
        let height = unmetered ? 480 : 360

        guard !LocalMusic.isLocal(track.videoId), !track.videoId.isEmpty else { return }

        Task.detached { [weak self] in
            guard let found = await SongVideos.shared.forSong(track, maxHeight: height) else { return }
            await self?.waitUntilSongComfortable(upTo: 4)
            await MainActor.run { VideoArtPlayers.shared.prepare(found) }
        }

        if let next = queue.indices.contains(index + 1) ? queue[index + 1] : nil,
           !LocalMusic.isLocal(next.videoId), !next.videoId.isEmpty {
            Task.detached { _ = await SongVideos.shared.forSong(next, maxHeight: height) }
        }
    }

    private func refreshSponsorSegments(for videoId: String) {
        sponsorTask?.cancel()
        sponsorSegments = []
        sponsorSkipped = 0
        lastSponsorSkip = nil
        guard PlaybackPrefs.shared.sponsorBlock,
              !LocalMusic.isLocal(videoId),
              !YouTube.isLive(videoId)
        else { return }
        let categories = Set(PlaybackPrefs.shared.sponsorCategories
            .compactMap(SponsorBlock.Category.init(rawValue:)))
        guard !categories.isEmpty else { return }

        sponsorTask = Task { [weak self] in
            let found = await SponsorBlock.segments(videoId: videoId, categories: categories)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.current?.videoId == videoId else { return }
                self.sponsorSegments = found
            }
        }
    }

    private func considerSponsorSkip() {
        guard !sponsorSegments.isEmpty, isPlaying, !isSeeking else { return }
        guard let segment = SponsorBlock.segment(in: sponsorSegments, at: currentTime) else { return }
        if let last = lastSponsorSkip, last.end == segment.end,
           Date().timeIntervalSince(last.at) < 2 { return }
        lastSponsorSkip = (segment.end, Date())
        sponsorSkipped += segment.end - currentTime
        seekSilently(to: segment.end)
    }

    private func considerStuckAtEnd() {
        guard duration > 0, !crossfading, !endHandled else {
            stuckSince = nil
            return
        }
        guard currentTime >= duration - 1.0 else {
            stuckSince = nil
            lastTickTime = currentTime
            return
        }
        if abs(currentTime - lastTickTime) > 0.05 {
            lastTickTime = currentTime
            stuckSince = Date()
            return
        }
        guard let since = stuckSince else {
            stuckSince = Date()
            return
        }
        if Date().timeIntervalSince(since) >= 2 {
            stuckSince = nil
            trackEnded()
        }
    }

    private var lastTickTime: Double = 0
    private var stuckSince: Date?

    private func trackEnded() {
        guard !crossfading, !endHandled else { return }
        endHandled = true
        if sleepAtEndOfSong {
            sleepAtEndOfSong = false
            stopForSleep()
            return
        }
        if let left = sleepSongsRemaining {
            let next = left - 1
            if next <= 0 {
                sleepSongsRemaining = nil
                stopForSleep()
                return
            }
            sleepSongsRemaining = next
        }
        if let id = current?.videoId, liveBroadcasts.contains(id), allowLiveRestart(id) {
            endHandled = false
            loadCurrent()
            return
        }

        if repeatMode == .one {
            countRepeat()
            endHandled = false
            seek(to: 0)
            avPlayer?.play()
            isPlaying = true
            updateNowPlaying()
            return
        }
        if adoptPreparedPlayer() { return }

        if !next(auto: true) {
            if PlaybackPrefs.shared.autoplay, PlaybackPrefs.shared.autoRadioQueue,
               let last = current, !last.videoId.isEmpty {
                extendWithRadio(from: last)
                return
            }
            avPlayer?.pause()
            isPlaying = false
            currentTime = duration
            updateNowPlaying()
        }
    }

    func startRadio(from track: Track) {
        guard !LocalMusic.isLocal(track.videoId), !track.videoId.isEmpty else { return }
        play([track], startAt: 0)
        Task { @MainActor in
            let shelves = await YouTube.related(videoId: track.videoId)
            let fresh = shelves
                .flatMap(\.items)
                .filter { $0.browseId == nil }
                .map(\.asTrack)
                .filter { !$0.videoId.isEmpty && $0.videoId != track.videoId }
            guard !fresh.isEmpty, self.current?.videoId == track.videoId else { return }
            self.queue.append(contentsOf: fresh)
            self.originalQueue = self.queue
            self.saveQueue()
        }
    }

    private func extendWithRadio(from track: Track) {
        guard !LocalMusic.isLocal(track.videoId) else { return }
        isLoading = true
        Task { @MainActor in
            let shelves = await YouTube.related(videoId: track.videoId)
            let known = Set(self.queue.map(\.videoId))
            let fresh = shelves
                .flatMap(\.items)
                .filter { $0.browseId == nil }
                .map(\.asTrack)
                .filter { !$0.videoId.isEmpty && !known.contains($0.videoId) }
            guard !fresh.isEmpty else {
                self.isLoading = false
                self.avPlayer?.pause()
                self.isPlaying = false
                self.currentTime = self.duration
                self.updateNowPlaying()
                return
            }
            self.queue.append(contentsOf: fresh)
            self.endHandled = false
            _ = self.next(auto: true)
        }
    }

    // MARK: - Load / stream

    private func loadCurrent() {
        guard let track = current else { return }
        pendingPlayNextIds.removeAll { $0 == track.videoId }
        if !crossfading { cancelCrossfade() }
        discardPrepared()
        if !crossfading { avPlayer?.pause() }
        currentTime = 0
        duration = track.duration
        VideoArtLog.note("load: \(track.title) from nothing, at 0 of \(Int(duration))s")
        saveQueue()
        isLoading = true
        endHandled = false
        lastError = nil
        artwork = nil
        artworkImage = nil
        artColor = Lunara.green
        loadArtwork(track.thumbnailURL)
        updateNowPlaying()

        let videoId = track.videoId
        countPlay(track)
        refreshSponsorSegments(for: videoId)
        warmVideoArt(for: track)

        if let own = LocalMusic.shared.localAudioURL(for: videoId) {
            let dur = LocalMusic.shared.duration(for: videoId) ?? track.duration
            duration = dur
            isLoading = false
            playStream(own, realDuration: dur, resumeAt: 0)
            warmLyrics(for: track, duration: dur)
            prefetchNext()
            return
        }
        if let local = Downloads.shared.localAudioURL(for: videoId) {
            let dur = Downloads.shared.duration(for: videoId) ?? track.duration
            duration = dur
            isLoading = false
            playStream(local, realDuration: dur, resumeAt: 0)
            warmLyrics(for: track, duration: dur)
            prefetchNext()
            return
        }
        if let cached = AudioCache.shared.cachedURL(for: videoId), track.duration > 0 {
            duration = track.duration
            isLoading = false
            playStream(cached, realDuration: track.duration, resumeAt: 0)
            warmLyrics(for: track, duration: track.duration)
            prefetchNext()
            return
        }

        Task {
            let stream = await YouTube.streamURL(for: videoId)
            await MainActor.run {
                guard self.current?.videoId == videoId else { return }
                guard let stream else {
                    self.discardPlayer()
                    self.songFailed("Couldn't load this track. Try again.", auto: true)
                    return
                }
                self.currentTime = 0
                self.duration = stream.duration
                if YouTube.isLive(videoId) {
                    self.liveBroadcasts.insert(videoId)
                    self.playStream(stream.url, realDuration: 0, resumeAt: 0)
                    return
                }
                self.liveBroadcasts.remove(videoId)
                self.playStream(stream.url, realDuration: stream.duration, resumeAt: 0)
                let cacheable = Track(videoId: track.videoId, title: track.title,
                                      artist: track.artist, thumbnail: track.thumbnail,
                                      duration: stream.duration, artistId: track.artistId)
                AudioCache.shared.cache(cacheable)
                self.warmLyrics(for: track, duration: stream.duration)
                self.prefetchNext()
            }
        }
    }

    private func prefetchNext() {
        let n = index + 1
        guard queue.indices.contains(n) else { return }
        let next = queue[n]
        let vid = next.videoId
        Task.detached { _ = await YouTube.streamURL(for: vid) }
        Task.detached {
            await LyricsCache.shared.warm(videoId: vid, title: next.title,
                                          artist: next.artist, duration: next.duration)
        }
        Task.detached { await ImageCache.prefetch(next.artURL(size: 1080)) }
    }

    private func warmLyrics(for track: Track, duration: Double) {
        let vid = track.videoId
        guard !vid.isEmpty else { return }
        Task.detached {
            await LyricsCache.shared.warm(videoId: vid, title: track.title,
                                          artist: track.artist, duration: duration)
        }
    }

    private var reopenCount = 0
    private var reopenFor: String?

    private var failedInARow = 0
    private var lastFreshStart = Date.distantPast
    private var backgroundedAt: Date?

    private func songFailed(_ message: String, auto: Bool) {
        isLoading = false
        lastError = message
        failedInARow += 1
        VideoArtLog.note("song failed (\(failedInARow) in a row): \(current?.title ?? "?") — \(message)")
        if Date().timeIntervalSince(lastFreshStart) > 60 {
            freshStart()
            loadCurrent()
            return
        }
        if failedInARow >= 4 {
            discardPlayer()
            lastError = "Nothing would play. Check your connection, then try again."
            return
        }
        guard PlaybackPrefs.shared.autoSkipOnError else { return }
        if auto {
            guard index + 1 < queue.count else { return }
            _ = next(auto: true)
        } else {
            _ = next()
        }
    }

    private func freshStart() {
        lastFreshStart = Date()
        YouTube.freshStart()
        configureSession()
    }

    private func mediaServicesWereReset() {
        VideoArtLog.note("media services were reset: session and players rebuilt")
        let position = currentTime
        let wasPlaying = isPlaying
        configureSession()
        cancelCrossfade()
        discardPrepared()
        discardPlayer()
        guard let track = current else { return }
        resumeVideoId = track.videoId
        resumePosition = position
        currentTime = position
        guard wasPlaying else { return }
        playWhenReady = true
        loadCurrent()
    }

    @discardableResult
    private func reopen() -> Bool {
        guard let track = current else { return false }
        if reopenFor != track.videoId {
            reopenFor = track.videoId
            reopenCount = 0
        }
        guard reopenCount < 3 else { return false }
        reopenCount += 1

        let resumeFrom = avPlayer?.currentTime().seconds ?? 0
        let videoId = track.videoId

        Task {
            guard let fresh = await YouTube.streamURL(for: videoId) else {
                await MainActor.run {
                    guard self.current?.videoId == videoId else { return }
                    self.songFailed("Couldn't load this track. Try again.", auto: false)
                }
                return
            }
            await MainActor.run {
                guard self.current?.videoId == videoId else { return }
                self.playStream(fresh.url, realDuration: fresh.duration, resumeAt: resumeFrom)
            }
        }
        return true
    }

    private func playStream(_ url: URL, realDuration: Double, resumeAt: Double = 0) {
        removeTimeObserver()
        statusObs = nil

        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: YouTube.visionUA])
        let item = AVPlayerItem(asset: asset)

        Task { @MainActor [weak item] in
            guard let mix = await EqualizerTap.audioMix(for: asset) else { return }
            item?.audioMix = mix
        }
        if realDuration > 0 {
            item.forwardPlaybackEndTime = CMTime(seconds: realDuration, preferredTimescale: 600)
        }
        statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.failedInARow = 0
                case .failed:
                    let e = item.error as NSError?
                    let under = e?.userInfo[NSUnderlyingErrorKey] as? NSError
                    let http = item.errorLog()?.events.last.map { " HTTP \($0.errorStatusCode)" } ?? ""
                    VideoArtLog.note("audio item failed: \(e?.domain ?? "?") \(e?.code ?? 0)"
                        + (under.map { " / \($0.domain) \($0.code)" } ?? "") + http)
                    if let url = (item.asset as? AVURLAsset)?.url { YouTube.streamFailed(url) }
                    if self.reopen() { return }
                    self.songFailed(item.error?.localizedDescription ?? "Playback failed", auto: false)
                default: break
                }
            }
        }

        let watched = item
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard let self, self.avPlayer?.currentItem === watched,
                  watched.status != .readyToPlay, self.currentTime < 1
            else { return }
            self.isLoading = false
            let reason = watched.error?.localizedDescription
                ?? "the stream never became ready"
            self.lastError = "This track wouldn't start — \(reason). "
                + "Long recordings are known to do this; please report it."
        }

        item.audioTimePitchAlgorithm = PlaybackPrefs.shared.preservePitch
            ? .timeDomain : .varispeed

        let p = AVPlayer(playerItem: item)
        avPlayer = p
        if resumeAt > 1 {
            p.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600),
                   toleranceBefore: .zero, toleranceAfter: .zero)
        }
        applyAudioPrefs()
        attachObservers(to: p)
        let target = current?.videoId == resumeVideoId ? resumePosition : 0
        resumePosition = 0
        resumeVideoId = nil
        if target > 1, realDuration > target {
            let wanted = playWhenReady
            playWhenReady = false
            p.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
                guard let self else { return }
                self.currentTime = target
                guard wanted else { return }
                self.configureSession()
                p.play()
                p.rate = Float(PlaybackPrefs.shared.speed)
            }
            isPlaying = wanted
            updateNowPlaying()
            return
        }
        playWhenReady = false
        if paused {
            isPlaying = false
            updateNowPlaying()
            return
        }
        configureSession()
        p.play()
        p.rate = Float(PlaybackPrefs.shared.speed)
        isPlaying = true
        updateNowPlaying()
    }

    // MARK: - Gapless

    private func considerGapless() {
        let prefs = PlaybackPrefs.shared
        guard !crossfading, isPlaying, repeatMode != .one, duration > 0 else { return }
        let next = index + 1
        guard queue.indices.contains(next), preparedIndex != next else { return }
        let remaining = duration - currentTime
        guard remaining <= 10 || bufferedAhead >= 20 || bufferedAhead >= remaining - 1 else { return }
        if prefs.crossfade, remaining <= prefs.crossfadeDuration + 1 { return }

        preparedIndex = next
        preparedVideoId = queue[next].videoId
        let track = queue[next]
        Task { @MainActor in
            guard let resolved = await self.resolved(for: track),
                  self.preparedIndex == next, self.preparedVideoId == track.videoId else { return }
            let asset = AVURLAsset(url: resolved.url,
                                   options: [AVURLAssetHTTPUserAgentKey: YouTube.visionUA])
            let item = AVPlayerItem(asset: asset)
            if resolved.duration > 0 {
                item.forwardPlaybackEndTime = CMTime(seconds: resolved.duration,
                                                     preferredTimescale: 600)
            }
            item.audioTimePitchAlgorithm = PlaybackPrefs.shared.preservePitch
                ? .timeDomain : .varispeed
            Task { @MainActor [weak item] in
                guard let mix = await EqualizerTap.audioMix(for: asset) else { return }
                item?.audioMix = mix
            }
            item.preferredForwardBufferDuration = 30
            let player = AVPlayer(playerItem: item)
            player.volume = self.avPlayer?.volume ?? 1
            player.pause()
            self.preparedPlayer = player
            self.preparedDuration = resolved.duration
        }
    }

    private func adoptPreparedPlayer(byHand: Bool = false) -> Bool {
        guard byHand || (PlaybackPrefs.shared.gapless && !PlaybackPrefs.shared.crossfade),
              let prepared = preparedPlayer,
              let target = preparedIndex,
              target == index + 1, queue.indices.contains(target),
              queue[target].videoId == preparedVideoId,
              prepared.currentItem?.status != .failed
        else { return false }

        if !crossfading { cancelCrossfade() }
        avPlayer?.pause()
        removeTimeObserver()
        statusObs = nil
        rateObs = nil

        preparedPlayer = nil
        preparedIndex = nil
        preparedVideoId = nil
        currentTime = 0
        duration = preparedDuration > 0 ? preparedDuration : queue[target].duration
        avPlayer = prepared
        index = target
        prepared.play()
        prepared.rate = Float(PlaybackPrefs.shared.speed)
        adoptPlayingTrack(realDuration: preparedDuration)
        preparedDuration = 0
        VideoArtLog.note("skip: handed over to \(queue[target].title) at 0 of \(Int(duration))s")
        return true
    }

    private func discardPrepared() {
        preparedPlayer?.pause()
        preparedPlayer = nil
        preparedIndex = nil
        preparedVideoId = nil
        preparedDuration = 0
    }

    // MARK: - Crossfade

    private func considerCrossfade() {
        let prefs = PlaybackPrefs.shared
        guard prefs.crossfade, !crossfading, isPlaying,
              repeatMode != .one, duration > 0,
              queue.indices.contains(index + 1)
        else { return }
        let window = prefs.crossfadeDuration
        guard duration - currentTime <= window, duration - currentTime > 0.2 else { return }

        crossfading = true
        let upcoming = queue[index + 1]
        Task { @MainActor in
            guard let resolved = await self.resolved(for: upcoming) else {
                self.crossfading = false
                return
            }
            self.startCrossfade(to: resolved.url, over: window,
                                realDuration: resolved.duration)
        }
    }

    private func resolved(for track: Track) async -> (url: URL, duration: Double)? {
        if let own = LocalMusic.shared.localAudioURL(for: track.videoId) {
            return (own, LocalMusic.shared.duration(for: track.videoId) ?? track.duration)
        }
        if let local = Downloads.shared.localAudioURL(for: track.videoId) {
            return (local, Downloads.shared.duration(for: track.videoId) ?? track.duration)
        }
        if let cached = AudioCache.shared.cachedURL(for: track.videoId) {
            return (cached, track.duration)
        }
        guard let stream = await YouTube.streamURL(for: track.videoId) else { return nil }
        return (stream.url, stream.duration)
    }

    private func startCrossfade(to url: URL, over seconds: Double, realDuration: Double) {
        guard let outgoing = avPlayer else { crossfading = false; return }

        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: YouTube.visionUA])
        let item = AVPlayerItem(asset: asset)
        if realDuration > 0 {
            item.forwardPlaybackEndTime = CMTime(seconds: realDuration, preferredTimescale: 600)
        }
        fadeDuration = realDuration
        let incoming = AVPlayer(playerItem: item)
        incoming.volume = 0
        fadePlayer = incoming
        incoming.play()
        incoming.rate = Float(PlaybackPrefs.shared.speed)

        let startVolume = outgoing.volume
        let steps = max(Int(seconds * 20), 1)
        var step = 0
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: seconds / Double(steps),
                                         repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            step += 1
            let t = Float(min(Double(step) / Double(steps), 1))
            outgoing.volume = startVolume * (1 - t)
            incoming.volume = startVolume * t
            guard step >= steps else { return }
            timer.invalidate()
            self.finishCrossfade(volume: startVolume)
        }
    }

    private func finishCrossfade(volume: Float) {
        fadeTimer?.invalidate()
        fadeTimer = nil
        guard let incoming = fadePlayer, index < queue.count - 1 else {
            cancelCrossfade()
            return
        }

        avPlayer?.pause()
        removeTimeObserver()
        statusObs = nil
        rateObs = nil

        avPlayer = incoming
        incoming.volume = volume
        fadePlayer = nil
        crossfading = false

        index += 1
        adoptPlayingTrack(realDuration: fadeDuration)
        fadeDuration = 0
    }

    private func adoptPlayingTrack(realDuration: Double) {
        guard let track = current, let player = avPlayer else { return }

        pendingPlayNextIds.removeAll { $0 == track.videoId }
        refreshSponsorSegments(for: track.videoId)
        warmVideoArt(for: track)
        if LocalMusic.shared.localAudioURL(for: track.videoId) == nil,
           Downloads.shared.localAudioURL(for: track.videoId) == nil,
           AudioCache.shared.cachedURL(for: track.videoId) == nil {
            AudioCache.shared.cache(Track(videoId: track.videoId, title: track.title,
                                          artist: track.artist, thumbnail: track.thumbnail,
                                          duration: realDuration > 0 ? realDuration : track.duration,
                                          artistId: track.artistId))
        }

        endHandled = false
        isLoading = false
        lastError = nil
        artwork = nil
        artworkImage = nil
        artColor = Lunara.green
        loadArtwork(track.thumbnailURL)

        currentTime = 0
        duration = realDuration > 0 ? realDuration : track.duration
        isPlaying = true

        countPlay(track)
        saveQueue()
        updateNowPlaying()
        warmLyrics(for: track, duration: duration)
        prefetchNext()

        attachObservers(to: player)
    }

    private func attachObservers(to player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main,
        ) { [weak self] time in
            guard let self, player === self.avPlayer, !self.isSeeking, time.isNumeric else { return }
            self.bufferedAhead = Self.bufferedAhead(of: player.currentItem, at: time)
            self.currentTime = time.seconds.isFinite ? time.seconds : 0

            if !self.isCurrentLive, self.duration <= 0, let item = player.currentItem {
                let real = item.duration.seconds
                if real.isFinite, real > 1 {
                    self.duration = real
                }
            }
            self.considerSponsorSkip()
            self.considerCrossfade()
            self.considerGapless()
            self.considerStuckAtEnd()
        }
        rateObs = player.observe(\.timeControlStatus,
                                 options: [.new, .initial]) { [weak self] observed, _ in
            DispatchQueue.main.async {
                guard let self, observed === self.avPlayer else { return }
                let playing = observed.timeControlStatus != .paused
                if self.isPlaying != playing {
                    self.isPlaying = playing
                    self.updateNowPlaying()
                }
            }
        }
    }

    private func cancelCrossfade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        fadePlayer?.pause()
        fadePlayer = nil
        crossfading = false
    }

    private var currentLoudnessDb: Double? {
        current.flatMap { YouTube.loudnessDb(for: $0.videoId) }
    }

    func applyAudioPrefs() {
        let prefs = PlaybackPrefs.shared
        avPlayer?.currentItem?.audioTimePitchAlgorithm =
            prefs.preservePitch ? .timeDomain : .varispeed
        if isPlaying { avPlayer?.rate = Float(prefs.speed) }
        if prefs.normalizeVolume, let loudness = currentLoudnessDb {
            let trim = prefs.loudnessTarget - loudness
            avPlayer?.volume = Float(pow(10, min(trim, 0) / 20))
        } else {
            avPlayer?.volume = 1
        }
    }

    func toggle() {
        guard let avPlayer else {
            if hasTrack {
                playWhenReady = true
                loadCurrent()
            }
            return
        }
        if isPlaying {
            avPlayer.pause()
        } else {
            avPlayer.play()
            avPlayer.rate = Float(PlaybackPrefs.shared.speed)
        }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func seek(by delta: Double) {
        guard duration > 0 else { return }
        let target = min(max(currentTime + delta, 0), max(duration - 0.5, 0))
        seek(to: target / duration)
    }

    func seek(to fraction: Double) {
        guard duration > 0, let avPlayer else { return }
        let target = fraction * duration
        isSeeking = true
        currentTime = target
        updateNowPlaying()
        avPlayer.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero,
        ) { [weak self] _ in
            self?.isSeeking = false
        }
    }

    // MARK: - Session / remote / now-playing

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.skipBackwardCommand.isEnabled = false
        c.skipForwardCommand.isEnabled = false
        c.nextTrackCommand.isEnabled = true
        c.previousTrackCommand.isEnabled = true
        c.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.prev(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard
                let self,
                let e = event as? MPChangePlaybackPositionCommandEvent,
                self.duration > 0
            else { return .commandFailed }
            self.seek(to: e.positionTime / self.duration)
            return .success
        }
    }

    private func resume() {
        guard let avPlayer else {
            if hasTrack {
                failedInARow = 0
                playWhenReady = true
                loadCurrent()
            }
            return
        }
        configureSession()
        avPlayer.play()
        isPlaying = true
        updateNowPlaying()
    }
    private func pause() { avPlayer?.pause(); isPlaying = false; updateNowPlaying() }

    private func loadArtwork(_ url: URL?) {
        guard let url else { return }
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return }
            artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            artworkImage = img
            artColor = img.gradientSeed
            AppTheme.shared.setArtworkSeed(img.gradientSeed)
            updateNowPlaying()
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let img = UIImage(data: data) else { return }
            let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            let seed = img.gradientSeed
            DispatchQueue.main.async {
                self.artwork = art
                self.artworkImage = img
                self.artColor = seed
                AppTheme.shared.setArtworkSeed(seed)
                self.updateNowPlaying()
            }
        }.resume()
    }

    private func updateNowPlaying() {
        guard let track = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist.isEmpty ? "Lunara" : track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func discardPlayer() {
        removeTimeObserver()
        statusObs = nil
        rateObs = nil
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayer = nil
        isPlaying = false
        currentTime = 0
        updateNowPlaying()
    }

    private func removeTimeObserver() {
        if let timeObserver { avPlayer?.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }
}

final class PlaybackClock: ObservableObject {
    @Published var currentTime = 0.0
}
