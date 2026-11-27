import SwiftUI
import UniformTypeIdentifiers

struct LibraryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

struct PersonalLibraryToolsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: LibraryBackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var playlistName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Listening statistics") {
                    LabeledContent("Songs in library", value: "\(library.tracks.count)")
                    LabeledContent("Artists", value: "\(library.artists.count)")
                    LabeledContent("Albums", value: "\(library.albums.count)")
                    LabeledContent("Listening time", value: duration(library.listeningSeconds))
                    if let top = library.mostPlayed.first, (library.playCounts[top.id] ?? 0) > 0 {
                        LabeledContent("Most played", value: "\(top.title) · \(library.playCounts[top.id] ?? 0) plays")
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
                                Text("\(library.tracks(in: playlist).count) songs").font(.caption).foregroundStyle(.secondary)
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
                    Text("Backups include song details, playlists, likes and listening statistics. Audio files are not included; restore works when the matching audio files are already in this app's Documents folder.")
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
                } catch { errorMessage = "Could not restore backup: \(error.localizedDescription)" }
            }
        }
    }

    private func prepareBackup() {
        do {
            exportDocument = LibraryBackupDocument(data: try library.makeBackupData())
            showExporter = true
            errorMessage = nil
        } catch { errorMessage = "Could not create backup: \(error.localizedDescription)" }
    }
    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
    }
}

struct TrackMetadataEditor: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\\.dismiss) private var dismiss
    let track: Track
    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var lyrics: String
    @State private var showLyricsPicker = false
    @State private var lyricsMessage: String?

    init(track: Track) {
        self.track = track
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
        _album = State(initialValue: track.album)
        _lyrics = State(initialValue: track.lyrics ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(spacing: 12) {
                        ArtworkView(track: track)
                            .frame(width: 190, height: 190)
                            .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
                        Text("EDIT SONG")
                            .font(.caption.weight(.bold))
                            .tracking(2)
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 16) {
                        editorHeading("Song Details")
                        metadataField("Title", text: $title)
                        metadataField("Artist", text: $artist)
                        metadataField("Album", text: $album)
                    }
                    .padding(18)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            editorHeading("Lyrics")
                            Spacer()
                            Text(lyrics.isEmpty ? "Not added" : "Saved locally")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Text("Add or edit lyrics for offline listening.")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        TextEditor(text: $lyrics)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .frame(minHeight: 170)
                            .padding(8)
                            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14))
                        Button {
                            showLyricsPicker = true
                        } label: {
                            Label("Import .LRC or .TXT file", systemImage: "document.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color(white: 0.28), in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        if let lyricsMessage {
                            Text(lyricsMessage)
                                .font(.caption)
                                .foregroundStyle(lyricsMessage.hasPrefix("Couldn't") ? .red : Theme.muted)
                        }
                    }
                    .padding(18)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    Text("Changes are saved in DSM Music. The original audio file is not modified.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        library.updateMetadata(for: track, title: title, artist: artist, album: album)
                        library.updateLyrics(for: track, text: lyrics)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || artist.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showLyricsPicker) {
                LyricsDocumentPicker { result in
                    showLyricsPicker = false
                    importLyrics(result)
                }
                .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func editorHeading(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
    }

    private func metadataField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(Theme.muted)
            TextField(label, text: text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(13)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func importLyrics(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let ext = url.pathExtension.lowercased()
            guard ext == "lrc" || ext == "txt" else {
                lyricsMessage = "Choose an .lrc or .txt file."
                return
            }
            let data = try Data(contentsOf: url)
            let decoded = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .isoLatin1)
            guard let text = decoded,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                lyricsMessage = "That file is empty or unreadable."
                return
            }
            lyrics = text
            library.updateLyrics(for: track, text: text)
            lyricsMessage = "Lyrics imported and saved for offline use."
        } catch is CancellationError {
            // The user cancelled the document picker.
        } catch {
            lyricsMessage = "Couldn't import lyrics: \\(error.localizedDescription)"
        }
    }
}
