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
    @State private var showCredits = false
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
                    Button("Song credits", systemImage: "person.text.rectangle") { showCredits = true }
                    Button(engine.autoplayEnabled ? "Turn Autoplay Off" : "Turn Autoplay On", systemImage: "infinity") { engine.autoplayEnabled.toggle() }
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
                AirPlayRoutePicker().frame(width: 34, height: 34)
            }.buttonStyle(.plain).foregroundStyle(.white).padding(.top, 28)
            Spacer(minLength: 18)
        }
        .padding(.horizontal, 24)
        .foregroundStyle(.white)
        .background(dynamicBackground)
        .animation(.easeInOut(duration: 0.55), value: engine.currentTrack?.id)
        .sheet(isPresented: $showQueue) { QueueSheet().environment(engine) }
        .sheet(isPresented: $showLyrics) { LyricsSheet().environment(engine).environment(library).presentationDetents([.large]) }
        .sheet(isPresented: $showCredits) {
            if let track = engine.currentTrack {
                SongCreditsView(track: track).presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $editingTrack) { track in TrackMetadataEditor(track: track).environment(library) }
        .confirmationDialog("Sleep timer", isPresented: $showSleepTimer, titleVisibility: .visible) {
            Button("15 minutes") { engine.setSleepTimer(minutes: 15) }
            Button("30 minutes") { engine.setSleepTimer(minutes: 30) }
            Button("45 minutes") { engine.setSleepTimer(minutes: 45) }
            Button("60 minutes") { engine.setSleepTimer(minutes: 60) }
            Button("Cancel timer", role: .destructive) { engine.cancelSleepTimer() }
        }
    }
    private var dynamicBackground: some View {
        ZStack {
            Theme.bg
            if let data = engine.currentTrack?.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: 72)
                    .overlay(Color.black.opacity(0.58))
                    .transition(.opacity)
            } else {
                LinearGradient(colors: [appTheme.accent.opacity(0.24), Theme.bg, Theme.bg],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(colors: [.black.opacity(0.18), .clear, .black.opacity(0.48)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var artwork: some View {
        ArtworkView(track: engine.currentTrack ?? Track(title: "Your music", artist: "Offline player", album: "", url: URL(fileURLWithPath: "/"), duration: 0, artworkData: nil))
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 28, x: 0, y: 18)
            .scaleEffect(engine.isPlaying ? 1 : 0.985)
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: engine.isPlaying)
    }
    private var titleRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(engine.currentTrack?.title ?? "Nothing playing")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Text(engine.currentTrack?.artist ?? "Import songs to get started")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                NowPlayingWaveform(isPlaying: engine.isPlaying, tint: appTheme.accent)
                    .frame(width: 66, height: 17)
                    .padding(.top, 4)
            }
            Spacer(minLength: 8)
            if let track = engine.currentTrack {
                Button { library.toggleLiked(track) } label: {
                    Image(systemName: library.isLiked(track) ? "heart.fill" : "heart")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(library.isLiked(track) ? appTheme.accent : .white)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: library.isLiked(track))
            }
        }
    }
    private var scrubber: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                let progress = engine.duration > 0 ? min(max(shownTime / engine.duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.20))
                    Capsule().fill(LinearGradient(colors: [.white, appTheme.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * progress, 0))
                        .shadow(color: appTheme.accent.opacity(0.55), radius: 7)
                }
                .frame(height: 5)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in scrubTime = min(max(v.location.x / geo.size.width, 0), 1) * engine.duration }
                    .onEnded { _ in if let t = scrubTime { engine.seek(to: t) }; scrubTime = nil })
            }
            .frame(height: 22)
            HStack {
                Text(format(shownTime))
                Spacer()
                Text("-" + format(max(engine.duration - shownTime, 0)))
            }
            .font(.system(.caption, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.65))
        }
    }
    private var controls: some View {
        HStack(spacing: 0) {
            Button { engine.previous() } label: {
                Image(systemName: "backward.end.fill").font(.title2)
                    .frame(width: 58, height: 58)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            }
            Spacer()
            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(.black)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 82, height: 82)
                    .background(LinearGradient(colors: [.white, appTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: appTheme.accent.opacity(0.28), radius: 18, x: 0, y: 8)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: engine.isPlaying)
            Spacer()
            Button { engine.next() } label: {
                Image(systemName: "forward.end.fill").font(.title2)
                    .frame(width: 58, height: 58)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
    private func format(_ t: TimeInterval) -> String { let s = Int(max(t, 0)); return String(format: "%d:%02d", s / 60, s % 60) }
}

private struct NowPlayingWaveform: View {
    let isPlaying: Bool
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<13, id: \.self) { index in
                    let movement = abs(sin(phase * 4.2 + Double(index) * 0.72))
                    Capsule()
                        .fill(tint.opacity(0.9))
                        .frame(width: 3, height: isPlaying ? 4 + movement * 13 : 4 + Double(index % 3) * 1.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .accessibilityLabel(isPlaying ? "Music playing" : "Music paused")
    }
}

struct QueueSheet: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = engine.currentTrack {
                    Section("Now Playing") {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform").foregroundStyle(ThemeAccent.color)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(current.title).font(.headline)
                                Text(current.artist).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("PLAYING").font(.caption2.bold()).tracking(1).foregroundStyle(ThemeAccent.color)
                        }
                    }
                }
                Section("Up Next · \(engine.currentIndex.map { max(engine.queue.count - $0 - 1, 0) } ?? engine.queue.count) songs") {
                    ForEach(Array(engine.queue.enumerated()), id: \.element.id) { index, track in
                        if index != engine.currentIndex {
                            Button { engine.play(index: index) } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title).foregroundStyle(.primary).lineLimit(1)
                                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                    }
                    .onMove(perform: engine.moveQueueItem)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Shuffle upcoming", systemImage: "shuffle") { engine.shuffleUpcoming() }
                            .disabled(engine.queue.count - (engine.currentIndex ?? -1) <= 2)
                        Button("Clear upcoming", systemImage: "trash", role: .destructive) { engine.clearUpcoming() }
                            .disabled(engine.queue.count <= 1)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
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
    private var lyricTime: TimeInterval { engine.currentTime }
    private var activeIndex: Int? {
        timedLines.lastIndex(where: { $0.time <= lyricTime })
    }
    private var activeLineID: Int? {
        activeIndex.map { timedLines[$0].id }
    }

    private var hasWordSyncedLyrics: Bool { timedLines.contains(where: \.hasWordTiming) }

    private func highlightedLine(_ line: TimedLyricLine, index: Int) -> AttributedString {
        var result = AttributedString()
        let isActiveLine = activeIndex == index

        if line.hasWordTiming {
            let activeWordIndex = isActiveLine ? line.words.lastIndex(where: { $0.time <= lyricTime }) : nil
            for (wordIndex, word) in line.words.enumerated() {
                let cleanWord = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanWord.isEmpty else { continue }
                if !result.characters.isEmpty { result.append(AttributedString(" ")) }
                var part = AttributedString(cleanWord)
                part.foregroundColor = wordIndex == activeWordIndex
                    ? appTheme.accent
                    : .white.opacity(0.38)
                result.append(part)
            }
            return result
        }

        // Standard LRC provides line timestamps only. Highlight the active
        // line instead of guessing word timings that can drift out of sync.
        var part = AttributedString(line.text)
        part.foregroundColor = isActiveLine ? appTheme.accent : .white.opacity(0.38)
        result.append(part)
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
