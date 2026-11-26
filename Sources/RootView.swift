import SwiftUI

enum AppTab: String, CaseIterable {
    case home = "Home", library = "Library", importer = "Import", themes = "Themes"
}

struct RootView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(ThemeStore.self) private var themes
    @State private var tab: AppTab = .home
    @State private var expanded = false
    @Namespace private var ns

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .home: HomeView()
                    case .library: LibraryView()
                    case .importer: ImportView()
                    case .themes: ThemesView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if engine.currentTrack != nil {
                    MiniPlayer(ns: ns, expanded: $expanded).padding(.horizontal, 16)
                }
                TabBar(tab: $tab).padding(.horizontal, 16).padding(.top, 8)
            }
            if expanded {
                NowPlayingView(ns: ns, expanded: $expanded)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .foregroundStyle(.white)
        .animation(themes.motion, value: expanded)
        .onChange(of: engine.currentTrack?.id) { themes.updateArt(engine.currentTrack?.artworkData) }
    }
}

struct MiniPlayer: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(ThemeStore.self) private var themes
    let ns: Namespace.ID
    @Binding var expanded: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if !expanded {
                    ArtView(data: engine.currentTrack?.artworkData).matchedGeometryEffect(id: "art", in: ns)
                } else {
                    Color.clear
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.currentTrack?.title ?? "").font(.system(size: 14, weight: .bold)).lineLimit(1)
                Text(engine.currentTrack?.artist ?? "").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Image(systemName: "waveform").foregroundStyle(themes.accent)
                .symbolEffect(.variableColor.iterative, isActive: engine.isPlaying)
            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
        }
        .padding(8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { expanded = true }
        .buttonStyle(.plain)
    }
}

struct TabBar: View {
    @Binding var tab: AppTab
    @Environment(ThemeStore.self) private var themes

    var body: some View {
        HStack {
            ForEach(AppTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    Text(t.rawValue).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tab == t ? themes.accent : Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .frame(height: 60)
        .background(Theme.card, in: Capsule())
    }
}
