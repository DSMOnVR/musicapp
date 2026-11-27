import Foundation
import Observation

@MainActor @Observable
final class LibraryStore {
    private(set) var tracks: [Track] = []
    var likedIDs: Set<UUID> = []
    var lastImportMessage: String?
    var importErrors: [String] = []

    private let storageURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        storageURL = support.appendingPathComponent("music-library.json")
        loadSavedLibrary()
    }

    var artists: [String] { Array(Set(tracks.map(\.artist))).sorted() }
    var albums: [String] { Array(Set(tracks.map(\.album))).sorted() }
    var likedTracks: [Track] { tracks.filter { likedIDs.contains($0.id) } }

    func add(_ newTracks: [Track]) {
        let existing = Set(tracks.map { $0.url.standardizedFileURL.path })
        let additions = newTracks.filter { !existing.contains($0.url.standardizedFileURL.path) }
        tracks.append(contentsOf: additions)
        saveLibrary()
        lastImportMessage = additions.isEmpty ? "These songs are already in your library." : "Added \(additions.count) song\(additions.count == 1 ? "" : "s")."

        // Look up missing lyrics in the background; successful results are stored locally.
        for track in additions where (track.lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task {
                guard let lyrics = await LyricsifyService.fetchLyrics(title: track.title, artist: track.artist) else { return }
                updateLyrics(for: track, text: lyrics)
            }
        }
    }

    func toggleLiked(_ track: Track) {
        if likedIDs.contains(track.id) { likedIDs.remove(track.id) } else { likedIDs.insert(track.id) }
        saveLibrary()
    }

    func isLiked(_ track: Track) -> Bool { likedIDs.contains(track.id) }

    func updateLyrics(for track: Track, text: String) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        tracks[index].lyrics = cleaned.isEmpty ? nil : cleaned
        saveLibrary()
    }

    func remove(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
        likedIDs.remove(track.id)
        saveLibrary()
    }

    private struct SavedLibrary: Codable {
        var tracks: [Track]
        var likedIDs: Set<UUID>
    }

    private func loadSavedLibrary() {
        guard let data = try? Data(contentsOf: storageURL),
              let saved = try? JSONDecoder().decode(SavedLibrary.self, from: data) else { return }
        tracks = saved.tracks.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        likedIDs = saved.likedIDs
    }

    private func saveLibrary() {
        let saved = SavedLibrary(tracks: tracks, likedIDs: likedIDs)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
