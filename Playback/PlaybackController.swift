import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
protocol AudioSessionManaging {
    func activateForPlayback() throws
    func deactivateAfterPlayback() throws
}

@MainActor
struct SystemAudioSessionManager: AudioSessionManaging {
    func activateForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    func deactivateAfterPlayback() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum NowPlayingArtworkFactory {
    nonisolated static func make(from image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var artwork: UIImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var isPreparing = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var canGoPrevious = false
    @Published private(set) var canGoNext = false
    @Published private(set) var qualityLabel = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var isShuffled = false
    @Published private(set) var repeatMode: RepeatMode = .off

    private let defaults: UserDefaults
    private let audioSession: AudioSessionManaging
    private let snapshotKey = "active-playback-snapshot-v1"
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var completionObserver: NSObjectProtocol?
    private var preparationTask: Task<Void, Never>?
    private var originalQueue: [Track] = []
    private var api: JellyfinAPI?
    private var userID: String?
    private var scope = ""
    private var plan: PlaybackPlan?
    private var generation = UUID()
    private var lastProgressBucket = -1
    private var lastPersistenceBucket = -1

    init(
        defaults: UserDefaults = .standard,
        audioSession: AudioSessionManaging = SystemAudioSessionManager()
    ) {
        self.defaults = defaults
        self.audioSession = audioSession
        configureRemoteCommands()
    }

    func play(
        _ track: Track,
        queue: [Track],
        using api: JellyfinAPI,
        userID: String,
        scope: String
    ) {
        self.queue = queue.isEmpty ? [track] : queue
        originalQueue = self.queue
        currentIndex = self.queue.firstIndex(of: track) ?? 0
        isShuffled = false
        repeatMode = .off
        self.api = api
        self.userID = userID
        self.scope = scope
        prepareCurrent(resumeAt: 0, autoPlay: true)
    }

    func restore(using api: JellyfinAPI, userID: String, scope: String) {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(PlaybackSnapshot.self, from: data),
              snapshot.scope == scope,
              snapshot.queue.indices.contains(snapshot.currentIndex) else { return }
        self.api = api
        self.userID = userID
        self.scope = scope
        queue = snapshot.queue
        currentIndex = snapshot.currentIndex
        originalQueue = snapshot.originalQueue
        isShuffled = snapshot.isShuffled
        repeatMode = snapshot.repeatMode
        prepareCurrent(resumeAt: snapshot.position, autoPlay: false)
        Diagnostics.event("playback_restored", ["position_seconds": Int(snapshot.position), "queue_count": queue.count])
    }

#if DEBUG
    func configureForUITesting(track: Track) {
        queue = [track]
        originalQueue = queue
        currentIndex = 0
        currentTrack = track
        duration = track.duration
        canGoPrevious = false
        canGoNext = false
    }
#endif

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        updatePlaybackRate()
        reportProgress()
        persistState()
    }

    func previous() {
        if elapsed > 5 {
            seek(to: 0)
            return
        }
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        prepareCurrent(resumeAt: 0, autoPlay: true)
    }

    func next() {
        advance(automatic: false)
    }

    func playNext(_ track: Track) {
        guard currentTrack != nil else { return }
        let insertionIndex = min(currentIndex + 1, queue.count)
        queue.insert(track, at: insertionIndex)
        insertIntoOriginalQueue(track)
        updateQueueControls()
        refreshNowPlayingQueueMetadata()
        persistState()
    }

    func addToQueue(_ track: Track) {
        guard currentTrack != nil else { return }
        queue.append(track)
        originalQueue.append(track)
        updateQueueControls()
        refreshNowPlayingQueueMetadata()
        persistState()
    }

    func toggleShuffle() {
        guard let currentTrack else { return }
        if isShuffled {
            queue = originalQueue
            currentIndex = queue.firstIndex(of: currentTrack) ?? 0
            isShuffled = false
        } else {
            originalQueue = queue
            var generator = SystemRandomNumberGenerator()
            queue = QueueOrder.shuffled(queue, keeping: currentTrack, using: &generator)
            currentIndex = 0
            isShuffled = true
        }
        updateQueueControls()
        refreshNowPlayingQueueMetadata()
        persistState()
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
        updateQueueControls()
        persistState()
    }

    private func advance(automatic: Bool) {
        if automatic, repeatMode == .one {
            prepareCurrent(resumeAt: 0, autoPlay: true)
            return
        }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            prepareCurrent(resumeAt: 0, autoPlay: true)
            return
        }
        if repeatMode == .all, !queue.isEmpty {
            currentIndex = 0
            prepareCurrent(resumeAt: 0, autoPlay: true)
            return
        }
        player?.pause()
        isPlaying = false
        reportProgress()
        updatePlaybackRate()
        persistState()
    }

    func seek(to seconds: TimeInterval) {
        let target = min(max(seconds, 0), duration)
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsed = target
        updateNowPlayingElapsed()
        reportProgress()
        persistState()
    }

