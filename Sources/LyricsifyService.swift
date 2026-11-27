import Foundation

/// Searches LRCLIB and returns timed lyrics when available, otherwise plain lyrics.
/// LibraryStore persists the result inside the local music library for offline use.
enum LyricsService {
    private struct LyricsRecord: Decodable {
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    static func fetchLyrics(title: String, artist: String, album: String? = nil, duration: TimeInterval? = nil) async -> String? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = searchURL(title: title, artist: artist, album: album) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 18
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("DSM Music/1.0 (https://github.com/DSMOnVR/musicapp)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            let records = try JSONDecoder().decode([LyricsRecord].self, from: data)
            let targetTitle = normalize(title)
            let targetArtist = normalize(artist)
            let targetAlbum = normalize(album ?? "")

            let candidates = records.compactMap { record -> (LyricsRecord, Int)? in
                guard record.instrumental != true,
                      let foundTitle = record.trackName,
                      let foundArtist = record.artistName else { return nil }
                let candidateTitle = normalize(foundTitle)
                let candidateArtist = normalize(foundArtist)
                guard candidateTitle == targetTitle || candidateTitle.contains(targetTitle) || targetTitle.contains(candidateTitle) else { return nil }
                guard candidateArtist == targetArtist || candidateArtist.contains(targetArtist) || targetArtist.contains(candidateArtist) else { return nil }

                var score = 100
                if candidateTitle == targetTitle { score += 30 }
                if candidateArtist == targetArtist { score += 30 }
                if !targetAlbum.isEmpty && normalize(record.albumName ?? "") == targetAlbum { score += 12 }
                if let duration, let foundDuration = record.duration {
                    let difference = abs(duration - foundDuration)
                    if difference <= 2 { score += 20 }
                    else if difference <= 5 { score += 8 }
                    else if difference > 15 { score -= 25 }
                }
                if let synced = record.syncedLyrics, !synced.isEmpty { score += 5 }
                return (record, score)
            }

            guard let best = candidates.max(by: { $0.1 < $1.1 })?.0 else { return nil }
            if let synced = best.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return synced }
            if let plain = best.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return plain }
            return nil
        } catch {
            return nil
        }
    }

    private static func searchURL(title: String, artist: String, album: String?) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if let album, !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        components?.queryItems = items
        return components?.url
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
