import Foundation
import SwiftUI

struct SongCredit: Identifiable, Hashable {
    var id: String { "\(role)-\(name)" }
    let role: String
    let name: String
}

enum SongCreditsService {
    static func fetch(title: String, artist: String) async throws -> [SongCredit] {
        let key = "dsm.credits.\(title.lowercased())|\(artist.lowercased())"
        if let cached = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SongCreditCache].self, from: cached) {
            return decoded.map { SongCredit(role: $0.role, name: $0.name) }
        }

        var search = URLComponents(string: "https://musicbrainz.org/ws/2/recording/")!
        search.queryItems = [
            URLQueryItem(name: "query", value: "recording:\"\(title)\" AND artist:\"\(artist)\""),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "1")
        ]
        var request = URLRequest(url: search.url!)
        request.setValue("DSMMusic/1.0 (offline music player)", forHTTPHeaderField: "User-Agent")
        let (searchData, _) = try await URLSession.shared.data(for: request)
        let searchJSON = try JSONSerialization.jsonObject(with: searchData) as? [String: Any]
        let recordings = searchJSON?["recordings"] as? [[String: Any]] ?? []
        guard let id = recordings.first?["id"] as? String else { return [] }

        var lookup = URLComponents(string: "https://musicbrainz.org/ws/2/recording/\(id)")!
        lookup.queryItems = [
            URLQueryItem(name: "inc", value: "artist-credits+work-rels+recording-rels"),
            URLQueryItem(name: "fmt", value: "json")
        ]
        var detailRequest = URLRequest(url: lookup.url!)
        detailRequest.setValue("DSMMusic/1.0 (offline music player)", forHTTPHeaderField: "User-Agent")
        let (detailData, _) = try await URLSession.shared.data(for: detailRequest)
        let detailJSON = try JSONSerialization.jsonObject(with: detailData) as? [String: Any]
        let relations = detailJSON?["relations"] as? [[String: Any]] ?? []
        let credits = relations.compactMap { relation -> SongCredit? in
            guard let role = relation["type"] as? String else { return nil }
            let artistObject = relation["artist"] as? [String: Any]
            let workObject = relation["work"] as? [String: Any]
            guard let name = (artistObject?["name"] as? String) ?? (workObject?["title"] as? String) else { return nil }
            return SongCredit(role: role.replacingOccurrences(of: "-", with: " ").capitalized, name: name)
        }
        let unique = Array(Set(credits)).sorted { $0.role < $1.role }
        let cache = unique.map { SongCreditCache(role: $0.role, name: $0.name) }
        if let data = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(data, forKey: key) }
        return unique
    }
}

private struct SongCreditCache: Codable {
    let role: String
    let name: String
}

struct SongCreditsView: View {
    let track: Track
    @State private var credits: [SongCredit] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(.title3.bold())
                        Text(track.artist).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
                Section("Credits") {
                    if isLoading {
                        HStack { ProgressView(); Text("Looking up credits…").foregroundStyle(.secondary) }
                    } else if let errorMessage {
                        Text(errorMessage).foregroundStyle(.secondary)
                    } else if credits.isEmpty {
                        Text("No additional credits were found for this recording.").foregroundStyle(.secondary)
                    } else {
                        ForEach(credits) { credit in
                            LabeledContent(credit.role, value: credit.name)
                        }
                    }
                }
                Section {
                    Text("Credits are looked up online and cached on this device for future offline viewing. Results depend on MusicBrainz community data.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Song Credits")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            do {
                credits = try await SongCreditsService.fetch(title: track.title, artist: track.artist)
                if credits.isEmpty { errorMessage = "No credits are available yet." }
            } catch {
                errorMessage = "Could not load credits. Connect to the internet and try again."
            }
            isLoading = false
        }
    }
}
