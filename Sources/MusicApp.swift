
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

    @State private var selectedTab: MainTab = .home
    @State private var showImporter = false
    @State private var showFolderImporter = false
    @State private var showNowPlaying = false
    @State private var isImporting = false

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

        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environment(engine)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }

        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
            allowsMultipleSelection: true
        ) { result in
            importResult(result)
        }

        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let folder = urls.first else {
                if case .failure(let error) = result {
                    library.importErrors = [error.localizedDescription]
                }
                return
            }

            Task {
                await importFolder(folder)
            }
        }
    }

    // MARK: - File selection

    private func importResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                await importURLs(urls)
            }

        case .failure(let error):
            library.importErrors = [error.localizedDescription]
        }
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
                        ? Color(red: 0.78, green: 1, blue: 0.2)
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
