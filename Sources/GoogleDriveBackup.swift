import Foundation
import GoogleSignIn
import SwiftUI
import UIKit

struct CloudLibraryPayload: Codable {
    var version: Int
    var tracks: [Track]
    var audioFiles: [String: Data]
    var likedIDs: Set<UUID>
    var playlists: [MusicPlaylist]
    var playCounts: [UUID: Int]
    var listeningSeconds: TimeInterval
    var dailyPlayCounts: [String: Int]
}

@MainActor
@Observable
final class GoogleDriveBackup {
    static let driveScope = "https://www.googleapis.com/auth/drive.appdata"
    private let backupName = "DSM-Music-Backup.json"

    private(set) var isSignedIn = false
    private(set) var accountEmail: String?
    private(set) var status = "Not connected"
    private(set) var isWorking = false

    private var user: GIDGoogleUser?
    private var lastAutomaticBackup = Date.distantPast

    func restorePreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            guard let self else { return }
            if let user {
                self.user = user
                self.isSignedIn = true
                self.accountEmail = user.profile?.email
                self.status = "Connected to Google Drive"
            } else if let error {
                self.status = "Sign in required"
                print("Google restore sign-in: \(error.localizedDescription)")
            }
        }
    }

    func signIn() async {
        guard let presenter = Self.topViewController() else {
            status = "Couldn't open Google sign-in"
            return
        }
        isWorking = true
        defer { isWorking = false }

        await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: [Self.driveScope]
            ) { [weak self] result, error in
                guard let self else { continuation.resume(); return }
                if let result {
                    self.user = result.user
                    self.isSignedIn = true
                    self.accountEmail = result.user.profile?.email
                    self.status = "Connected to Google Drive"
                } else {
                    self.status = error?.localizedDescription ?? "Google sign-in cancelled"
                }
                continuation.resume()
            }
        }
    }

    func backupIfSignedIn(_ library: LibraryStore) async {
        guard isSignedIn, !isWorking, Date().timeIntervalSince(lastAutomaticBackup) > 90 else { return }
        await backupNow(library)
    }

    func backupNow(_ library: LibraryStore) async {
        guard isSignedIn, let user else {
            status = "Connect Google Drive first"
            return
        }
        guard !isWorking else { return }
        isWorking = true
        status = "Preparing your music backup…"
        defer { isWorking = false }

        do {
            let token = try await validAccessToken(for: user)
            var audio: [String: Data] = [:]
            for track in library.tracks {
                guard FileManager.default.fileExists(atPath: track.url.path) else {
                    throw NSError(domain: "DSMMusicCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing audio file: \(track.title)"])
                }
                audio[track.id.uuidString] = try Data(contentsOf: track.url)
            }

            let payload = CloudLibraryPayload(
                version: 1,
                tracks: library.tracks,
                audioFiles: audio,
                likedIDs: library.likedIDs,
                playlists: library.playlists,
                playCounts: library.playCounts,
                listeningSeconds: library.listeningSeconds,
                dailyPlayCounts: library.dailyPlayCounts
            )
            let data = try JSONEncoder().encode(payload)
            try await upload(data, accessToken: token)
            lastAutomaticBackup = Date()
            status = "Backed up \(library.tracks.count) songs"
        } catch {
            status = "Backup failed: \(error.localizedDescription)"
        }
    }

    func restoreFromDrive(_ library: LibraryStore) async {
        guard isSignedIn, let user else {
            status = "Connect Google Drive first"
            return
        }
        guard !isWorking else { return }
        isWorking = true
        status = "Looking for your backup…"
        defer { isWorking = false }

        do {
            let token = try await validAccessToken(for: user)
            let fileID = try await findBackupFile(accessToken: token)
            guard let fileID else {
                status = "No DSM Music backup found in this Google account"
                return
            }
            var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.check(response, data: data)
            let payload = try JSONDecoder().decode(CloudLibraryPayload.self, from: data)
            guard payload.version == 1 else {
                throw NSError(domain: "DSMMusicCloud", code: 2, userInfo: [NSLocalizedDescriptionKey: "This backup version isn't supported."])
            }

            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DSM Music", isDirectory: true)
                .appendingPathComponent("Google Drive Restore", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            var restored: [Track] = []
            for var track in payload.tracks {
                guard let audioData = payload.audioFiles[track.id.uuidString] else { continue }
                let ext = track.url.pathExtension.isEmpty ? "mp3" : track.url.pathExtension
                let destination = folder.appendingPathComponent("\(track.id.uuidString).\(ext)")
                try audioData.write(to: destination, options: .atomic)
                track.url = destination
                restored.append(track)
            }
            try library.restoreFromGoogleDrive(
                tracks: restored,
                likedIDs: payload.likedIDs,
                playlists: payload.playlists,
                playCounts: payload.playCounts,
                listeningSeconds: payload.listeningSeconds,
                dailyPlayCounts: payload.dailyPlayCounts
            )
            status = "Restored \(restored.count) songs"
        } catch {
            status = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func validAccessToken(for user: GIDGoogleUser) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error { continuation.resume(throwing: error); return }
                guard let refreshedUser else {
                    continuation.resume(throwing: NSError(domain: "DSMMusicCloud", code: 3, userInfo: [NSLocalizedDescriptionKey: "Google couldn't refresh your sign-in."]))
                    return
                }
                self.user = refreshedUser
                continuation.resume(returning: refreshedUser.accessToken.tokenString)
            }
        }
    }

    private func findBackupFile(accessToken: String) async throws -> String? {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "q", value: "name = '\(backupName)' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id,name)")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        let result = try JSONDecoder().decode(DriveFileList.self, from: data)
        return result.files.first?.id
    }

    private func upload(_ data: Data, accessToken: String) async throws {
        let existingID = try await findBackupFile(accessToken: accessToken)
        let boundary = "DSMBOUNDARY-\(UUID().uuidString)"
        let metadata: [String: Any] = existingID == nil
            ? ["name": backupName, "parents": ["appDataFolder"]]
            : ["name": backupName]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        body.append(metadataData)
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--".utf8))

        let endpoint = existingID.map {
            "https://www.googleapis.com/upload/drive/v3/files/\($0)?uploadType=multipart"
        } ?? "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = existingID == nil ? "POST" : "PATCH"
        request.httpBody = body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: responseData)
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "Google Drive request failed"
            throw NSError(domain: "DSMMusicCloud", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: detail])
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let root = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

private struct DriveFileList: Decodable {
    struct File: Decodable { let id: String; let name: String }
    let files: [File]
}

extension Notification.Name {
    static let dsmMusicLibraryDidChange = Notification.Name("dsmMusicLibraryDidChange")
}
