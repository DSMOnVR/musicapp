import AVFoundation
import UIKit
import Observation

@MainActor @Observable
final class LibraryStore {
    nonisolated static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    private(set) var tracks: [Track] = []
    var status = ""
    @ObservationIgnored private let indexURL = LibraryStore.documents.appendingPathComponent("library.json")

    init() {
        if let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode([Track].self, from: data) {
            tracks = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tracks) { try? data.write(to: indexURL) }
    }

    func track(id: UUID?) -> Track? { tracks.first { $0.id == id } }

    func delete(_ track: Track) {
        try? FileManager.default.removeItem(at: track.url)
        tracks.removeAll { $0.id == track.id }
        save()
    }

    func fetchLyrics(for id: UUID) async {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        let t = tracks[i]
        if let lrc = await LyricsService.synced(title: t.title, artist: t.artist, duration: t.duration) {
            tracks[i].lrc = lrc
            save()
        }
    }

    /// Copies files into the app, reads tags, looks up missing info and lyrics. Returns the new tracks.
    func importFiles(_ urls: [URL], secured: Bool) async -> [Track] {
        let d = UserDefaults.standard
        let autoTag = d.object(forKey: "autoTag") as? Bool ?? true
        let findLyrics = d.object(forKey: "findLyrics") as? Bool ?? true
        var added: [Track] = []
        for (i, src) in urls.enumerated() {
            status = "Importing \(i + 1) of \(urls.count)"
            guard var t = try? await Self.readTrack(from: src, secured: secured) else { continue }
            let missing = t.artist == "Unknown Artist" || t.album == "Unknown Album" || t.artworkData == nil
            if autoTag, missing,
               let m = await MetadataService.lookup(title: t.title, artist: t.artist == "Unknown Artist" ? nil : t.artist) {
                if t.artist == "Unknown Artist" { t.artist = m.artist }
                if t.album == "Unknown Album" { t.album = m.album }
                if t.artworkData == nil { t.artworkData = m.artwork.flatMap { Self.shrink($0) } }
            }
            if findLyrics { t.lrc = await LyricsService.synced(title: t.title, artist: t.artist, duration: t.duration) }
            tracks.append(t)
            added.append(t)
        }
        status = ""
        save()
        return added
    }

    nonisolated static func readTrack(from source: URL, secured: Bool) async throws -> Track {
        let access = secured && source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }

        var name = source.lastPathComponent
        if FileManager.default.fileExists(atPath: documents.appendingPathComponent(name).path) {
            name = String(UUID().uuidString.prefix(6)) + "-" + name
        }
        let dest = documents.appendingPathComponent(name)

        // A coordinated read makes iCloud download the file first if it's only a placeholder.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                var coordError: NSError?
                var failure: Error?
                NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordError) { url in
                    do { try FileManager.default.copyItem(at: url, to: dest) } catch { failure = error }
                }
                if let e = coordError ?? failure { cont.resume(throwing: e) } else { cont.resume() }
            }
        }

        let asset = AVURLAsset(url: dest)
        let seconds = try await asset.load(.duration).seconds
        let metadata = try await asset.load(.commonMetadata)
        func string(_ id: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id).first else { return nil }
            return try? await item.load(.stringValue)
        }
        let artworkItem = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first
        let rawArt = try? await artworkItem?.load(.dataValue)

        return Track(
            title: await string(.commonIdentifierTitle) ?? dest.deletingPathExtension().lastPathComponent,
            artist: await string(.commonIdentifierArtist) ?? "Unknown Artist",
            album: await string(.commonIdentifierAlbumName) ?? "Unknown Album",
            fileName: name,
            duration: seconds.isFinite ? seconds : 0,
            artworkData: rawArt.flatMap { shrink($0) }
        )
    }

    nonisolated static func shrink(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let scale = min(1, 600 / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).jpegData(withCompressionQuality: 0.8) { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
