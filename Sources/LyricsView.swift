import SwiftUI

struct LyricsView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(ThemeStore.self) private var themes
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [LyricLine] = []
    @State private var searching = false

    private var activeIndex: Int {
        lines.lastIndex(where: { $0.time <= engine.currentTime + 0.3 }) ?? -1
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtView(data: engine.currentTrack?.artworkData).frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.currentTrack?.title ?? "").font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Text(engine.currentTrack?.artist ?? "").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.title3.bold()).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close lyrics")
            }
            .padding(.top, 24)

            if lines.isEmpty {
                Spacer()
                Text("No synced lyrics yet").font(.system(size: 20, weight: .bold))
                Button { findLyrics() } label: {
                    Text(searching ? "Searching…" : "Find lyrics").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.bg).padding(.horizontal, 22).frame(height: 44)
                        .background(themes.accent, in: Capsule())
                }
                .disabled(searching).padding(.top, 12)
                Spacer()
            } else {
                Text("TAP A LINE TO JUMP").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(lines) { line in
                                let active = line.id == activeIndex
                                Button { engine.seek(to: line.time) } label: {
                                    Text(line.text)
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundStyle(active ? themes.accent : Theme.muted)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                        .scaleEffect(active ? 1.1 : 1, anchor: .leading)
                                        .animation(themes.motion, value: activeIndex)
                                }
                                .buttonStyle(.plain)
                                .id(line.id)
                            }
                        }
                        .padding(.vertical, 140)
                    }
                    .onChange(of: activeIndex) { _, new in
                        guard new >= 0 else { return }
                        withAnimation(themes.motion) { proxy.scrollTo(new, anchor: .center) }
                    }
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                            .init(color: .black, location: 0.88), .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    )
                }
            }

            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28)).foregroundStyle(Theme.bg)
                    .frame(width: 68, height: 68)
                    .background(themes.accent, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .foregroundStyle(.white)
        .task(id: engine.currentTrack?.id) { reload() }
    }

    private func reload() {
        lines = library.track(id: engine.currentTrack?.id)?.lrc.map(LRC.parse) ?? []
    }

    private func findLyrics() {
        guard let id = engine.currentTrack?.id else { return }
        Task {
            searching = true
            await library.fetchLyrics(for: id)
            reload()
            searching = false
        }
    }
}
