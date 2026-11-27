import Foundation
import Observation

struct MusicPlaylist: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var trackIDs: [UUID] = []
    var createdAt: Date = .now
}

enum LyricsFetchStatus: Equatable {
    case searching
    case notFound
    case found
}

struct LibraryBackup: Codable {
    var tracks: [Track]
    var likedIDs: Set<UUID>
    var playlists: [MusicPlaylist]
    var playCounts: [UUID: Int]
    var listeningSeconds: TimeInterval
}

/// Portable backup manifest. Track URLs are relative paths inside the exported folder.
struct PortableLibraryBackup: Codable {
    var version: Int
    var tracks: [Track]
    var audioPaths: [UUID: String]
    var likedIDs: Set<UUID>
    var playlists: [MusicPlaylist]
    var playCounts: [UUID: Int]
    var listeningSeconds: TimeInterval
    var dailyPlayCounts: [String: Int]
}

@MainActor @Observable
final class LibraryStore {
    private(set) var tracks: [Track] = []
    var likedIDs: Set<UUID> = []
    var playlists: [MusicPlaylist] = []
    var playCounts: [UUID: Int] = [:]
    var listeningSeconds: TimeInterval = 0
    var dailyPlayCounts: [String: Int] = [:]
    var lastImportMessage: String?
    var importErrors: [String] = []

    private let storageURL: URL
    private var automaticBackupURL: URL { storageURL.deletingLastPathComponent().appendingPathComponent("music-library-autobackup.json") }
    @ObservationIgnored private var fetchingLyricsIDs: Set<UUID> = []
    private(set) var lyricsFetchStatus: [UUID: LyricsFetchStatus] = [:]
    @ObservationIgnored private var unsavedListeningSeconds: TimeInterval = 0

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

    var duplicateGroups: [[Track]] {
        // First match normalized title + artist, then compare durations with a
        // tolerance. This avoids missing duplicates that fall on opposite
        // sides of a rounded-second bucket.
        let candidates = Dictionary(grouping: tracks) { track in
            "\(normalizedDuplicateText(track.title))|\(normalizedDuplicateText(track.artist))"
        }

        var matches: [[Track]] = []
        for (key, bucket) in candidates where !key.hasPrefix("|") && !key.hasSuffix("|") && bucket.count > 1 {
            let sorted = bucket.sorted { $0.duration < $1.duration }
            var group: [Track] = []
            var referenceDuration: TimeInterval?

            for track in sorted {
                if let baseline = referenceDuration, abs(track.duration - baseline) > 5 {
                    if group.count > 1 { matches.append(group) }
                    group = []
                    referenceDuration = nil
                }
                if referenceDuration == nil { referenceDuration = track.duration }
                group.append(track)
            }
            if group.count > 1 { matches.append(group) }
        }

        return matches
            .map { $0.sorted { (playCounts[$0.id] ?? 0) > (playCounts[$1.id] ?? 0) } }
            .sorted { ($0.first?.title ?? "").localizedCaseInsensitiveCompare($1.first?.title ?? "") == .orderedAscending }
    }

