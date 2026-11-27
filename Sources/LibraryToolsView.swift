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
    @State private var confirmDuplicateRemoval = false
    @State private var showHistoryCalendar = false

    var body: some View {
        NavigationStack {
            List {
                Section("Listening history") {
                    Button { showHistoryCalendar = true } label: {
                        Label("Open listening calendar", systemImage: "calendar")
                    }
                    if let latest = library.dailyPlayCounts.max(by: { $0.key < $1.key }) {
                        LabeledContent("Most active day", value: "\(latest.key) · \(latest.value) plays")
                    }
                }
                Section("Listening statistics") {
                    LabeledContent("Songs in library", value: "\(library.tracks.count)")
                    LabeledContent("Artists", value: "\(library.artists.count)")
                    LabeledContent("Albums", value: "\(library.albums.count)")
                    LabeledContent("Listening time", value: duration(library.listeningSeconds))
                    if let top = library.mostPlayed.first, (library.playCounts[top.id] ?? 0) > 0 {
                        LabeledContent("Most played", value: "\(top.title) · \(library.playCounts[top.id] ?? 0) plays")
                    }
                }
                Section("Duplicate finder") {
                    if library.duplicateGroups.isEmpty {
                        Label("No duplicate songs found", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Duplicate groups", value: "\(library.duplicateGroups.count)")
                        LabeledContent("Extra copies", value: "\(library.duplicateGroups.reduce(0) { $0 + $1.count - 1 })")
                        ForEach(library.duplicateGroups, id: \.first?.id) { group in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group[0].title).font(.headline)
                                Text("\(group[0].artist) · \(group.count) copies")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button(role: .destructive) { confirmDuplicateRemoval = true } label: {
                            Label("Remove extra copies", systemImage: "trash")
                        }
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
            .confirmationDialog("Remove duplicate copies?", isPresented: $confirmDuplicateRemoval, titleVisibility: .visible) {
                Button("Remove duplicates", role: .destructive) { library.removeDuplicateTracks() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The copy with the most plays is kept. Other matching copies are removed from your library.")
            }
            .sheet(isPresented: $showHistoryCalendar) {
                ListeningHistoryCalendarView().environment(library)
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
    @Environment(\.dismiss) private var dismiss
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


struct ListeningHistoryCalendarView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var displayedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now

    private var monthDays: [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else { return [] }
        let weekdayOffset = (calendar.component(.weekday, from: first) + 5) % 7
        return Array(repeating: nil, count: weekdayOffset) + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) as Date? }
    }

    private func count(for date: Date) -> Int {
        library.dailyPlayCounts[LibraryStore.historyDateFormatter.string(from: date)] ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack {
                    Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(displayedMonth.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Spacer()
                    Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(Calendar.current.isDate(displayedMonth, equalTo: .now, toGranularity: .month))
                }
                .font(.title3)
                .padding(.horizontal, 8)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 10) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self + UUID().uuidString) { day in
                        Text(day).font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                        if let date {
                            let plays = count(for: date)
                            VStack(spacing: 4) {
                                Text(date.formatted(.dateTime.day())).font(.subheadline.weight(plays > 0 ? .bold : .regular))
                                Circle().fill(plays == 0 ? Color.clear : ThemeAccent.color.opacity(min(0.25 + Double(plays) * 0.12, 1)))
                                    .frame(width: 7, height: 7)
                            }
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(Calendar.current.isDateInToday(date) ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 10))
                        } else {
                            Color.clear.frame(height: 42)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Daily listening").font(.headline)
                    let entries = library.dailyPlayCounts
                        .compactMap { key, value -> (Date, Int)? in
                            guard let date = LibraryStore.historyDateFormatter.date(from: key) else { return nil }
                            return (date, value)
                        }
                        .filter { Calendar.current.isDate($0.0, equalTo: displayedMonth, toGranularity: .month) }
                        .sorted { $0.0 > $1.0 }
                    if entries.isEmpty {
                        Text("No listening history for this month yet.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(entries, id: \.0) { date, plays in
                            HStack {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text("\(plays) plays").foregroundStyle(.secondary)
                            }.font(.subheadline)
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Listening History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func changeMonth(_ offset: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) {
            displayedMonth = next
        }
    }
}
