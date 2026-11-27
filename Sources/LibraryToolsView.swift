import SwiftUI
import UniformTypeIdentifiers

struct LibraryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws {
        FileWrapper(regularFileWithContents: data)
    }
}

struct PersonalLibraryToolsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\\.dismiss) private var dismiss
    @State private var exportDocument: LibraryBackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var playlistName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Listening statistics") {
                    LabeledContent("Songs in library", value: "\\(library.tracks.count)")
                    LabeledContent("Artists", value: "\\(library.artists.count)")
                    LabeledContent("Albums", value: "\\(library.albums.count)")
                    LabeledContent("Listening time", value: duration(library.listeningSeconds))
                    if let top = library.mostPlayed.first, (library.playCounts[top.id] ?? 0) > 0 {
                        LabeledContent("Most played", value: "\\(top.title) · \\(library.playCounts[top.id] ?? 0) plays")
                    }
                }
                Section("Playlists") {
                    HStack {
                        TextField("New playlist name", text: $playlistName)
                        Button("Create") {
                            library.createPlaylist(name: playlistName)
                            playlistName = ""
                        }.disabled(playlistName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(library.playlists) { playlist in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(playlist.name)
                                Text("\\(library.tracks(in: playlist).count) songs").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { library.deletePlaylist(playlist) } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                Section("Backup & restore") {
                    Button { prepareBackup() } label: {
                        Label("Export library backup", systemImage: "square.and.arrow.up")
                    }
                    Button { showImporter = true } label: {
                        Label("Restore library backup", systemImage: "square.and.arrow.down")
                    }
                    Text("Backups include song details, playlists, likes and listening statistics. Audio files are not copied; they must remain in the app's Documents folder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Your Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "DSM-Music-Backup"
            ) { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try library.restoreBackup(from: Data(contentsOf: url))
                    errorMessage = nil
                } catch { errorMessage = "Could not restore backup: \\(error.localizedDescription)" }
            }
        }
    }

    private func prepareBackup() {
        do {
            exportDocument = LibraryBackupDocument(data: try library.makeBackupData())
            showExporter = true
            errorMessage = nil
        } catch { errorMessage = "Could not create backup: \\(error.localizedDescription)" }
    }
    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\\(minutes / 60) hr \\(minutes % 60) min" : "\\(minutes) min"
    }
}

struct TrackMetadataEditor: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\\.dismiss) private var dismiss
    let track: Track
    @State private var title: String
    @State private var artist: String
    @State private var album: String

    init(track: Track) {
        self.track = track
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
        _album = State(initialValue: track.album)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Song information") {
                    TextField("Title", text: $title)
                    TextField("Artist", text: $artist)
                    TextField("Album", text: $album)
                }
                Section {
                    Text("Changes are saved in DSM Music's library. The original audio file is not modified.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit song")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        library.updateMetadata(for: track, title: title, artist: artist, album: album)
                        dismiss()
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || artist.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
