import Foundation
import Observation

struct MusicPlaylist: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var trackIDs: [UUID] = []
    var createdAt: Date = .now
}

struct LibraryBackup: Codable {
    var tracks: [Track]
    var likedIDs: Set<UUID>
    var playlists: [MusicPlaylist]
    var playCounts: [UUID: Int]
    var listeningSeconds: TimeInterval
}

@MainActor @Observable
final class LibraryStore {
    private(set) var tracks: [Track] = []
    var likedIDs: Set<UUID> = []
    var playlists: [MusicPlaylist] = []
    var playCounts: [UUID: Int] = [:]
    var listeningSeconds: TimeInterval = 0
    var lastImportMessage: String?
    var importErrors: [String] = []

    private let storageURL: URL
    @ObservationIgnored private var fetchingLyricsIDs: Set<UUID> = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        storageURL = support.appendingPathComponent("music-library.json")
        loadSavedLibrary()
    }

    var artists: [String] { Array(Set(tracks.map(\.artist))).sorted() }
    var albums: [String] { Array(Set(tracks.map(\.album))).sorted() }
    var likedTracks: [Track] { tracks.filter { likedIDs.contains($0.id) } }
    var mostPlayed: [Track] { tracks.sorted { (playCounts[$0.id] ?? 0) > (playCounts[$1.id] ?? 0) } }

    func add(_ newTracks: [Track]) {
        let existing = Set(tracks.map { $0.url.standardizedFileURL.path })
        let additions = newTracks.filter { !existing.contains($0.url.standardizedFileURL.path) }
        tracks.append(contentsOf: additions)
        saveLibrary()
        lastImportMessage = additions.isEmpty ? "These songs are already in your library." : "Added \(additions.count) song\(additions.count == 1 ? "" : "s")."
        additions.forEach { fetchLyricsIfNeeded(for: $0) }
    }

    func toggleLiked(_ track: Track) {
        if likedIDs.contains(track.id) { likedIDs.remove(track.id) } else { likedIDs.insert(track.id) }
        saveLibrary()
    }
    func isLiked(_ track: Track) -> Bool { likedIDs.contains(track.id) }

    func fetchLyricsIfNeeded(for track: Track) {
        guard (track.lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !fetchingLyricsIDs.contains(track.id) else { return }
        fetchingLyricsIDs.insert(track.id)
        Task {
            defer { fetchingLyricsIDs.remove(track.id) }
            guard let lyrics = await LyricsifyService.fetchLyrics(title: track.title, artist: track.artist) else { return }
            updateLyrics(for: track, text: lyrics)
        }
    }

    func updateLyrics(for track: Track, text: String) {
        updateTrack(track.id) { $0.lyrics = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text }
    }

    func updateMetadata(for track: Track, title: String, artist: String, album: String) {
        updateTrack(track.id) {
            $0.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.album = album.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func updateTrack(_ id: UUID, change: (inout Track) -> Void) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        change(&tracks[index])
        saveLibrary()
    }

    func createPlaylist(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        playlists.append(MusicPlaylist(name: clean))
        saveLibrary()
    }
    func add(_ track: Track, to playlist: MusicPlaylist) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }),
              !playlists[i].trackIDs.contains(track.id) else { return }
        playlists[i].trackIDs.append(track.id)
        saveLibrary()
    }
    func remove(_ track: Track, from playlist: MusicPlaylist) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[i].trackIDs.removeAll { $0 == track.id }
        saveLibrary()
    }
    func tracks(in playlist: MusicPlaylist) -> [Track] {
        playlist.trackIDs.compactMap { id in tracks.first { $0.id == id } }
    }
    func deletePlaylist(_ playlist: MusicPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        saveLibrary()
    }

    func recordPlay(_ track: Track) {
        playCounts[track.id, default: 0] += 1
        saveLibrary()
    }
    func addListeningTime(_ seconds: TimeInterval) {
        guard seconds > 0, seconds < 5 else { return }
        listeningSeconds += seconds
        saveLibrary()
    }

    func remove(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
        likedIDs.remove(track.id)
        playCounts.removeValue(forKey: track.id)
        for index in playlists.indices { playlists[index].trackIDs.removeAll { $0 == track.id } }
        saveLibrary()
    }

    func makeBackupData() throws -> Data {
        try JSONEncoder.pretty.encode(LibraryBackup(tracks: tracks, likedIDs: likedIDs, playlists: playlists, playCounts: playCounts, listeningSeconds: listeningSeconds))
    }

    func restoreBackup(from data: Data) throws {
        let backup = try JSONDecoder().decode(LibraryBackup.self, from: data)
        let validTracks = backup.tracks.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        tracks = validTracks
        let ids = Set(validTracks.map(\.id))
        likedIDs = backup.likedIDs.intersection(ids)
        playlists = backup.playlists.map { playlist in
            var copy = playlist
            copy.trackIDs = copy.trackIDs.filter { ids.contains($0) }
            return copy
        }
        playCounts = backup.playCounts.filter { ids.contains($0.key) }
        listeningSeconds = backup.listeningSeconds
        saveLibrary()
    }

    private struct SavedLibrary: Codable {
        var tracks: [Track]
        var likedIDs: Set<UUID>
        var playlists: [MusicPlaylist]?
        var playCounts: [UUID: Int]?
        var listeningSeconds: TimeInterval?
    }

    private func loadSavedLibrary() {
        guard let data = try? Data(contentsOf: storageURL),
              let saved = try? JSONDecoder().decode(SavedLibrary.self, from: data) else { return }
        tracks = saved.tracks.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        likedIDs = saved.likedIDs
        playlists = saved.playlists ?? []
        playCounts = saved.playCounts ?? [:]
        listeningSeconds = saved.listeningSeconds ?? 0
    }

    private func saveLibrary() {
        let saved = SavedLibrary(tracks: tracks, likedIDs: likedIDs, playlists: playlists, playCounts: playCounts, listeningSeconds: listeningSeconds)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
