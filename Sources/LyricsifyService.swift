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

        if let richerLyrics = await fetchWordTimedLyrics(title: title, artist: artist, album: album, duration: duration) {
            return richerLyrics
        }

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

    /// Uses a multi-provider lyrics service first so songs can receive native
    /// word-level timestamps when a provider has them. Falls back to LRCLIB below.
    private static func fetchWordTimedLyrics(title: String, artist: String, album: String?, duration: TimeInterval?) async -> String? {
        var components = URLComponents(string: "https://api.liriqo-alfarrizi.my.id/v1/lyrics")
        var items = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "artist", value: artist)
        ]
        if let duration, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        if let album, !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "album", value: album))
        }
        components?.queryItems = items
        guard let endpoint = components?.url else { return nil }

        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let primary = root["primary"] as? [String: Any],
                  let lines = primary["timed"] as? [[String: Any]],
                  !lines.isEmpty else { return nil }

            var output: [String] = []
            for line in lines {
                guard let lineStart = number(line["start"]) else { continue }
                let lineText = (line["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = "[\(lrcTimestamp(lineStart))]"
                let words = line["words"] as? [[String: Any]] ?? []
                if !words.isEmpty {
                    let timedWords = words.compactMap { word -> String? in
                        guard let start = number(word["start"]),
                              let text = word["text"] as? String,
                              !text.isEmpty else { return nil }
                        return "<\(lrcTimestamp(start))>\(text)"
                    }
                    if !timedWords.isEmpty {
                        output.append(prefix + timedWords.joined())
                        continue
                    }
                }
                if !lineText.isEmpty {
                    output.append(prefix + lineText)
                }
            }
            let result = output.joined(separator: "\n")
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    /// LiriQo returns absolute timestamps in milliseconds; Enhanced LRC uses mm:ss.mmm.
    private static func lrcTimestamp(_ milliseconds: Double) -> String {
        let totalSeconds = max(milliseconds, 0) / 1000
        let minutes = Int(totalSeconds / 60)
        let seconds = totalSeconds - Double(minutes * 60)
        return String(format: "%02d:%06.3f", minutes, seconds)
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
