import SwiftUI

struct ImportView: View {
    @Environment(LibraryStore.self) private var library
    var onChooseFiles: () -> Void
    var onChooseFolder: () -> Void
    var isImporting: Bool
    @State private var autoTag = true
    @State private var fetchArt = true
    @State private var syncedLyrics = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Import").font(.system(size: 34, weight: .bold))
                VStack(spacing: 12) {
                    Image(systemName: "plus.app.fill").font(.system(size: 48)).foregroundStyle(ThemeAccent.color)
                    Text(isImporting ? "Importing your music…" : "Add music to your library").font(.title3.bold())
                    Text("MP3, M4A, AAC, ALAC, WAV, FLAC* and other iOS-supported audio formats").font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    Button("Choose audio files", action: onChooseFiles).buttonStyle(AccentButtonStyle()).disabled(isImporting)
                    Button("Choose a folder", action: onChooseFolder).font(.subheadline.bold()).foregroundStyle(.white).padding(.vertical, 8).disabled(isImporting)
                }.frame(maxWidth: .infinity).padding(24).background(Theme.card, in: RoundedRectangle(cornerRadius: 26)).overlay(RoundedRectangle(cornerRadius: 26).stroke(ThemeAccent.color.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [8, 8])))
                VStack(alignment: .leading, spacing: 16) {
                    Text("Import options").font(.title3.bold())
                    Toggle("Read song details from files", isOn: $autoTag)
                    Toggle("Use embedded cover art", isOn: $fetchArt)
                    Toggle("Look for synced lyrics", isOn: $syncedLyrics).disabled(true)
                    Text("Lyrics lookup will be added in a later version. Your imported audio stays on this device.").font(.caption).foregroundStyle(Theme.muted)
                }.tint(ThemeAccent.color).padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
                if let message = library.lastImportMessage { Text(message).font(.subheadline).foregroundStyle(ThemeAccent.color) }
                if !library.importErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) { Text("Some files couldn't be imported").font(.headline).foregroundStyle(.pink); ForEach(library.importErrors, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(Theme.muted) } }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recently added").font(.title3.bold())
                    ForEach(library.tracks.suffix(5).reversed()) { track in
                        HStack(spacing: 12) { ArtworkView(track: track).frame(width: 44, height: 44); VStack(alignment: .leading) { Text(track.title).font(.subheadline.bold()); Text(track.artist).font(.caption).foregroundStyle(Theme.muted) }; Spacer(); Image(systemName: "checkmark.circle.fill").foregroundStyle(ThemeAccent.color) }
                    }
                }
            }.padding(22)
        }.foregroundStyle(.white)
    }
}
