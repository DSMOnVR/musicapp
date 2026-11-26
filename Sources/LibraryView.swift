import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerEngine.self) private var engine
    @Environment(ThemeStore.self) private var themes
    @State private var query = ""

    private var shown: [Track] {
        guard !query.isEmpty else { return library.tracks }
        return library.tracks.filter { t in [t.title, t.artist, t.album].contains { $0.localizedCaseInsensitiveContains(query) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Library").font(.system(size: 32, weight: .bold)).padding(.top, 14)
            TextField("Search songs", text: $query)
                .padding(.horizontal, 18).frame(height: 44)
                .background(Theme.card, in: Capsule())
            if library.tracks.isEmpty {
                EmptyHint(text: "Your songs will show up here.")
                Spacer()
            } else {
                List {
                    ForEach(shown) { t in
                        Button { play(t) } label: {
                            HStack(spacing: 12) {
                                ArtView(data: t.artworkData).frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                                        .foregroundStyle(engine.currentTrack?.id == t.id ? themes.accent : .white)
                                    Text("\(t.artist) · \(t.album)").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    }
                    .onDelete { offsets in
                        let items = offsets.map { shown[$0] }
                        items.forEach { library.delete($0) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, 24)
    }

    private func play(_ t: Track) {
        let list = shown
        if let i = list.firstIndex(of: t) { engine.setQueue(list, startAt: i) }
    }
}
