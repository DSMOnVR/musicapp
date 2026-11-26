import SwiftUI

@main
struct MusicApp: App {
    @State private var engine = PlayerEngine()

    var body: some Scene {
        WindowGroup {
            RootView().environment(engine)
        }
    }
}

struct RootView: View {
    @Environment(PlayerEngine.self) private var engine
    @State private var showImporter = false

    var body: some View {
        NowPlayingView()
            .overlay(alignment: .topTrailing) {
                Button { showImporter = true } label: {
                    Image(systemName: "plus").font(.title2.bold())
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Add songs")
                .padding(.trailing, 12)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task {
                    var tracks: [Track] = []
                    for url in urls {
                        if let t = try? await TrackLoader.load(from: url) { tracks.append(t) }
                    }
                    if !tracks.isEmpty { engine.setQueue(tracks) }
                }
            }
    }
}
