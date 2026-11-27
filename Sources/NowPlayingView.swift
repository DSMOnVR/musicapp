import SwiftUI
import UniformTypeIdentifiers

struct NowPlayingView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(AppTheme.self) private var appTheme
    @Environment(\.dismiss) private var dismiss
    @State private var scrubTime: Double?
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showSleepTimer = false
    private var shownTime: Double { scrubTime ?? engine.currentTime }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3.bold()).foregroundStyle(.white).frame(width: 44, height: 44) }
                Spacer(); Text("NOW PLAYING").font(.caption.bold()).tracking(1.5).foregroundStyle(Theme.muted); Spacer()
                Menu { Button("Add to queue", systemImage: "text.badge.plus") { }; Button("Sleep timer", systemImage: "moon.zzz") { showSleepTimer = true } } label: { Image(systemName: "ellipsis").font(.title3.bold()).foregroundStyle(.white).frame(width: 44, height: 44) }
            }.padding(.top, 8)
            Spacer(minLength: 18)
            artwork
                .padding(.horizontal, 12)
                .frame(maxHeight: 350)
            titleRow.padding(.top, 34)
            scrubber.padding(.top, 22)
            controls.padding(.top, 18)
            HStack(spacing: 12) {
                Button { showLyrics = true } label: { Label("Lyrics", systemImage: "quote.bubble").font(.subheadline.bold()) }
                Button { showQueue = true } label: { Label("Queue", systemImage: "list.number").font(.subheadline.bold()) }
                Button { showSleepTimer = true } label: { Label("Sleep timer", systemImage: "moon.zzz").font(.subheadline.bold()) }
            }.buttonStyle(.plain).foregroundStyle(.white).padding(.top, 28)
            Spacer(minLength: 18)
        }
        .padding(.horizontal, 24).foregroundStyle(.white).background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showQueue) { QueueSheet().environment(engine) }
        .sheet(isPresented: $showLyrics) { LyricsSheet().environment(engine).environment(library) }
        .confirmationDialog("Sleep timer", isPresented: $showSleepTimer, titleVisibility: .visible) {
            Button("15 minutes") { engine.setSleepTimer(minutes: 15) }
            Button("30 minutes") { engine.setSleepTimer(minutes: 30) }
            Button("45 minutes") { engine.setSleepTimer(minutes: 45) }
            Button("60 minutes") { engine.setSleepTimer(minutes: 60) }
            Button("Cancel timer", role: .destructive) { engine.cancelSleepTimer() }
        }
    }
    private var artwork: some View {
        ArtworkView(track: engine.currentTrack ?? Track(title: "Your music", artist: "Offline player", album: "", url: URL(fileURLWithPath: "/"), duration: 0, artworkData: nil))
            .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 30).fill(appTheme.accent).offset(x: 9, y: 9))
    }
    private var titleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(engine.currentTrack?.title ?? "Nothing playing").font(.system(size: 29, weight: .bold)).lineLimit(1)
                Text(engine.currentTrack?.artist ?? "Import songs to get started").font(.system(size: 16)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let track = engine.currentTrack {
                Button { library.toggleLiked(track) } label: { Image(systemName: library.isLiked(track) ? "heart.fill" : "heart").font(.title2).foregroundStyle(library.isLiked(track) ? appTheme.accent : .white) }
            }
        }
    }
    private var scrubber: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let progress = engine.duration > 0 ? min(max(shownTime / engine.duration, 0), 1) : 0
                ZStack(alignment: .leading) { Capsule().fill(Color.white.opacity(0.15)); Capsule().fill(appTheme.accent).frame(width: geo.size.width * progress) }
                    .frame(height: 8).frame(maxHeight: .infinity).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in scrubTime = min(max(v.location.x / geo.size.width, 0), 1) * engine.duration }.onEnded { _ in if let t = scrubTime { engine.seek(to: t) }; scrubTime = nil })
            }.frame(height: 24)
            HStack { Text(format(shownTime)); Spacer(); Text("-" + format(max(engine.duration - shownTime, 0))) }.font(.caption).foregroundStyle(Theme.muted)
        }
    }
    private var controls: some View {
        HStack {
            Button { engine.previous() } label: { Image(systemName: "backward.end.fill").font(.title2).frame(width: 56, height: 56) }
            Spacer()
            Button { engine.togglePlayPause() } label: { Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 31, weight: .bold)).foregroundStyle(.black).frame(width: 82, height: 82).background(appTheme.accent, in: RoundedRectangle(cornerRadius: 28, style: .continuous)) }
            Spacer()
            Button { engine.next() } label: { Image(systemName: "forward.end.fill").font(.title2).frame(width: 56, height: 56) }
        }.buttonStyle(.plain).padding(.horizontal, 18)
    }
    private func format(_ t: TimeInterval) -> String { let s = Int(max(t, 0)); return String(format: "%d:%02d", s / 60, s % 60) }
}

