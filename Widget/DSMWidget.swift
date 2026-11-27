import SwiftUI
import WidgetKit

private let sharedGroup = "group.com.example.musicapp.shared"

struct MusicWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let isPlaying: Bool
    let style: String
}

struct MusicWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MusicWidgetEntry {
        MusicWidgetEntry(date: .now, title: "DSM Music", artist: "Your offline library", isPlaying: false, style: "Midnight")
    }
    func getSnapshot(in context: Context, completion: @escaping (MusicWidgetEntry) -> Void) {
        completion(readEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MusicWidgetEntry>) -> Void) {
        completion(Timeline(entries: [readEntry()], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
    private func readEntry() -> MusicWidgetEntry {
        let defaults = UserDefaults(suiteName: sharedGroup)
        return MusicWidgetEntry(
            date: .now,
            title: defaults?.string(forKey: "widget.track.title") ?? "No song playing",
            artist: defaults?.string(forKey: "widget.track.artist") ?? "Open DSM Music to play",
            isPlaying: defaults?.bool(forKey: "widget.track.isPlaying") ?? false,
            style: defaults?.string(forKey: "widget.style") ?? "Midnight"
        )
    }
}

struct DSMMusicWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MusicWidgetEntry

    private var tint: Color {
        switch entry.style {
        case "Ocean": return .cyan
        case "Violet": return .purple
        case "Rose": return .pink
        case "Gold": return .orange
        default: return .white
        }
    }
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label(entry.title, systemImage: "music.note")
            case .accessoryCircular:
                VStack(spacing: 3) {
                    Image(systemName: entry.isPlaying ? "waveform" : "music.note").font(.title3)
                    Text(entry.isPlaying ? "PLAY" : "PAUSE").font(.system(size: 8, weight: .bold))
                }.widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title).font(.headline).lineLimit(1)
                    Text(entry.artist).font(.caption2).lineLimit(1)
                    Label(entry.isPlaying ? "Playing" : "Paused", systemImage: entry.isPlaying ? "waveform" : "pause")
                        .font(.caption2).widgetAccentable()
                }
            default:
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Image(systemName: "waveform").font(.title2.bold()).foregroundStyle(tint)
                        Spacer()
                        Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill").font(.caption.bold())
                    }
                    Spacer(minLength: 2)
                    Text(entry.title).font(.headline).lineLimit(2)
                    Text(entry.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text("DSM MUSIC").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                }
                .padding()
                .containerBackground(background, for: .widget)
                .foregroundStyle(.white)
            }
        }
    }
    private var background: LinearGradient {
        let colors: [Color]
        switch entry.style {
        case "Ocean": colors = [Color.blue.opacity(0.85), Color.cyan.opacity(0.45), .black]
        case "Violet": colors = [.purple, .indigo, .black]
        case "Rose": colors = [.pink.opacity(0.8), .purple.opacity(0.45), .black]
        case "Gold": colors = [.orange.opacity(0.7), .brown.opacity(0.45), .black]
        default: colors = [Color(white: 0.20), .black]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

@main
struct DSMMusicWidget: Widget {
    let kind = "DSMMusicWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MusicWidgetProvider()) { entry in
            DSMMusicWidgetView(entry: entry)
        }
        .configurationDisplayName("DSM Music")
        .description("Now playing, including Lock Screen sizes.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
