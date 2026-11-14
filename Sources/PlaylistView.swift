import SwiftUI

struct PlaylistView: View {
    @Environment(\.palette) private var palette
    let item: HomeItem
    @ObservedObject var player: Player
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var localPlaylists = LocalPlaylistStore.shared
    @ObservedObject private var dial = SpeedDial.shared

    @State private var saved = false
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var editing = false
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false
    @State private var confirmStopDownload = false
    @State private var notice: String?
    @Environment(\.dismiss) private var dismiss

    private var isLocalPlaylist: Bool {
        LocalPlaylistStore.isLocal(item.browseId)
    }

    private var localModel: LocalPlaylist? {
        guard let id = item.browseId, isLocalPlaylist else { return nil }
        return localPlaylists.playlist(id: id)
    }

    private var displayTitle: String {
        localModel?.title ?? item.title
    }

    private var displaySubtitle: String {
        localModel?.subtitle ?? item.subtitle
    }

    private var displayThumbnailURL: URL? {
        if let thumb = localModel?.thumbnail, !thumb.isEmpty, let url = URL(string: thumb) {
            return url
        }
        return item.thumbnailURL
    }

    private var currentHomeItem: HomeItem {
        localModel?.asHomeItem ?? item
    }

    private var isEditable: Bool {
        isLocalPlaylist
    }

    private var downloadLabel: String {
        guard !tracks.isEmpty else { return "Download" }
        let done = tracks.filter { downloads.isDownloaded($0.videoId) }.count
        if done == tracks.count { return "Downloaded" }
        if done > 0 { return "\(done)/\(tracks.count)" }
        return "Download"
    }

