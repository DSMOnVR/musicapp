import SwiftUI

@main
struct MusicApp: App {
    @State private var engine = PlayerEngine()
    @State private var library = LibraryStore()
    @State private var themes = ThemeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(library)
                .environment(themes)
                .preferredColorScheme(.dark)
        }
    }
}
