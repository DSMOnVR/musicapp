import Foundation

struct Track: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var artist: String
    var album: String
    var url: URL
    var duration: TimeInterval
    var artworkData: Data?
}