    private func normalizedDuplicateText(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let words = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
        return words.joined().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    func removeDuplicateTracks() {
        let duplicates = duplicateGroups.flatMap { Array($0.dropFirst()) }
        guard !duplicates.isEmpty else { return }
        let removedIDs = Set(duplicates.map(\.id))
        tracks.removeAll { removedIDs.contains($0.id) }
        likedIDs.subtract(removedIDs)
        for id in removedIDs { playCounts.removeValue(forKey: id) }
        for index in playlists.indices {
            playlists[index].trackIDs.removeAll { removedIDs.contains($0) }
        }
        saveLibrary()
        lastImportMessage = "Removed \(duplicates.count) duplicate song copies."
    }

    func add(_ newTracks: [Track]) {
        let existing = Set(tracks.map { $0.url.standardizedFileURL.path })
        let additions = newTracks.filter { !existing.contains($0.url.standardizedFileURL.path) }
        tracks.append(contentsOf: additions)
        saveLibrary()
        lastImportMessage = additions.isEmpty ? "These songs are already in your library." : "Added \(additions.count) song\(additions.count == 1 ? "" : "s")."
        additions.forEach { fetchLyricsIfNeeded(for: $0) }
    }

    func fixMissingMetadata() -> Int {
        var fixed = 0
        for index in tracks.indices {
            let filename = tracks[index].url.deletingPathExtension().lastPathComponent
            let titleMissing = tracks[index].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || tracks[index].title.localizedCaseInsensitiveContains("unknown")
            let artistMissing = tracks[index].artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || tracks[index].artist.localizedCaseInsensitiveContains("unknown")
            guard titleMissing || artistMissing else { continue }

            if let separator = filename.range(of: " - ") {
                let fileArtist = String(filename[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
                let fileTitle = String(filename[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
                if titleMissing, !fileTitle.isEmpty { tracks[index].title = fileTitle }
                if artistMissing, !fileArtist.isEmpty { tracks[index].artist = fileArtist }
            } else if titleMissing, !filename.isEmpty {
                tracks[index].title = filename
            }
            if tracks[index].album.localizedCaseInsensitiveContains("unknown") {
                tracks[index].album = "Unknown Album"
            }
            fixed += 1
        }
        if fixed > 0 { saveLibrary() }
        lastImportMessage = fixed == 0 ? "No missing metadata could be fixed from filenames." : "Updated metadata for \(fixed) songs."
        return fixed
    }

    func organizeMusicFiles() -> Int {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("DSM Music", isDirectory: true)
        var moved = 0

        func safeFolder(_ value: String) -> String {
            let invalid = CharacterSet(charactersIn: "/\\\\:").union(.newlines)
            let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Unknown" : cleaned
        }

        for index in tracks.indices {
            let source = tracks[index].url
            let folder = root
                .appendingPathComponent(safeFolder(tracks[index].artist), isDirectory: true)
                .appendingPathComponent(safeFolder(tracks[index].album), isDirectory: true)
            let destinationFolder = folder
            var destination = destinationFolder.appendingPathComponent(source.lastPathComponent)
            if source.standardizedFileURL == destination.standardizedFileURL { continue }

            do {
                try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    destination = destinationFolder.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(6)).\(source.pathExtension)")
                }
                try FileManager.default.moveItem(at: source, to: destination)
                tracks[index].url = destination
                moved += 1
            } catch {
                continue
            }
        }
        if moved > 0 { saveLibrary() }
        lastImportMessage = moved == 0 ? "Your music files are already organized." : "Organized \(moved) music files by artist and album."
        return moved
    }

    func toggleLiked(_ track: Track) {
        if likedIDs.contains(track.id) { likedIDs.remove(track.id) } else { likedIDs.insert(track.id) }
        saveLibrary()
    }
    func isLiked(_ track: Track) -> Bool { likedIDs.contains(track.id) }

    func track(withID id: UUID) -> Track? {
        tracks.first { $0.id == id }
    }

    func lyricsStatus(for track: Track) -> LyricsFetchStatus {
        if !(track.lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .found }
        return lyricsFetchStatus[track.id] ?? .notFound
    }

    func fetchLyricsIfNeeded(for track: Track) {
        guard (self.track(withID: track.id)?.lyrics ?? track.lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !fetchingLyricsIDs.contains(track.id) else { return }
        fetchingLyricsIDs.insert(track.id)
        lyricsFetchStatus[track.id] = .searching
        Task {
            defer { fetchingLyricsIDs.remove(track.id) }
            guard let lyrics = await LyricsService.fetchLyrics(title: track.title, artist: track.artist, album: track.album, duration: track.duration) else {
                lyricsFetchStatus[track.id] = .notFound
                return
            }
            updateLyrics(for: track, text: lyrics)
        }
    }

    func retryLyrics(for track: Track) {
        guard !fetchingLyricsIDs.contains(track.id) else { return }
        lyricsFetchStatus[track.id] = .notFound
        fetchLyricsIfNeeded(for: track)
    }

    func updateLyrics(for track: Track, text: String) {
        updateTrack(track.id) { $0.lyrics = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text }
        lyricsFetchStatus[track.id] = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .notFound : .found
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
        let key = Self.historyDateFormatter.string(from: .now)
        dailyPlayCounts[key, default: 0] += 1
        saveLibrary()
    }

    static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    func addListeningTime(_ seconds: TimeInterval) {
        guard seconds > 0, seconds < 5 else { return }
        listeningSeconds += seconds
        unsavedListeningSeconds += seconds
        if unsavedListeningSeconds >= 15 {
            unsavedListeningSeconds = 0
            saveLibrary(syncCloud: false)
        }
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

    /// Creates a portable folder backup containing both the library database and every audio file.
    func makeFullBackupFileWrapper() throws -> FileWrapper {
        let portableTracks = tracks
        var audioWrappers: [String: FileWrapper] = [:]
        var audioPaths: [UUID: String] = [:]
        var missingFiles: [String] = []

        for track in portableTracks {
            let source = track.url
            guard FileManager.default.fileExists(atPath: source.path) else {
                missingFiles.append(track.title)
                continue
            }
            let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension
            let filename = "\(track.id.uuidString).\(ext)"
            let data = try Data(contentsOf: source)
            audioWrappers[filename] = FileWrapper(regularFileWithContents: data)
            audioPaths[track.id] = "Audio/\(filename)"
        }

        if !missingFiles.isEmpty {
            throw NSError(domain: "DSMMusicBackup", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Some songs are missing from this device: \(missingFiles.prefix(5).joined(separator: ", "))."
            ])
        }

        let manifest = PortableLibraryBackup(
            version: 1,
            tracks: portableTracks,
            audioPaths: audioPaths,
            likedIDs: likedIDs,
            playlists: playlists,
            playCounts: playCounts,
            listeningSeconds: listeningSeconds,
            dailyPlayCounts: dailyPlayCounts
        )
        let manifestData = try JSONEncoder.pretty.encode(manifest)
        let children: [String: FileWrapper] = [
            "Library.json": FileWrapper(regularFileWithContents: manifestData),
            "Audio": FileWrapper(directoryWithFileWrappers: audioWrappers)
        ]
        let root = FileWrapper(directoryWithFileWrappers: children)
        root.preferredFilename = "DSM Music Backup"
        return root
    }

    /// Restores a portable backup folder and copies its audio into this installation's Documents folder.
    func restoreFullBackup(from folderURL: URL) throws {
        let manifestURL = folderURL.appendingPathComponent("Library.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let backup = try JSONDecoder().decode(PortableLibraryBackup.self, from: manifestData)
        guard backup.version == 1 else {
            throw NSError(domain: "DSMMusicBackup", code: 2, userInfo: [NSLocalizedDescriptionKey: "This backup version isn't supported."])
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let restoredFolder = documents.appendingPathComponent("DSM Music", isDirectory: true)
            .appendingPathComponent("Restored", isDirectory: true)
        try FileManager.default.createDirectory(at: restoredFolder, withIntermediateDirectories: true)

        var restoredTracks: [Track] = []
        for var track in backup.tracks {
            guard let relative = backup.audioPaths[track.id] else { continue }
            let components = relative.split(separator: "/")
            guard components.count == 2, components[0] == "Audio" else { continue }
            let source = folderURL.appendingPathComponent("Audio", isDirectory: true)
                .appendingPathComponent(String(components[1]))
            guard FileManager.default.fileExists(atPath: source.path) else { continue }

            var destination = restoredFolder.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                let base = destination.deletingPathExtension().lastPathComponent
                destination = restoredFolder.appendingPathComponent("\(base)-\(UUID().uuidString.prefix(6)).\(destination.pathExtension)")
            }
            try FileManager.default.copyItem(at: source, to: destination)
            track.url = destination
            restoredTracks.append(track)
        }

        guard !restoredTracks.isEmpty || backup.tracks.isEmpty else {
            throw NSError(domain: "DSMMusicBackup", code: 3, userInfo: [NSLocalizedDescriptionKey: "No audio files could be restored. Make sure you selected the complete DSM Music Backup folder."])
        }

        let restoredIDs = Set(restoredTracks.map { $0.id })
        let existingIDs = Set(tracks.map(\.id))
        let newTracks = restoredTracks.filter { !existingIDs.contains($0.id) }
        tracks.append(contentsOf: newTracks)
        let allIDs = Set(tracks.map(\.id))
        likedIDs.formUnion(backup.likedIDs.intersection(allIDs))
        for playlist in backup.playlists {
            if !playlists.contains(where: { $0.id == playlist.id }) {
                var copy = playlist
                copy.trackIDs = copy.trackIDs.filter { allIDs.contains($0) }
                playlists.append(copy)
            }
        }
        for (id, count) in backup.playCounts where restoredIDs.contains(id) {
            playCounts[id] = max(playCounts[id, default: 0], count)
        }
        listeningSeconds = max(listeningSeconds, backup.listeningSeconds)
        for (day, count) in backup.dailyPlayCounts {
            dailyPlayCounts[day] = max(dailyPlayCounts[day, default: 0], count)
        }
        saveLibrary()
        lastImportMessage = "Restored \(restoredTracks.count) songs from your full backup."
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
        var dailyPlayCounts: [String: Int]?
    }

    private func loadSavedLibrary() {
        guard let data = try? Data(contentsOf: storageURL),
              let saved = try? JSONDecoder().decode(SavedLibrary.self, from: data) else { return }
        tracks = saved.tracks.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        likedIDs = saved.likedIDs
        playlists = saved.playlists ?? []
        playCounts = saved.playCounts ?? [:]
        listeningSeconds = saved.listeningSeconds ?? 0
        dailyPlayCounts = saved.dailyPlayCounts ?? [:]
    }

    func restoreFromGoogleDrive(tracks restoredTracks: [Track], likedIDs restoredLikes: Set<UUID>, playlists restoredPlaylists: [MusicPlaylist], playCounts restoredPlayCounts: [UUID: Int], listeningSeconds restoredListeningSeconds: TimeInterval, dailyPlayCounts restoredDailyCounts: [String: Int]) throws {
        tracks = restoredTracks
        let ids = Set(restoredTracks.map(\.id))
        likedIDs = restoredLikes.intersection(ids)
        playlists = restoredPlaylists.map { playlist in var copy = playlist; copy.trackIDs = copy.trackIDs.filter { ids.contains($0) }; return copy }
        playCounts = restoredPlayCounts.filter { ids.contains($0.key) }
        listeningSeconds = restoredListeningSeconds
        dailyPlayCounts = restoredDailyCounts
        saveLibrary(syncCloud: false)
    }

    private func saveLibrary(syncCloud: Bool = true) {
        let saved = SavedLibrary(tracks: tracks, likedIDs: likedIDs, playlists: playlists, playCounts: playCounts, listeningSeconds: listeningSeconds, dailyPlayCounts: dailyPlayCounts)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: storageURL, options: .atomic)
        try? data.write(to: automaticBackupURL, options: .atomic)
        if syncCloud { NotificationCenter.default.post(name: .dsmMusicLibraryDidChange, object: nil) }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
