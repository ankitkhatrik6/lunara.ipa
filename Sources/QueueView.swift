import SwiftUI

struct QueueView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    @AppStorage("queueEditLocked") private var locked = true

    @State private var showSave = false
    @State private var playlistName = ""
    @State private var saving = false
    @State private var notice: String?

    private var summary: String {
        let count = player.queue.count
        let songs = count == 1 ? String(localized: "1 song") : String(localized: "\(count) songs")
        let total = player.queue.reduce(0) { $0 + max($1.duration, 0) }
        guard total > 0 else { return songs }
        return songs + " · " + timeString(total)
    }

    private func subtitle(for track: Track) -> String {
        let length = track.duration > 0 ? timeString(track.duration) : ""
        return [track.artist, length].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { rows in
            List {
                Section {
                    EmptyView()
                } header: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Playing next")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(palette.onSurface)
                            Text(summary)
                                .font(.lunara(13))
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                        lockKey
                    }
                    .textCase(nil)
                    .padding(.bottom, 8)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
                }

                ForEach(Array(player.queue.enumerated()), id: \.element.id) { pair in
                    let active = pair.offset == player.index
                    HStack(spacing: 0) {
                        Button {
                            player.jump(to: pair.offset)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                RemoteImage(url: pair.element.artURL(size: 160), size: 52) {
                                    palette.onSurface.opacity(0.10)
                                }
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    if active {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(.black.opacity(0.45))
                                            .overlay {
                                                if player.isPlaying {
                                                    PlayingBars()
                                                } else {
                                                    Image(systemName: "play.fill")
                                                        .font(.system(size: 16, weight: .bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pair.element.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(palette.onSurface)
                                        .lineLimit(1)
                                    Text(subtitle(for: pair.element))
                                        .font(.system(size: 13))
                                        .foregroundStyle(palette.onSurfaceVariant)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        QueueRowMenu(track: pair.element, player: player,
                                     position: pair.offset)
                    }
                    .listRowBackground(active ? palette.onSurface.opacity(0.10) : nil)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            player.removeFromQueue(at: pair.offset)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            player.moveToPlayNext(from: pair.offset)
                        } label: {
                            Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        .tint(Lunara.green)
                    }
                }
                .onMove { from, to in player.moveInQueue(from: from, to: to) }
            }
            .environment(\.editMode, .constant(locked ? .inactive : .active))
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !player.queue.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { playlistName = ""; showSave = true } label: {
                            Image(systemName: "text.badge.plus")
                        }
                        .tint(palette.accent)
                        .accessibilityLabel("Save queue as a playlist")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(palette.accent)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomKeys
            }
            .overlay(alignment: .bottom) {
                if let notice {
                    Text(notice)
                        .font(.lunara(13, .semibold))
                        .foregroundStyle(palette.onSurface)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(palette.surfaceHigh)
                        .clipShape(Capsule())
                        .padding(.bottom, 28)
                        .transition(.opacity)
                }
            }
            .alert("Save queue as a playlist", isPresented: $showSave) {
                TextField("Name", text: $playlistName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { save() }
            } message: {
                Text("Creates a new playlist on this device with everything in the queue.")
            }
            .onAppear { jump(using: rows, animated: false) }
            .onChange(of: player.index) { jump(using: rows, animated: true) }
            }
        }
    }

    private func jump(using rows: ScrollViewProxy, animated: Bool) {
        guard player.queue.indices.contains(player.index) else { return }
        let id = player.queue[player.index].id
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0 : 0.05)) {
            if animated {
                withAnimation(.easeInOut(duration: 0.25)) { rows.scrollTo(id, anchor: .center) }
            } else {
                rows.scrollTo(id, anchor: .center)
            }
        }
    }

    private var lockKey: some View {
        Button {
            locked.toggle()
        } label: {
            Image(systemName: locked ? "lock" : "lock.open")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(locked ? palette.onSurfaceVariant : Lunara.green)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(locked
                        ? palette.onSurface.opacity(0.08)
                        : Lunara.green.opacity(0.18)),
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? "Queue locked" : "Queue unlocked")
        .accessibilityHint("Unlock to drag songs into a different order")
    }

    private var bottomKeys: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [palette.scaffold.opacity(0), palette.scaffold],
                startPoint: .top, endPoint: .bottom,
            )
            .frame(height: 26)
            .allowsHitTesting(false)

            HStack(spacing: 0) {
                key(player.isShuffled ? "shuffle.circle.fill" : "shuffle", "Shuffle",
                    on: player.isShuffled) { player.toggleShuffle() }
                key("chevron.down", "Close", on: false) { dismiss() }
                key(player.repeatMode == .one ? "repeat.1" : "repeat", "Repeat",
                    on: player.repeatMode != .off) { player.cycleRepeat() }
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
            .background(palette.scaffold)
        }
    }

    private func key(_ icon: String, _ title: String, on: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19))
                Text(title).font(.system(size: 11)).lineLimit(1)
            }
            .foregroundStyle(on ? palette.accent : palette.onSurface.opacity(0.85))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !player.queue.isEmpty else { return }
        let saved = LocalPlaylistStore.shared.create(title: name, tracks: player.queue)
        show(String(localized: "Saved \(saved.tracks.count) songs to \(saved.title)"))
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation { notice = nil }
        }
    }
}

private struct QueueRowMenu: View {
    @Environment(\.palette) private var palette
    let track: Track
    @ObservedObject var player: Player
    let position: Int

    @State private var playlistTrack: Track?

    var body: some View {
        Menu {
            Button {
                player.removeFromQueue(at: position)
                player.playNext(track)
            } label: {
                Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                player.setFavorite(track, liked: !player.favorites.contains(track.videoId))
            } label: {
                Label(player.favorites.contains(track.videoId)
                      ? "Remove from favourites" : "Add to favourites",
                      systemImage: player.favorites.contains(track.videoId) ? "heart.slash" : "heart")
            }
            Button { playlistTrack = track } label: {
                Label("Add to playlist", systemImage: "plus.circle")
            }
            if Downloads.shared.state(track.videoId) == .downloading {
                Button { Downloads.shared.cancel(track.videoId) } label: {
                    Label("Stop downloading", systemImage: "xmark.circle")
                }
            } else {
                Button { Downloads.shared.download(track) } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
            Divider()
            Button(role: .destructive) {
                player.removeFromQueue(at: position)
            } label: {
                Label("Remove from queue", systemImage: "minus.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.lunara(15))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .sheet(item: $playlistTrack) { AddToPlaylistSheet(track: $0) }
    }
}
