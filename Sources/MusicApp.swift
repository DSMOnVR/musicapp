
import SwiftUI
import WidgetKit
import UniformTypeIdentifiers
import GoogleSignIn

@main
struct MusicApp: App {
    @State private var engine = PlayerEngine()
    @State private var library = LibraryStore()
    @State private var appTheme = AppTheme()
    @State private var cloudBackup = GoogleDriveBackup()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(library)
                .environment(appTheme)
                .environment(cloudBackup)
                .preferredColorScheme(
                    appTheme.appearance == "Auto"
                    ? nil
                    : (appTheme.appearance == "Light" ? .light : .dark)
                )
        }
    }
}

enum MainTab: String, CaseIterable {
    case home = "Home"
    case library = "Library"
    case importMusic = "Import"
    case themes = "Themes"
}

struct RootView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(AppTheme.self) private var appTheme
    @Environment(GoogleDriveBackup.self) private var cloudBackup
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: MainTab = .home
    @State private var showImporter = false
    @State private var showFolderImporter = false
    @State private var showNowPlaying = false
    @State private var isImporting = false
    @State private var lastStatsSecond = -1

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .home:
                    HomeView(
                        onImport: { selectedTab = .importMusic },
                        onOpenPlayer: { showNowPlaying = true }
                    )

                case .library:
                    LibraryView(
                        onOpenPlayer: { showNowPlaying = true }
                    )

                case .importMusic:
                    ImportView(
                        onChooseFiles: { showImporter = true },
                        onChooseFolder: { showFolderImporter = true },
                        isImporting: isImporting
                    )

                case .themes:
                    ThemesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if engine.currentTrack != nil && !showNowPlaying {
                MiniPlayer {
                    showNowPlaying = true
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }

            TabBar(selection: $selectedTab)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onChange(of: engine.currentTrack?.id) { _, _ in
            if let track = engine.currentTrack {
                library.recordPlay(track)
                appTheme.updateArtworkAccent(from: track.artworkData)
            }
            publishWidgetSnapshot()
        }
        .onChange(of: engine.isPlaying) { _, _ in
            publishWidgetSnapshot()
        }
        .onOpenURL { url in GIDSignIn.sharedInstance.handle(url) }
        .onReceive(NotificationCenter.default.publisher(for: .dsmMusicLibraryDidChange)) { _ in
            Task { await cloudBackup.backupIfSignedIn(library) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                cloudBackup.restorePreviousSignIn()
                Task { await cloudBackup.backupIfSignedIn(library) }
                publishWidgetSnapshot()
            }
        }
        .onChange(of: appTheme.useArtworkColors) { _, enabled in
            if enabled { appTheme.updateArtworkAccent(from: engine.currentTrack?.artworkData) }
        }
        .task {
            appTheme.updateArtworkAccent(from: engine.currentTrack?.artworkData)
            cloudBackup.restorePreviousSignIn()
            publishWidgetSnapshot()
        }
        .onChange(of: Int(engine.currentTime)) { _, second in
            guard engine.isPlaying, second != lastStatsSecond else { return }
            if lastStatsSecond >= 0 && second > lastStatsSecond {
                library.addListeningTime(min(Double(second - lastStatsSecond), 1))
            }
            lastStatsSecond = second
        }

        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environment(engine)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }

        // Native iOS audio document picker
        .sheet(isPresented: $showImporter) {
            AudioDocumentPicker { result in
                showImporter = false

                switch result {
                case .success(let urls):
                    Task {
                        await importURLs(urls)
                    }

                case .failure(let error):
                    library.importErrors = [error.localizedDescription]
                }
            }
        }

        // Folder picker
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let folder = urls.first else { return }

                Task {
                    await importFolder(folder)
                }

            case .failure(let error):
                library.importErrors = [error.localizedDescription]
            }
        }
    }

    private func publishWidgetSnapshot() {
        let defaults = UserDefaults(suiteName: "group.com.example.musicapp.shared")
        defaults?.set(engine.currentTrack?.title ?? "No song playing", forKey: "widget.track.title")
        defaults?.set(engine.currentTrack?.artist ?? "Open DSM Music to play", forKey: "widget.track.artist")
        defaults?.set(engine.isPlaying, forKey: "widget.track.isPlaying")
        defaults?.set(Date().timeIntervalSince1970, forKey: "widget.lastUpdated")
        defaults?.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "DSMMusicWidget")
    }

    // MARK: - Folder importing

    private func importFolder(_ folder: URL) async {
        let access = folder.startAccessingSecurityScopedResource()

        defer {
            if access {
                folder.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil
            ).filter {
                UTType(filenameExtension: $0.pathExtension)?
                    .conforms(to: .audio) == true
            }

            await importURLs(urls)

        } catch {
            library.importErrors = [error.localizedDescription]
        }
    }

    // MARK: - Audio importing

    private func importURLs(_ urls: [URL]) async {
        isImporting = true
        library.importErrors = []

        guard !urls.isEmpty else {
            library.importErrors = ["No files were selected."]
            isImporting = false
            return
        }

        var loaded: [Track] = []
        var errors: [String] = []

        for url in urls {
            do {
                let track = try await TrackLoader.load(from: url)
                loaded.append(track)
            } catch {
                errors.append(
                    "\(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }

        library.add(loaded)
        library.importErrors = errors

        if !loaded.isEmpty && engine.currentTrack == nil {
            engine.setQueue(library.tracks)
        }

        isImporting = false
    }
}

// MARK: - Tab bar

struct TabBar: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: icon(for: tab))
                            .font(.system(size: 17, weight: .semibold))

                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(
                        selection == tab
                        ? Color(white: 0.72)
                        : Theme.muted
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.card, in: Capsule())
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private func icon(for tab: MainTab) -> String {
        switch tab {
        case .home:
            return "house.fill"
        case .library:
            return "music.note.list"
        case .importMusic:
            return "plus.circle.fill"
        case .themes:
            return "paintpalette.fill"
        }
    }
}