    func persistState() {
        guard !scope.isEmpty, queue.indices.contains(currentIndex) else { return }
        let snapshot = PlaybackSnapshot(
            scope: scope,
            queue: queue,
            currentIndex: currentIndex,
            position: elapsed,
            originalQueue: originalQueue,
            isShuffled: isShuffled,
            repeatMode: repeatMode
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func stop(clearSnapshot: Bool = true) {
        reportStopped()
        generation = UUID()
        preparationTask?.cancel()
        tearDownPlayer()
        queue = []
        originalQueue = []
        currentIndex = 0
        isShuffled = false
        repeatMode = .off
        plan = nil
        currentTrack = nil
        artwork = nil
        elapsed = 0
        duration = 0
        isPlaying = false
        isPreparing = false
        qualityLabel = ""
        updateQueueControls()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? audioSession.deactivateAfterPlayback()
        if clearSnapshot { defaults.removeObject(forKey: snapshotKey) }
    }

    private func prepareCurrent(resumeAt: TimeInterval, autoPlay: Bool) {
        guard queue.indices.contains(currentIndex), let api, let userID else { return }
        let previousTrack = currentTrack
        let previousPlan = plan
        let previousPosition = elapsed
        generation = UUID()
        let expectedGeneration = generation
        preparationTask?.cancel()
        tearDownPlayer()
        plan = nil
        artwork = nil
        currentTrack = queue[currentIndex]
        elapsed = max(0, resumeAt)
        duration = currentTrack?.duration ?? 0
        isPlaying = false
        isPreparing = true
        errorMessage = nil
        qualityLabel = "Preparing…"
        lastProgressBucket = -1
        lastPersistenceBucket = -1
        updateQueueControls()
        persistState()

        guard let track = currentTrack else { return }
        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try audioSession.activateForPlayback()
                if let previousTrack, let previousPlan {
                    await api.reportStopped(
                        itemID: previousTrack.id,
                        plan: previousPlan,
                        position: previousPosition
                    )
                }
                guard !Task.isCancelled, generation == expectedGeneration else { return }
                let selectedPlan = try await api.playbackPlan(itemID: track.id, userID: userID)
                guard !Task.isCancelled, generation == expectedGeneration else { return }
                plan = selectedPlan
                qualityLabel = selectedPlan.method == .directPlay ? "Direct Play" : "AAC transcode"
                let player = AVPlayer(url: selectedPlan.url)
                self.player = player
                lastProgressBucket = Int(resumeAt / 10)
                lastPersistenceBucket = Int(resumeAt / 5)
                observe(player)
                if resumeAt > 0 {
                    await player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
                }
                guard !Task.isCancelled, generation == expectedGeneration else { return }
                if autoPlay { player.play() }
                isPlaying = autoPlay
                isPreparing = false
                updateNowPlaying(track: track)
                Task { await api.reportStarted(itemID: track.id, plan: selectedPlan, position: elapsed, paused: !autoPlay) }
                if let albumID = track.albumID,
                   let data = try? await api.artworkData(itemID: albumID),
                   let image = UIImage(data: data), generation == expectedGeneration {
                    artwork = image
                    updateNowPlaying(track: track)
                }
            } catch {
                guard generation == expectedGeneration else { return }
                isPreparing = false
                qualityLabel = "Playback unavailable"
                errorMessage = error.localizedDescription
                Diagnostics.event("playback_prepare_failed", ["code": (error as NSError).code])
            }
        }
    }

    private func observe(_ player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = time.seconds.isFinite ? max(0, time.seconds) : 0
                if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
                    self.duration = seconds
                }
                self.updateNowPlayingElapsed()
                self.updateQueueControls()
                let progressBucket = Int(self.elapsed / 10)
                if progressBucket != self.lastProgressBucket {
                    self.lastProgressBucket = progressBucket
                    self.reportProgress()
                }
                let persistenceBucket = Int(self.elapsed / 5)
                if persistenceBucket != self.lastPersistenceBucket {
                    self.lastPersistenceBucket = persistenceBucket
                    self.persistState()
                }
            }
        }
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.advance(automatic: true) }
        }
    }

    private func tearDownPlayer() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }
        timeObserver = nil
        completionObserver = nil
        player?.pause()
        player = nil
    }

    private func reportProgress() {
        guard let api, let track = currentTrack, let plan else { return }
        let position = elapsed
        let paused = !isPlaying
        Task { await api.reportProgress(itemID: track.id, plan: plan, position: position, paused: paused) }
    }

    private func reportStopped() {
        guard let api, let track = currentTrack, let plan else { return }
        let position = elapsed
        Task { await api.reportStopped(itemID: track.id, plan: plan, position: position) }
    }

    private func updateQueueControls() {
        canGoPrevious = currentIndex > 0 || elapsed > 0
        canGoNext = currentIndex + 1 < queue.count
        let commands = MPRemoteCommandCenter.shared()
        commands.previousTrackCommand.isEnabled = currentIndex > 0
        commands.nextTrackCommand.isEnabled = canGoNext || (repeatMode == .all && !queue.isEmpty)
    }

    private func insertIntoOriginalQueue(_ track: Track) {
        guard let currentTrack,
              let originalIndex = originalQueue.firstIndex(of: currentTrack) else {
            originalQueue.append(track)
            return
        }
        originalQueue.insert(track, at: min(originalIndex + 1, originalQueue.count))
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.toggle() } }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.toggle() } }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying(track: Track) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: currentIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = NowPlayingArtworkFactory.make(from: artwork)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updatePlaybackRate() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    }

    private func updateNowPlayingElapsed() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
    }

    private func refreshNowPlayingQueueMetadata() {
        guard currentTrack != nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueIndex] = currentIndex
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.count
    }
}
