import SwiftUI

struct LibraryView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    var onOpenPlayer: () -> Void
    @State private var query = ""
    @State private var filter = "Songs"
    @State private var showTools = false
    @State private var editingTrack: Track?
    @State private var selectedPlaylist: MusicPlaylist?

    private var filtered: [Track] {
        library.tracks.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
                || $0.album.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Library").font(.system(size: 34, weight: .bold))
                Spacer()
                Text("\(library.tracks.count) songs").font(.caption).foregroundStyle(Theme.muted)
                Button { showTools = true } label: { Image(systemName: "chart.bar.xaxis").font(.title3).foregroundStyle(ThemeAccent.color).padding(.leading, 8) }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search your music", text: $query).foregroundStyle(.white)
            }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            Picker("View", selection: $filter) {
                Text("Songs").tag("Songs")
                Text("Albums").tag("Albums")
                Text("Artists").tag("Artists")
                Text("Playlists").tag("Playlists")
            }.pickerStyle(.segmented)

            if filter == "Songs" {
                if filtered.isEmpty {
                    ContentUnavailableView("No music yet", systemImage: "music.note.list", description: Text("Import audio files to see them here."))
                } else {
                    List {
                        ForEach(filtered) { track in
                            Button { play(track) } label: {
                                HStack(spacing: 12) {
                                    ArtworkView(track: track).frame(width: 52, height: 52)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                                        Text("\(track.artist) · \(track.album)").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                                    }
                                    Spacer()
                                    if library.isLiked(track) { Image(systemName: "heart.fill").foregroundStyle(ThemeAccent.color) }
                                }.padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.bg)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { library.remove(track) } label: { Label("Delete", systemImage: "trash") }
                                Button { editingTrack = track } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                            }
                            .contextMenu {
                                Button(library.isLiked(track) ? "Unlike" : "Like", systemImage: "heart") { library.toggleLiked(track) }
                                Button("Edit song details", systemImage: "pencil") { editingTrack = track }
                                Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") { engine.addToQueue(track, playNext: true) }
                                Button("Add to queue", systemImage: "text.badge.plus") { engine.addToQueue(track) }
                                Menu("Add to playlist", systemImage: "text.badge.plus") {
                                    ForEach(library.playlists) { playlist in
                                        Button(playlist.name) { library.add(track, to: playlist) }
                                    }
                                }.disabled(library.playlists.isEmpty)
                                Button("Remove from library", systemImage: "trash", role: .destructive) { library.remove(track) }
                            }
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            } else if filter == "Playlists" {
                List {
                    ForEach(library.playlists) { playlist in
                        Button { selectedPlaylist = playlist } label: {
                            HStack {
                                Image(systemName: "music.note.list").font(.title2).foregroundStyle(ThemeAccent.color)
                                VStack(alignment: .leading) {
                                    Text(playlist.name).foregroundStyle(.white)
                                    Text("\(library.tracks(in: playlist).count) songs").font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                            }.padding(.vertical, 5)
                        }.listRowBackground(Theme.bg)
                    }
                    if library.playlists.isEmpty {
                        ContentUnavailableView("No playlists yet", systemImage: "music.note.list", description: Text("Open the chart button to create one."))
                            .listRowBackground(Theme.bg)
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
            } else {
                List {
                    ForEach(filter == "Albums" ? library.albums : library.artists, id: \.self) { name in
                        Button {
                            let tracks = library.tracks.filter { filter == "Albums" ? $0.album == name : $0.artist == name }
                            engine.setQueue(tracks); onOpenPlayer()
                        } label: {
                            HStack {
                                Image(systemName: filter == "Albums" ? "square.stack" : "person.crop.circle").foregroundStyle(ThemeAccent.color)
                                Text(name).foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "play.fill").foregroundStyle(Theme.muted)
                            }
                        }.listRowBackground(Theme.bg)
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).foregroundStyle(.white)
        .sheet(isPresented: $showTools) { PersonalLibraryToolsView().environment(library) }
        .sheet(item: $editingTrack) { track in TrackMetadataEditor(track: track).environment(library) }
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist).environment(library).environment(engine)
        }
    }

    private func play(_ track: Track) {
        engine.setQueue(filtered, startAt: filtered.firstIndex(of: track) ?? 0)
        onOpenPlayer()
    }
}

struct PlaylistDetailView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let playlist: MusicPlaylist
    private var songs: [Track] { library.tracks(in: playlist) }
    private var playlistShareText: String {
        let rows = songs.map { "\($0.title) — \($0.artist) [\($0.album)]" }
        return (["DSM Music Playlist: \(playlist.name)", ""] + rows).joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(songs) { track in
                    HStack(spacing: 12) {
                        ArtworkView(track: track).frame(width: 46, height: 46)
                        Button { engine.setQueue(songs, startAt: songs.firstIndex(of: track) ?? 0); dismiss() } label: {
                            VStack(alignment: .leading) {
                                Text(track.title).foregroundStyle(.primary)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) { library.remove(track, from: playlist) } label: { Image(systemName: "minus.circle") }
                    }
                }
            }
            .navigationTitle(playlist.name)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: playlistShareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
