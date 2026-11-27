import SwiftUI

struct HomeView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    var onImport: () -> Void
    var onOpenPlayer: () -> Void
    @State private var search = ""
    @State private var artistPhotos: [String: UIImage] = [:]
    @State private var lastStatsSecond = -1
    private var recent: [Track] { Array(library.tracks.reversed().prefix(8)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Text("Home").font(.system(size: 34, weight: .bold))
                    Spacer()
                    Button { onImport() } label: { Image(systemName: "plus").font(.title2.bold()).foregroundStyle(ThemeAccent.color).padding(10) }
                }
                if library.tracks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "waveform").font(.system(size: 54)).foregroundStyle(ThemeAccent.color)
                        Text("Your music starts here").font(.title2.bold())
                        Text("Import songs from Files to build your offline library.").foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        Button("Import music", action: onImport).buttonStyle(AccentButtonStyle())
                    }.frame(maxWidth: .infinity).padding(.vertical, 50).padding(.horizontal, 24).background(Theme.card, in: RoundedRectangle(cornerRadius: 28))
                } else {
                    HStack(spacing: 12) {
                        quickCard("Liked Songs", icon: "heart.fill", count: "\(library.likedTracks.count) songs") { engine.setQueue(library.likedTracks) }
                        quickCard("All Music", icon: "music.note", count: "\(library.tracks.count) songs") { engine.setQueue(library.tracks) }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("Recently added")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(recent) { track in
                                    Button { play(track) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ArtworkView(track: track).frame(width: 142, height: 142)
                                            Text(track.title).font(.subheadline.bold()).lineLimit(1).foregroundStyle(.white)
                                            Text(track.artist).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                                        }.frame(width: 142, alignment: .leading)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Your artists")
                        ForEach(library.artists, id: \.self) { artist in
                            Button { engine.setQueue(library.tracks.filter { $0.artist == artist }) } label: {
                                HStack(spacing: 12) {
                                    Group {
                                        if let photo = artistPhotos[artist] {
                                            Image(uiImage: photo).resizable().scaledToFill()
                                        } else {
                                            Circle().fill(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                .overlay(Image(systemName: "person.fill").foregroundStyle(.white))
                                        }
                                    }
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                                    Text(artist).font(.headline).foregroundStyle(.white)
                                    Spacer(); Image(systemName: "play.fill").foregroundStyle(ThemeAccent.color)
                                }.padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 20)
        }
        .foregroundStyle(.white)
        .onChange(of: engine.currentTrack?.id) { _, _ in
            if let track = engine.currentTrack { library.recordPlay(track) }
        }
        .onChange(of: Int(engine.currentTime)) { _, second in
            guard engine.isPlaying, second != lastStatsSecond else { return }
            if lastStatsSecond >= 0 && second > lastStatsSecond {
                library.addListeningTime(min(Double(second - lastStatsSecond), 1))
            }
            lastStatsSecond = second
        }
        .task(id: library.artists) {
            for artist in library.artists where artistPhotos[artist] == nil {
                if let photo = await ArtistImageStore.image(for: artist) {
                    artistPhotos[artist] = photo
                }
            }
        }
    }
    private var listeningTime: String {
        let minutes = Int(library.listeningSeconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    private func quickCard(_ title: String, icon: String, count: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.title2).foregroundStyle(ThemeAccent.color)
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.bold()).foregroundStyle(.white); Text(count).font(.caption).foregroundStyle(Theme.muted) }
                Spacer(minLength: 0)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.title3.bold()).foregroundStyle(.white) }
    private func play(_ track: Track) { engine.setQueue(library.tracks, startAt: library.tracks.firstIndex(of: track) ?? 0); onOpenPlayer() }
}

struct ThemeAccent { static let color = Color(red: 0.78, green: 1, blue: 0.2) }

struct ArtworkView: View {
    var track: Track
    var body: some View {
        Group {
            if let data = track.artworkData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else { LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing).overlay(Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.white.opacity(0.8))) }
        }.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline.bold()).foregroundStyle(.black).padding(.horizontal, 24).padding(.vertical, 14)
            .background(ThemeAccent.color, in: Capsule()).scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
