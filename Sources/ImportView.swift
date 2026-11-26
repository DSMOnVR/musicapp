import SwiftUI

struct ImportView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ThemeStore.self) private var themes
    @AppStorage("serverURL") private var server = ""
    @AppStorage("findLyrics") private var findLyrics = true
    @AppStorage("autoTag") private var autoTag = true
    @State private var link = ""
    @State private var picking = false
    @State private var busy = false
    @State private var message = ""
    @State private var error: String?
    @State private var reviewed: [Track] = []
    @State private var showReview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Import").font(.system(size: 32, weight: .bold)).padding(.top, 14)

                Button { picking = true } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.bg)
                            .frame(width: 56, height: 56)
                            .background(themes.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        Text("Choose music files").font(.system(size: 20, weight: .bold))
                        Text("MP3, FLAC, AAC, ALAC, WAV").font(.caption).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity).frame(height: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(themes.accent, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    )
                }
                .buttonStyle(.plain)
                .disabled(busy)

                HStack(spacing: 8) {
                    TextField("Paste a link", text: $link)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .padding(.horizontal, 18).frame(height: 48)
                        .background(Theme.card, in: Capsule())
                    Button { getLink() } label: {
                        Text("Get MP3").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.bg)
                            .padding(.horizontal, 18).frame(height: 48)
                            .background(themes.accent, in: Capsule())
                    }
                    .disabled(busy || link.isEmpty)
                }
                TextField("Server address, e.g. http://100.64.0.1:8000", text: $server)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .font(.system(size: 14)).padding(.horizontal, 18).frame(height: 44)
                    .background(Theme.card, in: Capsule())

                Text("Auto-tag").font(.system(size: 20, weight: .bold)).padding(.top, 8)
                Toggle("Find album, artist and cover art", isOn: $autoTag)
                Toggle("Find synced lyrics", isOn: $findLyrics)

                if busy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(library.status.isEmpty ? message : library.status).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }
                if let error { Text(error).font(.subheadline).foregroundStyle(Theme.warn) }
            }
            .font(.system(size: 15, weight: .bold))
            .tint(themes.accent)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .failure(let e): error = e.localizedDescription
            case .success(let urls):
                Task {
                    busy = true; error = nil; message = "Importing…"
                    let added = await library.importFiles(urls, secured: true)
                    finish(added, expected: urls.count)
                    busy = false
                }
            }
        }
        .sheet(isPresented: $showReview) {
            ImportReviewView(tracks: reviewed).presentationBackground(Theme.bg)
        }
    }

    private func getLink() {
        let l = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !l.isEmpty else { return }
        Task {
            busy = true; error = nil; message = "Downloading…"
            do {
                let file = try await DownloadService.fetchMP3(link: l, server: server)
                message = "Importing…"
                let added = await library.importFiles([file], secured: false)
                finish(added, expected: 1)
                link = ""
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func finish(_ added: [Track], expected: Int) {
        reviewed = added
        showReview = !added.isEmpty
        if added.count < expected {
            error = "Couldn't import \(expected - added.count) file(s). If they're in iCloud, download them in Files first."
        }
    }
}

struct ImportReviewView: View {
    let tracks: [Track]
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeStore.self) private var themes

    private func matched(_ t: Track) -> Bool {
        t.artist != "Unknown Artist" && t.album != "Unknown Album" && t.artworkData != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Review").font(.system(size: 32, weight: .bold)).padding(.top, 28)
            Text("\(tracks.filter { matched($0) }.count) of \(tracks.count) matched · \(tracks.filter { $0.lrc != nil }.count) with synced lyrics")
                .font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 6)
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(tracks) { t in
                        HStack(spacing: 12) {
                            ArtView(data: t.artworkData).frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                                Text("\(t.artist) · \(t.album)").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            Text(matched(t) ? "Matched" : "Check")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(matched(t) ? themes.accent : Theme.warn)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Theme.card, in: Capsule())
                        }
                    }
                }
                .padding(.top, 22)
            }
            Button { dismiss() } label: {
                Text("Done").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(themes.accent, in: Capsule())
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
        .foregroundStyle(.white)
    }
}
