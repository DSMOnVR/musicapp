import SwiftUI

struct ListeningStatsView: View {
    @Environment(LibraryStore.self) private var library
    private var totalPlays: Int { library.playCounts.values.reduce(0, +) }
    private var hours: Int { Int(library.listeningSeconds) / 3600 }
    private var minutes: Int { (Int(library.listeningSeconds) % 3600) / 60 }
    private var lastSevenDays: [(String, Int)] {
        let calendar = Calendar.current
        let formatter = LibraryStore.historyDateFormatter
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { return nil }
            let key = formatter.string(from: date)
            return (date.formatted(.dateTime.weekday(.abbreviated)), library.dailyPlayCounts[key, default: 0])
        }
    }
    private var topTracks: [Track] {
        library.mostPlayed.filter { library.playCounts[$0.id, default: 0] > 0 }.prefix(5).map { $0 }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metric("Listening time", value: hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m", icon: "clock")
                        metric("Total plays", value: "\(totalPlays)", icon: "play.circle")
                        metric("Songs", value: "\(library.tracks.count)", icon: "music.note")
                        metric("Liked", value: "\(library.likedTracks.count)", icon: "heart")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Plays this week").font(.headline)
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(Array(lastSevenDays.enumerated()), id: \.offset) { _, day in
                                VStack(spacing: 7) {
                                    Text("\(day.1)").font(.caption2).foregroundStyle(Theme.muted)
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(ThemeAccent.color.opacity(0.85))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: CGFloat(max(day.1, 1)) / CGFloat(max(lastSevenDays.map(\.1).max() ?? 1, 1)) * 90)
                                    Text(day.0).font(.caption2).foregroundStyle(Theme.muted)
                                }
                                .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }.frame(height: 130)
                    }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Most played").font(.headline)
                        if topTracks.isEmpty {
                            Text("Your play history will show up here.").font(.subheadline).foregroundStyle(Theme.muted)
                        } else {
                            ForEach(Array(topTracks.enumerated()), id: \.element.id) { index, track in
                                HStack(spacing: 12) {
                                    Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 22)
                                    ArtworkView(track: track).frame(width: 42, height: 42)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title).font(.subheadline.bold()).lineLimit(1)
                                        Text(track.artist).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(library.playCounts[track.id, default: 0]) plays").font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                }.padding(20)
            }
            .background(Theme.bg)
            .foregroundStyle(.white)
            .navigationTitle("Listening statistics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).foregroundStyle(ThemeAccent.color)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(Theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 17))
    }
}
