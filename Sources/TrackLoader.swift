import Foundation
import UIKit

/// Online helpers: song info (iTunes Search), synced lyrics (LRCLIB), and the link-download server.
struct Match {
    var artist: String
    var album: String
    var artwork: Data?
}

enum MetadataService {
    static func lookup(title: String, artist: String?) async -> Match? {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [
            .init(name: "term", value: [artist, title].compactMap { $0 }.joined(separator: " ")),
            .init(name: "entity", value: "song"),
            .init(name: "limit", value: "1"),
        ]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first else { return nil }
        var art: Data?
        if let s = (first["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100", with: "600x600"),
           let u = URL(string: s), let (d, _) = try? await URLSession.shared.data(from: u) { art = d }
        return Match(artist: first["artistName"] as? String ?? artist ?? "Unknown Artist",
                     album: first["collectionName"] as? String ?? "Unknown Album", artwork: art)
    }
}

enum LyricsService {
    static func synced(title: String, artist: String, duration: TimeInterval) async -> String? {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist)]
        var req = URLRequest(url: c.url!)
        req.setValue("MusicApp (personal)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let withLyrics = list.filter { ($0["syncedLyrics"] as? String)?.isEmpty == false }
        let best = withLyrics.first { abs(($0["duration"] as? Double ?? -99) - duration) < 3 } ?? withLyrics.first
        return best?["syncedLyrics"] as? String
    }
}

enum DownloadService {
    enum Failure: LocalizedError {
        case badServer, failed
        var errorDescription: String? {
            switch self {
            case .badServer: return "Enter your server address first."
            case .failed: return "The server couldn't get that link. Check the address and the link."
            }
        }
    }

    /// Sends the link to your server (POST /download with {"url": ...}) and saves the MP3 it returns.
    static func fetchMP3(link: String, server: String) async throws -> URL {
        guard let base = URL(string: server.trimmingCharacters(in: .whitespaces)), base.host != nil else { throw Failure.badServer }
        var req = URLRequest(url: base.appendingPathComponent("download"))
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["url": link])
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.failed }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}
