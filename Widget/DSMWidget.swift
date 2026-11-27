import SwiftUI
import WidgetKit

private let sharedGroup = "group.com.example.musicapp.shared"

struct MusicWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let isPlaying: Bool
}

struct MusicWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MusicWidgetEntry {
        MusicWidgetEntry(date: .now, title: "DSM Music", artist: "Your offline library", isPlaying: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (MusicWidgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MusicWidgetEntry>) -> Void) {
        let entry = readEntry()
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func readEntry() -> MusicWidgetEntry {
        let defaults = UserDefaults(suiteName: sharedGroup)
        return MusicWidgetEntry(
            date: .now,
            title: defaults?.string(forKey: "widget.track.title") ?? "No song playing",
            artist: defaults?.string(forKey: "widget.track.artist") ?? "Open DSM Music to play",
            isPlaying: defaults?.bool(forKey: "widget.track.isPlaying") ?? false
        )
    }
}

struct DSMMusicWidgetView: View {
    let entry: MusicWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "waveform").font(.title2.bold())
                Spacer()
                Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                    .font(.caption.bold())
            }
            Spacer(minLength: 2)
            Text(entry.title).font(.headline).lineLimit(2)
            Text(entry.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text("DSM MUSIC").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
        }
        .padding()
        .containerBackground(.black.gradient, for: .widget)
        .foregroundStyle(.white)
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
        .description("See the song currently playing.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
