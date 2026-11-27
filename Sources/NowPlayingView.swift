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
    @Environment(AppTheme.self) private var appTheme

    private var track: Track? {
        guard let playing = engine.currentTrack else { return nil }
        return library.track(withID: playing.id) ?? playing
    }
    private var lyrics: String { track?.lyrics ?? "" }
    private var timedLines: [TimedLyricLine] { LyricsParser.lines(from: lyrics) }
    private var activeIndex: Int? {
        timedLines.lastIndex(where: { $0.time <= engine.currentTime }) ?? (timedLines.isEmpty ? nil : 0)
    }
    private var activeLineID: Int? {
        activeIndex.map { timedLines[$0].id }
    }

    private func highlightedLine(_ line: TimedLyricLine, index: Int) -> AttributedString {
        let words = line.text.split(separator: " ", omittingEmptySubsequences: false)
        let nextTime = index + 1 < timedLines.count ? timedLines[index + 1].time : line.time + 4.0
        let lineDuration = max(nextTime - line.time, 0.8)
        let progress = min(max((engine.currentTime - line.time) / lineDuration, 0), 0.999)
        let litWord = min(Int(progress * Double(max(words.count, 1))), max(words.count - 1, 0))

        var result = AttributedString()
        for (wordIndex, word) in words.enumerated() {
            var part = AttributedString(String(word))
            if wordIndex < litWord {
                part.foregroundColor = .white
            } else if wordIndex == litWord {
                part.foregroundColor = Color(white: 0.78)
            } else {
                part.foregroundColor = .white.opacity(0.34)
            }
            result.append(part)
            if wordIndex < words.count - 1 {
                result.append(AttributedString(" "))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if let track {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.title)
                                .font(.system(size: 18, weight: .bold))
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 12)
                        .padding(.bottom, 20)

                        if !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            if !timedLines.isEmpty {
                                ScrollViewReader { proxy in
                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 23) {
                                            ForEach(Array(timedLines.enumerated()), id: \.element.id) { index, line in
                                                let isActive = activeLineID == line.id
                                                Text(highlightedLine(line, index: index))
                                                    .font(.system(size: isActive ? 34 : 27, weight: isActive ? .bold : .semibold, design: .rounded))
                                                    .tracking(isActive ? -0.8 : -0.5)
                                                    .lineSpacing(7)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .scaleEffect(isActive ? 1.0 : 0.97, anchor: .leading)
                                                    .opacity(isActive ? 1 : 0.68)
                                                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isActive)
                                                    .id(line.id)
                                            }
                                        }
                                        .padding(.horizontal, 24)
                                        .padding(.top, 24)
                                        .padding(.bottom, 180)
                                    }
                                    .scrollIndicators(.hidden)
                                    .onAppear {
                                        if let activeLineID { proxy.scrollTo(activeLineID, anchor: .center) }
                                    }
                                    .onChange(of: activeLineID) { _, nextID in
                                        guard let nextID else { return }
                                        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                                            proxy.scrollTo(nextID, anchor: .center)
                                        }
                                    }
                                }
                            } else {
                                ScrollView {
                                    Text(lyrics)
                                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                        .padding(24)
                                }
                            }
                        } else {
                            Spacer()
                            VStack(spacing: 14) {
                                Image(systemName: "quote.bubble")
                                    .font(.system(size: 38, weight: .light))
                                    .foregroundStyle(appTheme.accent)
                                switch library.lyricsStatus(for: track) {
                                case .searching:
                                    ProgressView().tint(appTheme.accent)
                                    Text("Finding your lyrics").font(.headline)
                                    Text("They’ll be saved for offline listening.")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                case .notFound:
                                    Text("Lyrics not found").font(.title3.bold())
                                    Text("Try searching again for this song.")
                                        .font(.subheadline).foregroundStyle(Theme.muted)
                                    Button {
                                        library.retryLyrics(for: track)
                                    } label: {
                                        Label("Search again", systemImage: "arrow.clockwise")
                                            .font(.subheadline.bold())
                                            .padding(.horizontal, 18).padding(.vertical, 11)
                                            .background(.ultraThinMaterial, in: Capsule())
                                    }
                                    .tint(.white)
                                case .found:
                                    Text("No readable lyrics").font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            Spacer()
                        }
                    }
                } else {
                    ContentUnavailableView("Nothing playing", systemImage: "music.note")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                    Text("SYNCED LYRICS")
                        .font(.caption2.weight(.bold))
                        .tracking(1.5)
                }
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                .padding(.bottom, 14)
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task(id: track?.id) {
            if let track { library.fetchLyricsIfNeeded(for: track) }
        }
        .presentationDetents([.large])
    }
}
