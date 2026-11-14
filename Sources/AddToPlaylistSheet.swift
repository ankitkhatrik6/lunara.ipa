import SwiftUI

struct AddToPlaylistSheet: View {
    @Environment(\.palette) private var palette
    let track: Track
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localPlaylists = LocalPlaylistStore.shared

    @State private var addedID: String?
    @State private var creating = false
    @State private var newName = ""
    @State private var failed = false

    private var playlists: [UserPlaylist] {
        localPlaylists.playlists.map(\.asUserPlaylist)
    }

    var body: some View {
        NavigationStack {
            List {
                Button { creating = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(palette.accent)
                            .clipShape(Circle())
                        Text("Create playlist")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.onSurface)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)

                ForEach(playlists) { playlist in
                    Button { add(to: playlist) } label: { row(playlist) }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                }

                if playlists.isEmpty {
                    Text("No playlists yet")
                        .foregroundStyle(palette.onSurfaceVariant)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(palette.surface.ignoresSafeArea())
            .navigationTitle("Add to playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(palette.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("New playlist", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Create") { create() }
        }
        .alert("Couldn't update the playlist", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func row(_ playlist: UserPlaylist) -> some View {
        HStack(spacing: 14) {
            RemoteImage(url: playlist.thumbnailURL, size: 56) {
                palette.onSurface.opacity(0.06)
                    .overlay(Image(systemName: "music.note.list")
                        .foregroundStyle(palette.onSurface.opacity(0.35)))
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(playlist.title)
                .font(.system(size: 16))
                .foregroundStyle(palette.onSurface)
                .lineLimit(1)
            Spacer(minLength: 0)

            if addedID == playlist.id {
                Image(systemName: "checkmark").foregroundStyle(palette.accent)
            }
        }
        .contentShape(Rectangle())
    }

    private func add(to playlist: UserPlaylist) {
        guard localPlaylists.add([track], to: playlist.id) else {
            failed = true
            return
        }
        addedID = playlist.id
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run { dismiss() }
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        newName = ""
        guard !name.isEmpty else { return }
        localPlaylists.create(title: name, tracks: [track])
        dismiss()
    }
}
