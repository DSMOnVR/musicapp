import Foundation
import UIKit

/// Looks up an artist's Wikipedia thumbnail while online and keeps a local copy for offline use.
@MainActor
enum ArtistImageStore {
    private struct Summary: Decodable {
        struct Thumbnail: Decodable {
            let source: URL
        }
        let thumbnail: Thumbnail?
    }

    static func image(for artist: String) async -> UIImage? {
        let name = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "Unknown Artist" else { return nil }

        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArtistPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = Data(name.lowercased().utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        let cachedFile = directory.appendingPathComponent(filename + ".jpg")

        if let data = try? Data(contentsOf: cachedFile), let cached = UIImage(data: data) {
            return cached
        }

        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let summaryURL = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encodedName)") else {
            return nil
        }

        do {
            var request = URLRequest(url: summaryURL)
            request.setValue("DSM-MusicApp/1.0 (artist artwork lookup)", forHTTPHeaderField: "User-Agent")
            let (summaryData, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let summary = try? JSONDecoder().decode(Summary.self, from: summaryData),
                  let imageURL = summary.thumbnail?.source else { return nil }

            let (imageData, imageResponse) = try await URLSession.shared.data(from: imageURL)
            guard (imageResponse as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: imageData) else { return nil }

            try? imageData.write(to: cachedFile, options: .atomic)
            return image
        } catch {
            return nil
        }
    }
}
