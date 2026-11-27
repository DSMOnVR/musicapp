import Foundation

struct TimedLyricWord: Identifiable {
    let id: Int
    let time: TimeInterval
    let text: String
}

struct TimedLyricLine: Identifiable {
    let id: Int
    let time: TimeInterval
    let text: String
    let words: [TimedLyricWord]

    var hasWordTiming: Bool { !words.isEmpty }
}

enum LyricsParser {
    private static let lineTimestampPattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
    private static let wordTimestampPattern = #"<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>"#

    static func lines(from lyrics: String) -> [TimedLyricLine] {
        var result: [TimedLyricLine] = []
        guard let lineRegex = try? NSRegularExpression(pattern: lineTimestampPattern),
              let wordRegex = try? NSRegularExpression(pattern: wordTimestampPattern) else { return [] }

        for rawLine in lyrics.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let lineMatches = lineRegex.matches(in: rawLine, range: fullRange)
            guard !lineMatches.isEmpty else { continue }

            let wordMatches = wordRegex.matches(in: rawLine, range: fullRange)
            var wordSegments: [(time: TimeInterval, text: String)] = []
            if !wordMatches.isEmpty {
                for (index, match) in wordMatches.enumerated() {
                    let contentStart = NSMaxRange(match.range)
                    let contentEnd = index + 1 < wordMatches.count
                        ? wordMatches[index + 1].range.location
                        : nsLine.length
                    guard contentEnd >= contentStart,
                          let timestamp = timestamp(from: match, in: rawLine) else { continue }
                    let segment = nsLine.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
                    wordSegments.append((timestamp, segment))
                }
            }

            let plainText = lineRegex.stringByReplacingMatches(
                in: rawLine,
                range: fullRange,
                withTemplate: ""
            )
            let cleanText = wordRegex.stringByReplacingMatches(
                in: plainText,
                range: NSRange(location: 0, length: (plainText as NSString).length),
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            let words = wordSegments.enumerated().map { index, segment in
                TimedLyricWord(id: index, time: segment.time, text: segment.text)
            }

            for match in lineMatches {
                guard let lineTime = timestamp(from: match, in: rawLine) else { continue }
                result.append(TimedLyricLine(
                    id: result.count,
                    time: lineTime,
                    text: cleanText,
                    words: words
                ))
            }
        }

        return result.sorted { $0.time < $1.time }
    }

    private static func timestamp(from match: NSTextCheckingResult, in source: String) -> TimeInterval? {
        guard let minuteRange = Range(match.range(at: 1), in: source),
              let secondRange = Range(match.range(at: 2), in: source),
              let minutes = Double(source[minuteRange]),
              let seconds = Double(source[secondRange]) else { return nil }

        var fraction = 0.0
        if match.range(at: 3).location != NSNotFound,
           let fractionRange = Range(match.range(at: 3), in: source),
           let rawFraction = Double(source[fractionRange]) {
            let digits = source[fractionRange].count
            fraction = rawFraction / (digits == 1 ? 10 : digits == 2 ? 100 : 1000)
        }
        return minutes * 60 + seconds + fraction
    }
}
