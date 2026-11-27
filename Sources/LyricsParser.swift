import Foundation

struct TimedLyricLine: Identifiable {
    let id: Int
    let time: TimeInterval
    let text: String
}

enum LyricsParser {
    static func lines(from lyrics: String) -> [TimedLyricLine] {
        var result: [TimedLyricLine] = []
        let pattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for rawLine in lyrics.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let matches = regex.matches(in: rawLine, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }
            let text = regex.stringByReplacingMatches(
                in: rawLine,
                range: NSRange(location: 0, length: nsLine.length),
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: rawLine),
                      let secondRange = Range(match.range(at: 2), in: rawLine),
                      let minutes = Double(rawLine[minuteRange]),
                      let seconds = Double(rawLine[secondRange]) else { continue }
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: rawLine),
                   let rawFraction = Double(rawLine[fractionRange]) {
                    let digits = rawLine[fractionRange].count
                    fraction = rawFraction / (digits == 1 ? 10 : digits == 2 ? 100 : 1000)
                }
                result.append(TimedLyricLine(
                    id: result.count,
                    time: minutes * 60 + seconds + fraction,
                    text: text
                ))
            }
        }
        return result.sorted { $0.time < $1.time }
    }
}
