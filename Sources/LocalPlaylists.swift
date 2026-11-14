import Foundation
import SwiftUI

struct LocalPlaylist: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var tracks: [Track]
    let createdAt: Date
    var updatedAt: Date

    var thumbnail: String {
        for track in tracks {
            if let url = track.artURL(size: 544)?.absoluteString, !url.isEmpty {
                return url
            }
            if !track.thumbnail.isEmpty {
                return track.thumbnail
            }
        }
        return ""
    }

    var subtitle: String {
        let count = tracks.count
        return count == 1 ? String(localized: "1 song") : String(localized: "\(count) songs")
    }

    var asHomeItem: HomeItem {
        HomeItem(
            title: title,
            subtitle: subtitle,
            thumbnail: thumbnail,
            videoId: nil,
            browseId: id,
            isCircular: false
        )
    }

    var asUserPlaylist: UserPlaylist {
        UserPlaylist(id: id, title: title, thumbnail: thumbnail)
    }
}

@MainActor
final class LocalPlaylistStore: ObservableObject {
    static let shared = LocalPlaylistStore()
    static let idPrefix = "local:"

    @Published private(set) var playlists: [LocalPlaylist] = []

    private let fileURL: URL

    static func isLocal(_ browseId: String?) -> Bool {
        browseId?.hasPrefix(idPrefix) == true
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Lunara", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("local_playlists.json")
        load()
    }

    func playlist(id: String) -> LocalPlaylist? {
        playlists.first { $0.id == id }
    }

    @discardableResult
    func create(title: String, tracks: [Track] = []) -> LocalPlaylist {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let normalized = tracks.map { assignRowId($0) }
        let created = LocalPlaylist(
            id: Self.idPrefix + UUID().uuidString,
            title: cleanTitle.isEmpty ? String(localized: "Untitled playlist") : cleanTitle,
            tracks: normalized,
            createdAt: now,
            updatedAt: now
        )
        playlists.insert(created, at: 0)
        save()
        return created
    }

    @discardableResult
    func add(_ newTracks: [Track], to id: String) -> Bool {
        guard let index = playlists.firstIndex(where: { $0.id == id }), !newTracks.isEmpty else {
            return false
        }
        let stamped = newTracks.map { assignRowId($0) }
        playlists[index].tracks.append(contentsOf: stamped)
        playlists[index].updatedAt = Date()
        save()
        return true
    }

    @discardableResult
    func removeTrack(setVideoId: String?, videoId: String, from id: String) -> Bool {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return false }
        if let setVideoId, !setVideoId.isEmpty {
            playlists[index].tracks.removeAll { $0.setVideoId == setVideoId }
        } else {
            playlists[index].tracks.removeAll { $0.videoId == videoId }
        }
        playlists[index].updatedAt = Date()
        save()
        return true
    }

    @discardableResult
    func moveTracks(fromOffsets: IndexSet, toOffset: Int, in id: String) -> Bool {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return false }
        playlists[index].tracks.move(fromOffsets: fromOffsets, toOffset: toOffset)
        playlists[index].updatedAt = Date()
        save()
        return true
    }

    @discardableResult
    func rename(id: String, title: String) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty,
              let index = playlists.firstIndex(where: { $0.id == id }) else { return false }
        playlists[index].title = cleanTitle
        playlists[index].updatedAt = Date()
        save()
        return true
    }

    @discardableResult
    func delete(id: String) -> Bool {
        let before = playlists.count
        playlists.removeAll { $0.id == id }
        guard playlists.count != before else { return false }
        save()
        return true
    }

    private func assignRowId(_ track: Track) -> Track {
        var copy = track
        copy.setVideoId = UUID().uuidString
        return copy
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([LocalPlaylist].self, from: data) else {
            playlists = []
            return
        }
        playlists = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct FavoriteArtist: Identifiable, Codable, Hashable {
    let browseId: String
    let name: String
    let thumbnail: String
    let subscribers: String

    var id: String { browseId }

    var asHomeItem: HomeItem {
        HomeItem(
            title: name,
            subtitle: subscribers,
            thumbnail: thumbnail,
            videoId: nil,
            browseId: browseId,
            isCircular: true
        )
    }
}

@MainActor
final class FavoriteArtistStore: ObservableObject {
    static let shared = FavoriteArtistStore()

    @Published private(set) var artists: [FavoriteArtist] = []
    private let key = "favoriteArtistsLocal"

    private init() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FavoriteArtist].self, from: data) else {
            artists = []
            return
        }
        artists = decoded
    }

    func contains(_ browseId: String) -> Bool {
        artists.contains { $0.browseId == browseId }
    }

    func toggle(browseId: String, name: String, thumbnail: String, subscribers: String) {
        if let idx = artists.firstIndex(where: { $0.browseId == browseId }) {
            artists.remove(at: idx)
        } else {
            artists.insert(
                FavoriteArtist(
                    browseId: browseId,
                    name: name,
                    thumbnail: thumbnail,
                    subscribers: subscribers
                ),
                at: 0
            )
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(artists) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
