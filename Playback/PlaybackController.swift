import AVFoundation
import Foundation
import MediaPlayer

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var canGoPrevious = false
    @Published private(set) var canGoNext = false
    @Published private(set) var errorMessage: String?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var completionObserver: NSObjectProtocol?
    private var queue: [Track] = []
    private var currentIndex = 0
    private var api: JellyfinAPI?

    init() {
        configureRemoteCommands()
    }

    func play(_ track: Track, queue: [Track], using api: JellyfinAPI) {
        self.queue = queue.isEmpty ? [track] : queue
        currentIndex = self.queue.firstIndex(of: track) ?? 0
        self.api = api
        playCurrent()
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updatePlaybackRate()
    }

    func previous() {
        if elapsed > 5 {
            seek(to: 0)
            return
        }
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        playCurrent()
    }

    func next() {
        guard currentIndex + 1 < queue.count else {
            player?.pause()
            isPlaying = false
            updatePlaybackRate()
            return
        }
        currentIndex += 1
        playCurrent()
    }

    func seek(to seconds: TimeInterval) {
        let target = min(max(seconds, 0), duration)
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsed = target
        updateNowPlayingElapsed()
    }

    func stop() {
        tearDownPlayer()
        queue = []
        currentTrack = nil
        elapsed = 0
        duration = 0
        isPlaying = false
        updateQueueControls()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func playCurrent() {
        guard queue.indices.contains(currentIndex), let api else { return }
        let track = queue[currentIndex]
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            tearDownPlayer()
            let player = AVPlayer(url: try api.streamURL(itemID: track.id))
            self.player = player
            currentTrack = track
            elapsed = 0
            duration = track.duration
            observe(player)
            player.play()
            isPlaying = true
            updateQueueControls()
            updateNowPlaying(track: track)
        } catch {
            errorMessage = error.localizedDescription
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
            }
        }
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.next() }
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

    private func updateQueueControls() {
        canGoPrevious = currentIndex > 0 || elapsed > 0
        canGoNext = currentIndex + 1 < queue.count
        let commands = MPRemoteCommandCenter.shared()
        commands.previousTrackCommand.isEnabled = currentIndex > 0
        commands.nextTrackCommand.isEnabled = canGoNext
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }

    private func updatePlaybackRate() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    }

    private func updateNowPlayingElapsed() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
    }
}