struct QueueSheet: View {
    @Environment(PlayerEngine.self) private var engine
    var body: some View {
        NavigationStack { List { ForEach(engine.queue.indices, id: \.self) { index in let track = engine.queue[index]; Button { engine.play(index: index) } label: { HStack { VStack(alignment: .leading) { Text(track.title); Text(track.artist).font(.caption).foregroundStyle(.secondary) }; Spacer(); if index == engine.currentIndex { Image(systemName: "waveform").foregroundStyle(ThemeAccent.color) } } } } }.navigationTitle("Up Next").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { } } } }
        .presentationDetents([.medium, .large])
    }
}

struct LyricsSheet: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @State private var showImporter = false
    @State private var importError: String?

    private var track: Track? { engine.currentTrack }
    private var lyrics: String { track?.lyrics ?? "" }
    private var timedLines: [TimedLyricLine] { LyricsParser.lines(from: lyrics) }
    private var activeLineID: Int? {
        timedLines.last(where: { $0.time <= engine.currentTime })?.id ?? timedLines.first?.id
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let track {
                    Text(track.title).font(.title2.bold())
                    Text(track.artist).foregroundStyle(Theme.muted)

                    if !timedLines.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 18) {
                                    ForEach(timedLines) { line in
                                        Text(line.text.isEmpty ? "♪" : line.text)
                                            .font(.system(size: 22, weight: activeLineID == line.id ? .bold : .semibold))
                                            .foregroundStyle(activeLineID == line.id ? ThemeAccent.color : .white.opacity(0.48))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .id(line.id)
                                    }
                                }
                                .padding(.vertical, 16)
                            }
                            .onAppear {
                                if let activeLineID { proxy.scrollTo(activeLineID, anchor: .center) }
                            }
                            .onChange(of: activeLineID) { nextID in
                                guard let nextID else { return }
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo(nextID, anchor: .center)
                                }
                            }
                        }
                    } else if lyrics.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            "Finding lyrics…",
                            systemImage: "quote.bubble",
                            description: Text("DSM Music is checking Lyricsify. If lyrics are found, they’ll be saved for offline playback. You can also import an .lrc or .txt file.")
                        )
                        Spacer()
                    } else {
                        ScrollView {
                            Text(lyrics)
                                .font(.system(size: 20, weight: .semibold))
                                .lineSpacing(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                        }
                    }

                    if let importError {
                        Text(importError).font(.caption).foregroundStyle(.red)
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label(lyrics.isEmpty ? "Import lyrics" : "Replace lyrics", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ThemeAccent.color)
                } else {
                    ContentUnavailableView("Nothing playing", systemImage: "music.note")
                }
            }
            .padding(24)
            .foregroundStyle(.white)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.plainText, UTType(filenameExtension: "lrc") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first, let track else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard let text = String(data: data, encoding: .utf8)
                        ?? String(data: data, encoding: .utf16) else {
                        throw NSError(domain: "LyricsImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "This lyrics file could not be read as text."])
                    }
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw NSError(domain: "LyricsImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "The lyrics file is empty."])
                    }
                    library.updateLyrics(for: track, text: text)
                    importError = nil
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
        .task(id: track?.id) {
            if let track { library.fetchLyricsIfNeeded(for: track) }
        }
        .presentationDetents([.medium, .large])
    }
}
