import SwiftUI
import UniformTypeIdentifiers

@main
struct MusicApp: App {
    @State private var engine = PlayerEngine()
    @State private var library = LibraryStore()
    @State private var appTheme = AppTheme()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(library)
                .environment(appTheme)
                .preferredColorScheme(appTheme.appearance == "Auto" ? nil : (appTheme.appearance == "Light" ? .light : .dark))
        }
    }
}

enum MainTab: String, CaseIterable { case home = "Home", library = "Library", importMusic = "Import", themes = "Themes" }

struct RootView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @State private var selectedTab: MainTab = .home
    @State private var showImporter = false
    @State private var showFolderImporter = false
    @State private var showNowPlaying = false
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .home: HomeView(onImport: { selectedTab = .importMusic }, onOpenPlayer: { showNowPlaying = true })
                case .library: LibraryView(onOpenPlayer: { showNowPlaying = true })
                case .importMusic: ImportView(onChooseFiles: { showImporter = true }, onChooseFolder: { showFolderImporter = true }, isImporting: isImporting)
                case .themes: ThemesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if engine.currentTrack != nil && !showNowPlaying {
                MiniPlayer { showNowPlaying = true }
                    .padding(.horizontal, 18).padding(.bottom, 8)
            }
            TabBar(selection: $selectedTab)
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showNowPlaying) { NowPlayingView().environment(engine).presentationDetents([.large]).presentationDragIndicator(.hidden) }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio, .mp3],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                print("Selected files: \(urls)")
                Task {
                    await importURLs(urls)
                }
            case .failure(let error):
                library.importErrors = [error.localizedDescription]
            }
        }
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let folder = urls.first else { return }
            Task { await importFolder(folder) }
        }
        .onChange(of: library.tracks.count) { _, _ in }
    }

    private func importResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error): library.importErrors = [error.localizedDescription]
        case .success(let urls): Task { await importURLs(urls) }
        }
    }
    private func importFolder(_ folder: URL) async {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .audio) == true }
            await importURLs(urls)
        } catch { library.importErrors = [error.localizedDescription] }
    }
    private func importURLs(_ urls: [URL]) async {
        isImporting = true
        var loaded: [Track] = []
        var errors: [String] = []
        for url in urls {
            do { loaded.append(try await TrackLoader.load(from: url)) }
            catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        library.add(loaded)
        library.importErrors = errors
        isImporting = false
        if !loaded.isEmpty && engine.currentTrack == nil { engine.setQueue(library.tracks) }
    }
}

struct TabBar: View {
    @Binding var selection: MainTab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: icon(for: tab)).font(.system(size: 17, weight: .semibold))
                        Text(tab.rawValue).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selection == tab ? Color(red: 0.78, green: 1, blue: 0.2) : Theme.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .background(Theme.card, in: Capsule())
        .padding(.horizontal, 18).padding(.bottom, 8)
    }
    private func icon(for tab: MainTab) -> String {
        switch tab { case .home: "house.fill"; case .library: "music.note.list"; case .importMusic: "plus.circle.fill"; case .themes: "paintpalette.fill" }
    }
}