    var body: some View {
        ScrollViewReader { scroller in
        ScrollView {
            VStack(spacing: 16) {
                RemoteImage(url: displayThumbnailURL, size: 220) {
                    palette.onSurface.opacity(0.06)
                        .overlay(Image(systemName: "music.note.list")
                            .font(.lunara(48))
                            .foregroundStyle(palette.onSurface.opacity(0.35)))
                }
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 12)
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text(displayTitle)
                        .font(.lunara(22, .bold))
                        .foregroundStyle(palette.onSurface)
                        .multilineTextAlignment(.center)
                    if !displaySubtitle.isEmpty {
                        Text(displaySubtitle)
                            .font(.lunara(14))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)

                if !tracks.isEmpty || isEditable {
                    actionRow
                }

                if loading {
                    SkeletonTrackList(rows: 7).padding(.top, 8)
                } else if tracks.isEmpty {
                    Text(isLocalPlaylist ? "No songs in this playlist yet" : "Nothing to play here")
                        .foregroundStyle(palette.onSurfaceVariant)
                        .padding(.top, 40)
                } else if editing {
                    List {
                        ForEach(tracks) { track in
                            TrackRow(track: track)
                                .listRowBackground(palette.scaffold)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { remove(track) } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { player.playNext(track) } label: {
                                        Label("Play next",
                                              systemImage: "text.line.first.and.arrowtriangle.forward")
                                    }
                                    .tint(Lunara.green)
                                }
                        }
                        .onMove { from, to in move(from: from, to: to) }
                    }
                    .environment(\.editMode, .constant(.active))
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: CGFloat(tracks.count) * 68)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { pair in
                            SongRow(track: pair.element, player: player) {
                                player.play(tracks, startAt: pair.offset)
                            }
                            .id(pair.element.videoId)
                            .padding(.leading, 16)
                            .padding(.vertical, 6)
                            .buttonStyle(.plain)
                            .swipeToPlayNext(pair.element, player: player)
                        }
                    }
                }
            }
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename playlist", isPresented: $renaming) {
            TextField("Name", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") { rename() }
        }
        .alert("Delete this playlist?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deletePlaylist() }
        } message: {
            Text("It will be removed from this device.")
        }
        .alert("Stop downloading?", isPresented: $confirmStopDownload) {
            Button("Keep downloading", role: .cancel) {}
            Button("Stop", role: .destructive) { Downloads.shared.cancelAll(tracks) }
        } message: {
            Text("Songs still waiting or arriving are stopped. Songs that already finished stay on your phone.")
        }
        .alert("Couldn't do that",
               isPresented: Binding(get: { notice != nil },
                                    set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
        .task {
            saved = SavedPlaylists.contains(item.browseId ?? "")
            await load()
        }
        .onChange(of: localPlaylists.playlists) {
            if isLocalPlaylist, let lp = localModel {
                tracks = lp.tracks
            }
        }
        .onChange(of: loading) {
            guard !loading, let id = player.current?.videoId, tracks.contains(where: { $0.videoId == id }) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scroller.scrollTo(id, anchor: .center)
            }
        }
        }
    }

    private var actionRow: some View {
        HStack {
            if !isLocalPlaylist, let id = item.browseId, !id.isEmpty {
                roundButton(saved ? "heart.fill" : "heart",
                            tint: saved ? Lunara.green : nil) { toggleSaved(id) }
            } else {
                Color.clear.frame(width: 46, height: 46)
            }
            Spacer()
            if !tracks.isEmpty {
                downloadButton
            } else {
                Color.clear.frame(width: 46, height: 46)
            }
            Spacer()
            Button {
                guard !tracks.isEmpty else { return }
                let order = PlaybackPrefs.shared.shufflePlaylistFirst ? tracks.shuffled() : tracks
                player.play(order, startAt: 0)
                player.openFullPlayer()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(palette.heroGradient)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(tracks.isEmpty)
            .opacity(tracks.isEmpty ? 0.45 : 1)
            .accessibilityLabel("Play")
            Spacer()
            if !tracks.isEmpty {
                roundButton("shuffle") {
                    player.play(tracks.shuffled(), startAt: 0)
                    player.openFullPlayer()
                }
            } else {
                Color.clear.frame(width: 46, height: 46)
            }
            Spacer()
            if isEditable || !(item.browseId ?? "").isEmpty {
                editMenu
            } else {
                Color.clear.frame(width: 46, height: 46)
            }
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 20)
    }

    @ViewBuilder private var downloadButton: some View {
        let states = tracks.map { downloads.state($0.videoId) }
        if states.allSatisfy({ $0 == .done }) {
            roundButton("checkmark.circle.fill", tint: palette.accent) {}
                .disabled(true)
                .accessibilityLabel("Downloaded")
        } else if states.contains(.downloading) {
            Button { confirmStopDownload = true } label: {
                LunaraDownloadLoader(size: 30)
                    .frame(width: 46, height: 46)
                    .background(palette.onSurface.opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Downloading. Tap to stop")
        } else {
            roundButton("arrow.down") { Downloads.shared.downloadAll(tracks) }
                .accessibilityLabel(downloadLabel)
        }
    }

    private func roundButton(_ icon: String, tint: Color? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint ?? palette.onSurface)
                .frame(width: 46, height: 46)
                .background(palette.onSurface.opacity(0.10))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func toggleSaved(_ id: String) {
        if saved {
            if let localId = SavedPlaylists.localCopyId(for: id) {
                localPlaylists.delete(id: localId)
                SavedPlaylists.setLocalCopyId(nil, for: id)
            }
            SavedPlaylists.set(id, false)
            saved = false
        } else {
            let created = localPlaylists.create(title: item.title, tracks: tracks)
            SavedPlaylists.setLocalCopyId(created.id, for: id)
            SavedPlaylists.set(id, true)
            saved = true
        }
    }

    @ViewBuilder private var editMenu: some View {
        if isEditable || !(item.browseId ?? "").isEmpty {
            Menu {
                if let browseId = item.browseId, !browseId.isEmpty {
                    Button { dial.toggle(currentHomeItem) } label: {
                        Label(dial.isPinned(browseId)
                              ? "Unpin from speed dial" : "Pin to speed dial",
                              systemImage: dial.isPinned(browseId) ? "pin.slash" : "pin")
                    }
                }
                if isEditable {
                    if !tracks.isEmpty {
                        Divider()
                        Button {
                            withAnimation { editing.toggle() }
                        } label: {
                            Label(editing ? "Done" : "Reorder or remove",
                                  systemImage: editing ? "checkmark" : "arrow.up.arrow.down")
                        }
                    }
                    Button {
                        newTitle = displayTitle
                        renaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete playlist", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .frame(width: 46, height: 46)
                    .background(palette.onSurface.opacity(0.10))
                    .clipShape(Circle())
            }
        }
    }

    private func remove(_ track: Track) {
        guard let playlistId = item.browseId, isLocalPlaylist else {
            notice = "This row can't be removed."
            return
        }
        withAnimation {
            tracks.removeAll {
                if let setId = track.setVideoId { return $0.setVideoId == setId }
                return $0.videoId == track.videoId
            }
        }
        localPlaylists.removeTrack(setVideoId: track.setVideoId, videoId: track.videoId, from: playlistId)
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        guard let playlistId = item.browseId, isLocalPlaylist else { return }
        withAnimation { tracks.move(fromOffsets: offsets, toOffset: destination) }
        localPlaylists.moveTracks(fromOffsets: offsets, toOffset: destination, in: playlistId)
    }

    private func rename() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let playlistId = item.browseId, isLocalPlaylist, !title.isEmpty else { return }
        localPlaylists.rename(id: playlistId, title: title)
    }

    private func deletePlaylist() {
        guard let playlistId = item.browseId, isLocalPlaylist else { return }
        if localPlaylists.delete(id: playlistId) {
            dismiss()
        } else {
            notice = "Couldn't delete the playlist."
        }
    }

    private func load() async {
        if isLocalPlaylist, let id = item.browseId {
            tracks = localPlaylists.playlist(id: id)?.tracks ?? []
            loading = false
            return
        }
        loading = true
        let t = await YouTube.playlist(browseId: item.browseId ?? "")
        await MainActor.run {
            tracks = t
            loading = false
        }
    }
}

enum SavedPlaylists {
    private static let key = "savedPlaylistIds"
    private static let mapKey = "savedPlaylistLocalCopies"

    static func contains(_ id: String) -> Bool {
        !id.isEmpty && (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id)
    }

    static func set(_ id: String, _ saved: Bool) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if saved { ids.insert(id) } else { ids.remove(id) }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    static func localCopyId(for remoteId: String) -> String? {
        let dict = UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String] ?? [:]
        return dict[remoteId]
    }

    static func setLocalCopyId(_ localId: String?, for remoteId: String) {
        var dict = UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String] ?? [:]
        if let localId {
            dict[remoteId] = localId
        } else {
            dict.removeValue(forKey: remoteId)
        }
        UserDefaults.standard.set(dict, forKey: mapKey)
    }
}
