import SwiftUI

struct LibraryView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    var onOpenPlayer: () -> Void
    @State private var query = ""
    @State private var filter = "Songs"
    private var filtered: [Track] { library.tracks.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) || $0.album.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("Library").font(.system(size: 34, weight: .bold)); Spacer(); Text("\(library.tracks.count) songs").font(.caption).foregroundStyle(Theme.muted) }
            HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted); TextField("Search your music", text: $query).foregroundStyle(.white) }
                .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            Picker("View", selection: $filter) { Text("Songs").tag("Songs"); Text("Albums").tag("Albums"); Text("Artists").tag("Artists") }.pickerStyle(.segmented)
            if filter == "Songs" {
                if filtered.isEmpty { ContentUnavailableView("No music yet", systemImage: "music.note.list", description: Text("Import audio files to see them here.")) }
                else {
                    List {
                        ForEach(filtered) { track in
                            Button { play(track) } label: {
                                HStack(spacing: 12) {
                                    ArtworkView(track: track).frame(width: 52, height: 52)
                                    VStack(alignment: .leading, spacing: 4) { Text(track.title).font(.headline).foregroundStyle(.white).lineLimit(1); Text("\(track.artist) · \(track.album)").font(.caption).foregroundStyle(Theme.muted).lineLimit(1) }
                                    Spacer()
                                    if library.isLiked(track) { Image(systemName: "heart.fill").foregroundStyle(ThemeAccent.color) }
                                    Menu { Button(library.isLiked(track) ? "Unlike" : "Like", systemImage: "heart") { library.toggleLiked(track) }; Button("Remove from library", systemImage: "trash", role: .destructive) { library.remove(track) } } label: { Image(systemName: "ellipsis").foregroundStyle(Theme.muted).padding(8) }
                                }.padding(.vertical, 4)
                            }.listRowBackground(Theme.bg)
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            } else {
                List {
                    ForEach(filter == "Albums" ? library.albums : library.artists, id: \.self) { name in
                        Button { let tracks = library.tracks.filter { filter == "Albums" ? $0.album == name : $0.artist == name }; engine.setQueue(tracks); onOpenPlayer() } label: {
                            HStack { Image(systemName: filter == "Albums" ? "square.stack" : "person.crop.circle").foregroundStyle(ThemeAccent.color); Text(name).foregroundStyle(.white); Spacer(); Image(systemName: "play.fill").foregroundStyle(Theme.muted) }
                        }.listRowBackground(Theme.bg)
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }.padding(.horizontal, 20).padding(.top, 18).foregroundStyle(.white)
    }
    private func play(_ track: Track) { engine.setQueue(filtered, startAt: filtered.firstIndex(of: track) ?? 0); onOpenPlayer() }
}
