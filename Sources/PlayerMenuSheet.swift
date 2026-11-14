import SwiftUI
import UIKit

struct PlayerMenuSheet: View {
    @ObservedObject var player: Player
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var dial = SpeedDial.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAddToPlaylist = false
    @State private var showRepeatTimes = false
    @State private var showSpeed = false
    @ObservedObject private var playback = PlaybackPrefs.shared
    @State private var artist: ArtistRoute?
    @State private var copied = false

    var onQueue: () -> Void
    var onSleep: () -> Void
    var onLyrics: () -> Void
    var onLyricsSettings: () -> Void
    var onLyricsTiming: () -> Void
    var onEqualizer: () -> Void

    private var downloadState: DownloadState { downloads.state(player.current?.videoId ?? "") }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                RemoteImage(url: player.current?.artURL(size: 300), size: 52) { ArtPlaceholder() }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.current?.title ?? "")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(player.current?.artist ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider().overlay(Color.white.opacity(0.1))

            ScrollView {
                VStack(spacing: 0) {
                    actionRow
                    Divider().overlay(Color.white.opacity(0.1)).padding(.vertical, 4)

                    row(player.repeatTimesLeft > 0 ? "repeat.1.circle.fill" : "repeat.1",
                        player.repeatTimesLeft > 0
                            ? String(localized: "\(player.repeatTimesLeft) more to go")
                            : String(localized: "Play this song again"),
                        tint: player.repeatTimesLeft > 0 ? Lunara.green : .white) {
                        showRepeatTimes = true
                    }

                    row(copied ? "checkmark" : "link",
                        copied ? String(localized: "Link copied") : String(localized: "Copy link"),
                        tint: copied ? Lunara.green : .white) { copyLink() }

                    if let track = player.current, !track.artist.isEmpty {
                        let name = leadArtist(track)
                        let blocked = BlockedArtists.shared.isBlocked(id: track.artistId, name: name)
                        row(blocked ? "person.crop.circle.badge.checkmark" : "nosign",
                            blocked ? String(localized: "Unblock \(name)")
                                    : String(localized: "Block \(name)"),
                            tint: blocked ? Lunara.green : .white) {
                            if blocked {
                                BlockedArtists.shared.unblock(id: track.artistId, name: name)
                            } else {
                                BlockedArtists.shared.block(id: track.artistId, name: name)
                            }
                        }
                    }

                    row(player.isCurrentFavorite ? "heart.fill" : "heart",
                        player.isCurrentFavorite
                            ? String(localized: "Remove from library")
                            : String(localized: "Add to library"),
                        tint: player.isCurrentFavorite ? .red : .white) {
                        player.toggleFavorite()
                    }

                    if let track = player.current, !track.videoId.isEmpty {
                        let pinned = dial.isPinned(track.videoId)
                        row(pinned ? "pin.slash" : "pin",
                            pinned ? String(localized: "Unpin from speed dial")
                                   : String(localized: "Pin to speed dial"),
                            tint: pinned ? Lunara.green : .white) {
                            dial.toggle(track)
                        }
                    }

                    row("slider.horizontal.3", "Equaliser") { dismiss(); onEqualizer() }

                    row("gauge.with.dots.needle.67percent",
                        playback.speed == 1 ? String(localized: "Speed and pitch")
                            : String(localized: "Speed and pitch (\(SpeedSheet.label(playback.speed)))"),
                        tint: playback.speed == 1 ? .white : Lunara.green) { showSpeed = true }

                    if let url = shareURL {
                        ShareLink(item: url) {
                            rowLabel("square.and.arrow.up", "Share", tint: .white)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().overlay(Color.white.opacity(0.1)).padding(.vertical, 4)

                    row("quote.bubble", "Lyrics") { dismiss(); onLyrics() }
                    row("textformat.size", "Lyrics settings") { dismiss(); onLyricsSettings() }
                    row("metronome", "Lyrics timing") { dismiss(); onLyricsTiming() }
                    row("list.bullet", "View queue") { dismiss(); onQueue() }
                    row(player.sleepActive ? "moon.zzz.fill" : "moon.zzz",
                        player.sleepActive ? String(localized: "Sleep timer (on)")
                                           : String(localized: "Sleep timer"),
                        tint: player.sleepActive ? Lunara.green : .white) { dismiss(); onSleep() }
                }
                .padding(.vertical, 6)
            }
        }
        .background(Lunara.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAddToPlaylist) {
            if let track = player.current { AddToPlaylistSheet(track: track) }
        }
        .sheet(isPresented: $showRepeatTimes) {
            RepeatTimesSheet(player: player)
        }
        .sheet(isPresented: $showSpeed) { SpeedSheet() }
        .fullScreenCover(item: $artist) { ArtistView(browseId: $0.browseId, player: player) }
    }

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                action("text.badge.plus", "Add to queue") {
                    if let t = player.current { player.addToQueue([t]) }
                    dismiss()
                }
                action("plus.circle", "Add to playlist") { showAddToPlaylist = true }
                if downloadState == .downloading {
                    stopDownloadAction
                } else {
                    action(downloadState == .done ? "arrow.down.circle.fill" : "arrow.down.circle",
                           downloadState == .done ? "Downloaded" : "Download",
                           tint: downloadState == .done ? Lunara.green : .white,
                           disabled: player.isCurrentLive) {
                        if let t = player.current { downloads.toggle(t) }
                    }
                }
                action("person", "Artist") { openArtist() }
                action("dot.radiowaves.left.and.right", "Start radio") {
                    if let t = player.current { player.startRadio(from: t) }
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 4)
    }

    private func action(_ icon: String, _ title: String, tint: Color = .white,
                        disabled: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .frame(height: 28)
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(disabled ? Color.white.opacity(0.35) : tint)
            .frame(width: 108)
            .padding(.vertical, 12)
            .background(Color.white.opacity(disabled ? 0.04 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var stopDownloadAction: some View {
        Button {
            if let id = player.current?.videoId { downloads.cancel(id) }
        } label: {
            VStack(spacing: 6) {
                LunaraDownloadLoader(size: 28, tint: Lunara.green)
                    .frame(height: 28)
                Text("Stop download")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Color.white)
            .frame(width: 108)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Downloading. Tap to stop")
    }

    private func leadArtist(_ track: Track) -> String {
        track.artist
            .components(separatedBy: CharacterSet(charactersIn: ",&"))
            .first?.trimmingCharacters(in: .whitespaces) ?? track.artist
    }

    private func openArtist() {
        guard let track = player.current else { return }
        if let id = track.artistId, !id.isEmpty {
            artist = ArtistRoute(browseId: id)
            return
        }
        Task {
            let found = await YouTube.resolveArtistId(name: track.artist)
            await MainActor.run {
                artist = found.map(ArtistRoute.init)
            }
        }
    }

    private func copyLink() {
        guard let url = shareURL else { return }
        UIPasteboard.general.string = url.absoluteString
        withAnimation { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copied = false }
        }
    }

    private func row(_ icon: String, _ title: String, tint: Color = .white,
                     disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(icon, title, tint: tint) }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
    }

    private func rowLabel(_ icon: String, _ title: String, tint: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(tint)
                .frame(width: 26)
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }

    private var shareURL: URL? {
        guard let id = player.current?.videoId else { return nil }
        return URL(string: "https://music.youtube.com/watch?v=\(id)")
    }
}

struct RepeatTimesSheet: View {
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    private let choices = [1, 2, 3, 5, 10]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "repeat.1")
                    .font(.system(size: 22))
                    .foregroundStyle(Lunara.green)
                Text("How many more times?")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 8)

            Text("The song plays that many more times, then the queue carries on.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ForEach(choices, id: \.self) { times in
                Button {
                    player.repeatCurrentSong(times: times)
                    dismiss()
                } label: {
                    HStack {
                        Text(times == 1 ? String(localized: "1 time")
                                        : String(localized: "\(times) times"))
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                        if player.repeatTimesLeft == times {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Lunara.green)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if player.repeatTimesLeft > 0 {
                Button {
                    player.repeatCurrentSong(times: 0)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Stop repeating")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Lunara.surface.ignoresSafeArea())
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

struct SpeedSheet: View {
    @ObservedObject private var prefs = PlaybackPrefs.shared

    private let presets: [Double] = [0.75, 1, 1.25, 1.5, 2]

    static func label(_ speed: Double) -> String {
        let rounded = (speed * 100).rounded() / 100
        return rounded.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 22))
                    .foregroundStyle(Lunara.green)
                Text("Speed and pitch")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(Self.label(prefs.speed))
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Lunara.green)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 12)

            Slider(value: $prefs.speed, in: PlaybackPrefs.speedRange, step: 0.05)
                .tint(Lunara.green)
                .padding(.horizontal, 20)

            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { speed in
                    let chosen = abs(prefs.speed - speed) < 0.001
                    Button { prefs.speed = speed } label: {
                        Text(Self.label(speed))
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(chosen ? Color.black : Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(chosen ? Lunara.green : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Toggle(isOn: $prefs.preservePitch) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep pitch")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                    Text("Stop voices rising as the speed goes up")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .tint(Lunara.green)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Lunara.surface.ignoresSafeArea())
        .presentationDetents([.height(300)])
        .preferredColorScheme(.dark)
    }
}
