import Foundation
import Observation
import GoogleSignIn
import SwiftUI
import UIKit
import CryptoKit

/// Small manifest stored in Drive. Audio is uploaded separately so large libraries
/// do not have to fit inside one JSON/multipart request.
private struct CloudLibraryPayload: Codable {
    var version: Int
    var tracks: [Track]
    var audioFileNames: [String: String]
    var likedIDs: Set<UUID>
    var playlists: [MusicPlaylist]
    var playCounts: [UUID: Int]
    var listeningSeconds: TimeInterval
    var dailyPlayCounts: [String: Int]
}

/// Reads backups made by the first cloud-backup implementation.
private struct LegacyCloudLibraryPayload: Codable {
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
    private let backupName = "DSM-Music-Library.json"
    private let audioPrefix = "DSM-Music-Audio-"

    private(set) var isSignedIn = false
    private(set) var accountEmail: String?
    private(set) var status = "Not connected"
    private(set) var isWorking = false

    private var user: GIDGoogleUser?
    private var backupRequestedWhileWorking = false

    func restorePreviousSignIn(_ library: LibraryStore? = nil) {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            guard let self else { return }
            if let user {
                self.user = user
                self.isSignedIn = true
                self.accountEmail = user.profile?.email
                self.status = "Connected to Google Drive"
                if let library, library.tracks.isEmpty {
                    Task { await self.restoreFromDrive(library) }
                }
            } else if let error {
                self.status = "Sign in required"
                print("Google restore sign-in: \(error.localizedDescription)")
            }
        }
    }

    /// Connects the Google account, then restores an existing cloud library if
    /// this installation has no songs. Otherwise it uploads this device's library.
    func connectAndSync(_ library: LibraryStore) async {
        await signIn()
        guard isSignedIn else { return }
        if library.tracks.isEmpty {
            await restoreFromDrive(library)
            if library.tracks.isEmpty && status.hasPrefix("No DSM Music backup") {
                await backupNow(library)
            }
        } else {
            await backupNow(library)
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
        guard isSignedIn else { return }
        if isWorking {
            backupRequestedWhileWorking = true
            return
        }
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
        defer {
            isWorking = false
            if backupRequestedWhileWorking {
                backupRequestedWhileWorking = false
                Task { await self.backupNow(library) }
            }
        }

        do {
            let token = try await validAccessToken(for: user)
            let remoteFiles = try await listAppDataFiles(accessToken: token)
            var namesByTrack: [String: String] = [:]
            let encoder = JSONEncoder()

            for (index, track) in library.tracks.enumerated() {
                guard FileManager.default.fileExists(atPath: track.url.path) else {
                    throw Self.error("Missing audio file: \(track.title)")
                }
                let fileName = audioPrefix + track.id.uuidString + "." +
                    (track.url.pathExtension.isEmpty ? "audio" : track.url.pathExtension)
                let audioData = try Data(contentsOf: track.url)
                let checksum = Self.md5(audioData)
                let existing = remoteFiles.first { $0.name == fileName }
                if existing?.md5Checksum != checksum {
                    try await uploadFile(
                        audioData,
                        name: fileName,
                        mimeType: Self.mimeType(for: track.url),
                        existingID: existing?.id,
                        accessToken: token
                    )
                }
                namesByTrack[track.id.uuidString] = fileName
                status = "Backing up song \(index + 1) of \(library.tracks.count)…"
            }

            let payload = CloudLibraryPayload(
                version: 2,
                tracks: library.tracks,
                audioFileNames: namesByTrack,
                likedIDs: library.likedIDs,
                playlists: library.playlists,
                playCounts: library.playCounts,
                listeningSeconds: library.listeningSeconds,
                dailyPlayCounts: library.dailyPlayCounts
            )
            let manifestData = try encoder.encode(payload)
            let manifest = remoteFiles.first { $0.name == backupName }
            try await uploadFile(
                manifestData,
                name: backupName,
                mimeType: "application/json",
                existingID: manifest?.id,
                accessToken: token
            )
            status = "Backed up \(library.tracks.count) songs to Google Drive"
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
            let files = try await listAppDataFiles(accessToken: token)
            guard let manifest = files.first(where: { $0.name == backupName }) else {
                // Compatibility with the first version of the app's cloud backup.
                guard let legacyManifest = files.first(where: { $0.name == "DSM-Music-Backup.json" }) else {
                    status = "No DSM Music backup found in this Google account"
                    return
                }
                let oldData = try await downloadFile(legacyManifest.id, accessToken: token)
                let old = try JSONDecoder().decode(LegacyCloudLibraryPayload.self, from: oldData)
                guard old.version == 1 else { throw Self.error("This backup version isn't supported.") }
                let restored = try await restoreLegacy(old, library: library)
                status = "Restored \(restored) songs"
                return
            }

            let manifestData = try await downloadFile(manifest.id, accessToken: token)
            let payload = try JSONDecoder().decode(CloudLibraryPayload.self, from: manifestData)
            guard payload.version == 2 else { throw Self.error("This backup version isn't supported.") }

            let restoreFolder = try Self.restoreFolder()
            var restored: [Track] = []
            for (index, originalTrack) in payload.tracks.enumerated() {
                guard let fileName = payload.audioFileNames[originalTrack.id.uuidString],
                      let remote = files.first(where: { $0.name == fileName }) else {
                    throw Self.error("A backed-up audio file is missing for \(originalTrack.title). Your current library was left unchanged.")
                }
                let audioData = try await downloadFile(remote.id, accessToken: token)
                var track = originalTrack
                let ext = URL(fileURLWithPath: fileName).pathExtension
                let destination = restoreFolder.appendingPathComponent("\(track.id.uuidString).\(ext.isEmpty ? "audio" : ext)")
                try audioData.write(to: destination, options: .atomic)
                track.url = destination
                restored.append(track)
                status = "Restoring song \(index + 1) of \(payload.tracks.count)…"
            }

            try library.restoreFromGoogleDrive(
                tracks: restored,
                likedIDs: payload.likedIDs,
                playlists: payload.playlists,
                playCounts: payload.playCounts,
                listeningSeconds: payload.listeningSeconds,
                dailyPlayCounts: payload.dailyPlayCounts
            )
            status = "Restored \(restored.count) songs from Google Drive"
        } catch {
            status = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func restoreLegacy(_ payload: LegacyCloudLibraryPayload, library: LibraryStore) async throws -> Int {
        let folder = try Self.restoreFolder()
        var restored: [Track] = []
        for var track in payload.tracks {
            guard let audioData = payload.audioFiles[track.id.uuidString] else {
                throw Self.error("A backed-up audio file is missing for \(track.title). Your current library was left unchanged.")
            }
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
        return restored.count
    }

    private func validAccessToken(for user: GIDGoogleUser) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error { continuation.resume(throwing: error); return }
                guard let refreshedUser else {
                    continuation.resume(throwing: Self.error("Google couldn't refresh your sign-in."))
                    return
                }
                self.user = refreshedUser
                continuation.resume(returning: refreshedUser.accessToken.tokenString)
            }
        }
    }

    private func listAppDataFiles(accessToken: String) async throws -> [DriveFile] {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "q", value: "'appDataFolder' in parents and trashed = false"),
            URLQueryItem(name: "pageSize", value: "1000"),
            URLQueryItem(name: "fields", value: "files(id,name,size,md5Checksum)")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        return try JSONDecoder().decode(DriveFileList.self, from: data).files
    }

    private func downloadFile(_ id: String, accessToken: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(id)?alt=media")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        return data
    }

    /// Uses Drive's resumable protocol so large audio files can upload reliably.
    private func uploadFile(_ data: Data, name: String, mimeType: String, existingID: String?, accessToken: String) async throws {
        let metadata: [String: Any] = existingID == nil
            ? ["name": name, "parents": ["appDataFolder"]]
            : ["name": name]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        let endpoint = existingID.map {
            "https://www.googleapis.com/upload/drive/v3/files/\($0)?uploadType=resumable&fields=id,name"
        } ?? "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,name"

        var start = URLRequest(url: URL(string: endpoint)!)
        start.httpMethod = existingID == nil ? "POST" : "PATCH"
        start.httpBody = metadataData
        start.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        start.setValue(String(data.count), forHTTPHeaderField: "X-Upload-Content-Length")

        let (_, startResponse) = try await URLSession.shared.data(for: start)
        guard let http = startResponse as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location) else {
            throw Self.responseError(startResponse, data: Data())
        }

        var upload = URLRequest(url: uploadURL)
        upload.httpMethod = "PUT"
        upload.httpBody = data
        upload.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let (result, response) = try await URLSession.shared.data(for: upload)
        try Self.check(response, data: result)
    }

    private static func restoreFolder() throws -> URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DSM Music", isDirectory: true)
            .appendingPathComponent("Google Drive Restore", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "mp4": return "audio/mp4"
        case "aac": return "audio/aac"
        case "wav": return "audio/wav"
        case "aiff", "aif": return "audio/aiff"
        case "flac": return "audio/flac"
        case "ogg", "oga": return "audio/ogg"
        default: return "application/octet-stream"
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "DSMMusicCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func responseError(_ response: URLResponse, data: Data) -> NSError {
        let detail = String(data: data, encoding: .utf8) ?? "Google Drive upload failed"
        return NSError(domain: "DSMMusicCloud", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: detail])
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw responseError(response, data: data)
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
    let files: [DriveFile]
}

private struct DriveFile: Decodable {
    let id: String
    let name: String
    let md5Checksum: String?
}
