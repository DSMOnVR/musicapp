import SwiftUI

struct NowPlayingView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var scrubTime: Double?

    private var shownTime: Double { scrubTime ?? engine.currentTime }

    var body: some View {
        VStack(spacing: 0) {
            Text("NOW PLAYING")
                .font(.caption.weight(.bold)).tracking(1.2)
                .foregroundStyle(Theme.muted)
                .padding(.top, 14)
            artwork.padding(.top, 34)
            titleRow.padding(.top, 34)
            scrubber.padding(.top, 18)
            controls.padding(.top, 10)
            Spacer()
        }
        .padding(.horizontal, 24)
        .foregroundStyle(.white)
        .background(Theme.bg.ignoresSafeArea())
    }

    private var artwork: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 322)
            .overlay {
                if let data = engine.currentTrack?.artworkData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Theme.accent).offset(x: 10, y: 10)
            )
            .scaleEffect(engine.isPlaying ? 1 : 0.88)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: engine.isPlaying)
    }

    private var titleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(engine.currentTrack?.title ?? "Nothing playing")
                    .font(.system(size: 30, weight: .bold)).lineLimit(1)
                Text(engine.currentTrack?.artist ?? "Tap + to add songs")
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
                    Capsule().fill(Theme.accent).frame(width: geo.size.width * progress)
                }
                .frame(height: 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let p = min(max(v.location.x / geo.size.width, 0), 1)
                            scrubTime = p * engine.duration
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
                Image(systemName: "backward.fill").font(.system(size: 30))
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Previous song")
            Spacer()
            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 36)).foregroundStyle(Theme.bg)
                    .frame(width: 84, height: 84)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { engine.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 30))
                    .frame(width: 56, height: 56)
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
