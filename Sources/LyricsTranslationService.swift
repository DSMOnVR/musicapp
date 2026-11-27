import Foundation

enum LyricsTranslationService {
    private struct Response: Decodable {
        struct Translation: Decodable { let translatedText: String }
        let responseData: Translation
    }

    static func translate(_ text: String, targetLanguage: String) async throws -> String {
        let lines = text.components(separatedBy: .newlines)
        var chunks: [String] = []
        var current = ""
        for line in lines {
            let candidate = current.isEmpty ? line : current + "\n" + line
            if candidate.count > 430, !current.isEmpty {
                chunks.append(current)
                current = line
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { chunks.append(current) }

        var translated: [String] = []
        for chunk in chunks {
            var components = URLComponents(string: "https://api.mymemory.translated.net/get")
            components?.queryItems = [
                URLQueryItem(name: "q", value: chunk),
                URLQueryItem(name: "langpair", value: "en|\(targetLanguage)")
            ]
            guard let url = components?.url else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let result = try JSONDecoder().decode(Response.self, from: data)
            translated.append(result.responseData.translatedText)
        }
        return translated.joined(separator: "\n")
    }
}
