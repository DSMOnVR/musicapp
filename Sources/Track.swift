import Foundation

struct Track: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var artist: String
    var album: String
    var url: URL
    var duration: TimeInterval
    var artworkData: Data?
    var lyrics: String?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String,
        url: URL,
        duration: TimeInterval,
        artworkData: Data?,
        lyrics: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.url = url
        self.duration = duration
        self.artworkData = artworkData
        self.lyrics = lyrics
    }
}
