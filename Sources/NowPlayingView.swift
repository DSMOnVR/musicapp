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
    @State private var editingTrack: Track?
    private var shownTime: Double { scrubTime ?? engine.currentTime }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3.bold()).foregroundStyle(.white).frame(width: 44, height: 44) }
                Spacer(); Text("NOW PLAYING").font(.caption.bold()).tracking(1.5).foregroundStyle(Theme.muted); Spacer()
                Menu {
                    if let track = engine.currentTrack {
                        Button("Edit song details", systemImage: "pencil") { editingTrack = track }
                    }
                    Button("Sleep timer", systemImage: "moon.zzz") { showSleepTimer = true }
                } label: { Image(systemName: "ellipsis").font(.title3.bold()).foregroundStyle(.white).frame(width: 44, height: 44) }
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
        .sheet(isPresented: $showLyrics) { LyricsSheet().environment(engine).environment(library).presentationDetents([.large]) }
        .sheet(item: $editingTrack) { track in TrackMetadataEditor(track: track).environment(library) }
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
        NavigationStack {
            List {
                ForEach(engine.queue.indices, id: \.self) { index in
                    let track = engine.queue[index]
                    Button { engine.play(index: index) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(track.title)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if index == engine.currentIndex {
                                Image(systemName: "waveform").foregroundStyle(ThemeAccent.color)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { engine.removeQueueItem(at: index) } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: engine.moveQueueItem)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Up Next")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { } } }
        }
        .presentationDetents([.medium, .large])
    }
}


struct LyricsSheet: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(LibraryStore.self) private var library

    private var track: Track? {
        guard let playing = engine.currentTrack else { return nil }
        return library.track(withID: playing.id) ?? playing
    }
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

                    if !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                                    }.padding(.vertical, 16)
                                }
                                .onAppear {
                                    if let activeLineID { proxy.scrollTo(activeLineID, anchor: .center) }
                                }
                                .onChange(of: activeLineID) { _, nextID in
                                    guard let nextID else { return }
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        proxy.scrollTo(nextID, anchor: .center)
                                    }
                                }
                            }
                        } else {
                            ScrollView {
                                Text(lyrics)
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(.vertical, 12)
                            }
                        }
                    } else {
                        Spacer(minLength: 8)
                        switch library.lyricsStatus(for: track) {
                        case .searching:
                            ProgressView().tint(ThemeAccent.color)
                            Text("Searching LRCLIB…").font(.headline)
                            Text("Lyrics will be saved automatically when found.")
                                .font(.caption).foregroundStyle(Theme.muted)
                        case .notFound:
                            ContentUnavailableView(
                                "Lyrics not found",
                                systemImage: "quote.bubble",
                                description: Text("No lyrics were found for this song. Try searching again later.")
                            )
                            Button {
                                library.retryLyrics(for: track)
                            } label: {
                                Label("Search for lyrics again", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered).tint(ThemeAccent.color)
                        case .found:
                            ContentUnavailableView("No readable lyrics", systemImage: "text.quote")
                        }
                        Spacer(minLength: 8)
                    }


                } else {
                    ContentUnavailableView("Nothing playing", systemImage: "music.note")
                }
            }
            .padding(24).foregroundStyle(.white).background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Lyrics").navigationBarTitleDisplayMode(.inline)

        }
        .task(id: track?.id) {
            if let track { library.fetchLyricsIfNeeded(for: track) }
        }
        .presentationDetents([.large])
    }


}
