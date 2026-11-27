import Foundation

/// Fetches timed LRC lyrics from Lyricsify. Lyrics are saved by LibraryStore for offline use.
enum LyricsifyService {
    static func fetchLyrics(title: String, artist: String) async -> String? {
        let artistSlug = slug(artist)
        let titleSlug = slug(title)
        guard !artistSlug.isEmpty, !titleSlug.isEmpty else { return nil }

        let pageURL = URL(string: "https://www.lyricsify.com/lyrics/\(artistSlug)/\(titleSlug)")!
        do {
            let html = try await fetchText(from: pageURL)
            if let lrcPath = firstMatch(
                in: html,
                patterns: [
                    #"href=["']([^"']*/lrc/[^"']+)["']"#,
                    #"href=["']([^"']+\.lrc(?:\?[^"']*)?)["']"#
                ]
            ), let lrcURL = absoluteURL(lrcPath, relativeTo: pageURL),
               let lrcPage = try? await fetchText(from: lrcURL),
               let lrc = extractLRC(from: lrcPage) {
                return lrc
            }

            // Some song pages expose the timed text directly in the entry container.
            if let lrc = extractLRC(from: html) { return lrc }
        } catch {
            // Lyricsify may block automated requests or have no matching song.
        }
        return nil
    }

    private static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let words = folded.lowercased().split { !$0.unicodeScalars.allSatisfy { allowed.contains($0) } }
        return words.map(String.init).joined(separator: "-")
    }

    private static func fetchText(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,text/plain,*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return text
    }

    private static func extractLRC(from page: String) -> String? {
        if !page.contains("<") && looksLikeLRC(page) { return page }
        if let entry = firstMatch(
            in: page,
            patterns: [
                #"<div[^>]*id=["']entry["'][^>]*>(.*?)</div>"#,
                #"<div[^>]*id=["']lyrics_[^"']*_details["'][^>]*>(.*?)</div>"#
            ]
        ) {
            let decoded = decodeHTML(stripHTML(entry))
            if looksLikeLRC(decoded) { return decoded }
        }
        return nil
    }

    private static func firstMatch(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return String(text[range])
        }
        return nil
    }

    private static func absoluteURL(_ value: String, relativeTo base: URL) -> URL? {
        let cleaned = value.replacingOccurrences(of: "&amp;", with: "&")
        if let url = URL(string: cleaned, relativeTo: base)?.absoluteURL,
           url.scheme == "https", url.host == "www.lyricsify.com" || url.host == "lyricsify.com" {
            return url
        }
        return nil
    }

    private static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p\\s*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static func decodeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#x27;", with: "'")
    }

    private static func looksLikeLRC(_ text: String) -> Bool {
        text.range(of: #"\[\d{1,2}:\d{2}(?:\.\d{1,3})?\]"#, options: .regularExpression) != nil
    }
}
