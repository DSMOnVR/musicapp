import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerEngine.self) private var engine

    private struct ArtistItem: Identifiable { let id: String; let art: Data? }

    private var recent: [Track] { Array(library.tracks.reversed().prefix(12)) }
    private var artists: [ArtistItem] {
        var seen = Set<String>()
        var out: [ArtistItem] = []
        for t in library.tracks.reversed() where seen.insert(t.artist).inserted {
            out.append(ArtistItem(id: t.artist, art: t.artworkData))
        }
        return Array(out.prefix(12))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Home").font(.system(size: 32, weight: .bold)).padding(.top, 14)
                if library.tracks.isEmpty {
                    EmptyHint(text: "No songs yet. Open Import to add some.")
                } else {
                    SectionTitle("Recently added")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(recent) { t in
                                Button { play(t) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ArtView(data: t.artworkData).frame(width: 120, height: 120)
                                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                        Text(t.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                                        Text(t.artist).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                                    }
                                    .frame(width: 120, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    SectionTitle("Artists")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(artists) { a in
                                Button { playArtist(a.id) } label: {
                                    VStack(spacing: 6) {
                                        ArtView(data: a.art).frame(width: 106, height: 106).clipShape(Circle())
                                        Text(a.id).font(.system(size: 13, weight: .bold)).lineLimit(1)
                                    }
                                    .frame(width: 106)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private func play(_ t: Track) {
        if let i = library.tracks.firstIndex(of: t) { engine.setQueue(library.tracks, startAt: i) }
    }

    private func playArtist(_ name: String) {
        let list = library.tracks.filter { $0.artist == name }
        if !list.isEmpty { engine.setQueue(list) }
    }
}
