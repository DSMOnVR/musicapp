import SwiftUI

struct NowPlayingView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(ThemeStore.self) private var themes
    let ns: Namespace.ID
    @Binding var expanded: Bool
    @State private var scrubTime: Double?
    @State private var showLyrics = false

    private var shownTime: Double { scrubTime ?? engine.currentTime }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { expanded = false } label: {
                    Image(systemName: "chevron.down").font(.title3.bold()).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close player")
                Spacer()
                Text("NOW PLAYING").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.muted)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            artwork.padding(.top, 26)
            titleRow.padding(.top, 34)
            scrubber.padding(.top, 18)
            controls.padding(.top, 10)
            Spacer()
            Button { showLyrics = true } label: {
                Text("Lyrics").font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 22).frame(height: 44)
                    .background(Theme.card, in: Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showLyrics) {
            LyricsView().presentationBackground(Theme.bg)
        }
    }

    private var artwork: some View {
        ArtView(data: engine.currentTrack?.artworkData)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 322)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .matchedGeometryEffect(id: "art", in: ns)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(themes.accent).offset(x: 10, y: 10)
            )
            .scaleEffect(engine.isPlaying ? 1 : 0.88)
            .animation(themes.motion, value: engine.isPlaying)
    }

    private var titleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(engine.currentTrack?.title ?? "Nothing playing")
                    .font(.system(size: 30, weight: .bold)).lineLimit(1)
                Text(engine.currentTrack?.artist ?? "")
                    .font(.system(size: 16)).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let progress = engine.duration > 0 ? min(max(shownTime / engine.duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(themes.accent).frame(width: geo.size.width * progress)
                }
                .frame(height: 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            scrubTime = min(max(v.location.x / geo.size.width, 0), 1) * engine.duration
                        }
                        .onEnded { _ in
                            if let t = scrubTime { engine.seek(to: t) }
                            scrubTime = nil
                        }
                )
            }
            .frame(height: 28)
            HStack {
                Text(format(shownTime))
                Spacer()
                Text("-" + format(max(engine.duration - shownTime, 0)))
            }
            .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private var controls: some View {
        HStack {
            Button { engine.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 30)).frame(width: 56, height: 56)
            }
            .accessibilityLabel("Previous song")
            Spacer()
            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 36)).foregroundStyle(Theme.bg)
                    .frame(width: 84, height: 84)
                    .background(themes.accent, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { engine.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 30)).frame(width: 56, height: 56)
            }
            .accessibilityLabel("Next song")
        }
        .padding(.horizontal, 18)
        .buttonStyle(.plain)
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(max(t, 0))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
