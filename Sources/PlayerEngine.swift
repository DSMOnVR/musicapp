import AVFoundation
import MediaPlayer
import Observation
import UIKit

@MainActor @Observable
final class PlayerEngine {
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    var currentTrack: Track? {
        guard let i = currentIndex, queue.indices.contains(i) else { return nil }
        return queue[i]
    }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        configureRemoteCommands()
        observeInterruptions()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                let t = time.seconds
                self?.currentTime = t.isFinite ? t : 0
            }
        }
    }

    // MARK: Controls

    func setQueue(_ tracks: [Track], startAt index: Int = 0) {
        queue = tracks
        load(index: index)
        play()
    }

    func play() {
        guard currentTrack != nil else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func togglePlayPause() { isPlaying ? pause() : play() }

    func play(index: Int) {
        guard queue.indices.contains(index) else { return }
        load(index: index)
        play()
    }

    func addToQueue(_ track: Track, playNext: Bool = false) {
        if playNext, let currentIndex {
            queue.insert(track, at: min(currentIndex + 1, queue.count))
        } else {
            queue.append(track)
        }
    }

    func moveQueueItem(from source: IndexSet, to destination: Int) {
        let oldCurrentID = currentTrack?.id
        let moving = source.sorted().compactMap { queue.indices.contains($0) ? queue[$0] : nil }
        for index in source.sorted(by: >) where queue.indices.contains(index) {
            queue.remove(at: index)
        }
        let adjustedDestination = max(0, min(destination - source.filter { $0 < destination }.count, queue.count))
        queue.insert(contentsOf: moving, at: adjustedDestination)
        currentIndex = oldCurrentID.flatMap { id in queue.firstIndex(where: { $0.id == id }) }
    }

    func removeQueueItem(at index: Int) {
        guard queue.indices.contains(index) else { return }
        let removedCurrent = index == currentIndex
        queue.remove(at: index)
        if queue.isEmpty {
            pause()
            currentIndex = nil
            player.replaceCurrentItem(with: nil)
            duration = 0
            currentTime = 0
        } else if removedCurrent {
            let nextIndex = min(index, queue.count - 1)
            load(index: nextIndex)
            play()
        } else if let currentIndex, index < currentIndex {
            self.currentIndex = currentIndex - 1
        }
    }

    /// Removes every upcoming track while keeping the current song playing.
    func clearUpcoming() {
        guard let currentIndex, queue.indices.contains(currentIndex) else {
            queue.removeAll()
            pause()
            player.replaceCurrentItem(with: nil)
            self.currentIndex = nil
            currentTime = 0
            duration = 0
            return
        }
        queue = [queue[currentIndex]]
        self.currentIndex = 0
    }

    /// Randomizes only upcoming tracks; the current song stays in place.
    func shuffleUpcoming() {
        guard let currentIndex, currentIndex + 1 < queue.count else { return }
        let current = queue[currentIndex]
        var upcoming = Array(queue.dropFirst(currentIndex + 1))
        upcoming.shuffle()
        queue = Array(queue.prefix(currentIndex)) + [current] + upcoming
    }

    func setSleepTimer(minutes: Int) {
        sleepTask?.cancel()
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            self?.pause()
            self?.sleepTask = nil
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
    }

    func next() {
        guard let i = currentIndex else { return }
        if i + 1 < queue.count {
            load(index: i + 1)
            play()
        } else {
            pause()
            seek(to: 0)
        }
    }

    func previous() {
        guard let i = currentIndex else { return }
        if currentTime > 3 || i == 0 {
            seek(to: 0)
        } else {
            load(index: i - 1)
            play()
        }
    }

    func seek(to time: TimeInterval) {
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateNowPlaying()
    }

    // MARK: Internals

    private func load(index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        let track = queue[index]
        let item = AVPlayerItem(url: track.url)
        player.replaceCurrentItem(with: item)
        duration = track.duration
        currentTime = 0

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        }
        updateNowPlaying()
    }

    private func configureRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in self?.seek(to: t) }
            return .success
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let optionRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionRaw).contains(.shouldResume)
            MainActor.assumeIsolated {
                if type == .began { self?.pause() } else if shouldResume { self?.play() }
            }
        }
    }

    private func updateNowPlaying() {
        guard let t = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyAlbumTitle: t.album,
            MPMediaItemPropertyPlaybackDuration: t.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let data = t.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
