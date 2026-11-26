import Foundation

struct Track: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var artist: String
    var album: String
    var fileName: String
    var duration: TimeInterval
    var artworkData: Data?
    var lrc: String?
    var url: URL { LibraryStore.documents.appendingPathComponent(fileName) }
}

struct LyricLine: Identifiable {
    let id: Int
    let time: TimeInterval
    let text: String
}

enum LRC {
    /// Parses "[mm:ss.xx] text" lines into time-sorted lyric lines.
    static func parse(_ raw: String) -> [LyricLine] {
        let regex = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        var rows: [(TimeInterval, String)] = []
        for row in raw.components(separatedBy: .newlines) {
            let ns = row as NSString
            let matches = regex.matches(in: row, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
                rows.append((min * 60 + sec, text))
            }
        }
        return rows.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}
