import Foundation

/// Looks up missing album covers online and returns image bytes for local offline storage.
enum AlbumArtworkService {
    private struct SearchResponse: Decodable {
        struct Result: Decodable {
            let artworkUrl100: URL?
        }
        let results: [Result]
    }

    static func artwork(title: String, artist: String) async -> Data? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\\(artist) \\(title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components?.url else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let results = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return nil }
            for result in results.results {
                guard let smallURL = result.artworkUrl100,
                      let largeURL = URL(string: smallURL.absoluteString.replacingOccurrences(of: "100x100", with: "600x600")) else { continue }
                let (imageData, imageResponse) = try await URLSession.shared.data(from: largeURL)
                if (imageResponse as? HTTPURLResponse)?.statusCode == 200,
                   imageData.count > 1_000, imageData.count < 12_000_000 {
                    return imageData
                }
            }
        } catch { return nil }
        return nil
    }
}
