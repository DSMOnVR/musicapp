import AVFoundation

/// Copies a picked audio file into the app's Documents folder and reads its tags.
enum TrackLoader {
    static func load(from source: URL) async throws -> Track {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = docs.appendingPathComponent(source.lastPathComponent)
        if !FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.copyItem(at: source, to: dest)
        }

        let asset = AVURLAsset(url: dest)
        let seconds = try await asset.load(.duration).seconds
        let metadata = try await asset.load(.commonMetadata)

        func string(_ id: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id).first else { return nil }
            return try? await item.load(.stringValue)
        }
        let artworkItem = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first
        let artworkData = try? await artworkItem?.load(.dataValue)

        return Track(
            title: await string(.commonIdentifierTitle) ?? dest.deletingPathExtension().lastPathComponent,
            artist: await string(.commonIdentifierArtist) ?? "Unknown Artist",
            album: await string(.commonIdentifierAlbumName) ?? "Unknown Album",
            url: dest,
            duration: seconds.isFinite ? seconds : 0,
            artworkData: artworkData
        )
    }
}
