import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Copies imported audio into the app's Documents folder and reads embedded metadata.
enum TrackLoader {
    static func load(from source: URL) async throws -> Track {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let safeName = source.lastPathComponent.isEmpty ? "Imported audio" : source.lastPathComponent
        var destination = docs.appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: destination.path) {
            let base = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            destination = docs.appendingPathComponent("\(base)-\(UUID().uuidString.prefix(8)).\(ext)")
        }

        // NSFileCoordinator asks the Files/iCloud provider to vend the actual file contents.
        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: source, options: .forUploading, error: &coordinationError) { readableURL in
            do { try FileManager.default.copyItem(at: readableURL, to: destination) }
            catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }

        let asset = AVURLAsset(url: destination)
        let loadedDuration = try await asset.load(.duration)
        let seconds = loadedDuration.seconds
        let metadata = try await asset.load(.commonMetadata)
        let allMetadata = (try? await asset.load(.metadata)) ?? []

        func string(_ identifier: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first else { return nil }
            return try? await item.load(.stringValue)
        }

        let artworkItem = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first
        var artworkData = try? await artworkItem?.load(.dataValue)

        let lyricIdentifiers: [AVMetadataIdentifier] = [
            .iTunesMetadataLyrics,
            .id3MetadataUnsynchronizedLyric
        ]
        var embeddedLyrics: String?
        for identifier in lyricIdentifiers {
            if let item = AVMetadataItem.metadataItems(from: allMetadata, filteredByIdentifier: identifier).first,
               let value = try? await item.load(.stringValue),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                embeddedLyrics = value
                break
            }
        }

        let title = await string(.commonIdentifierTitle) ?? destination.deletingPathExtension().lastPathComponent
        let artist = await string(.commonIdentifierArtist) ?? "Unknown Artist"
        let album = await string(.commonIdentifierAlbumName) ?? "Unknown Album"
        if artworkData == nil {
            artworkData = await AlbumArtworkService.artwork(title: title, artist: artist)
        }

        return Track(
            title: title,
            artist: artist,
            album: album,
            url: destination,
            duration: seconds.isFinite ? seconds : 0,
            artworkData: artworkData,
            lyrics: embeddedLyrics
        )
    }
}
