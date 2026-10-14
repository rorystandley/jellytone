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
        // Re-setting category on every track advance can emit spurious
        // interruption/route notifications that clear autoplay intent.
        if session.category != .playback || session.mode != .default {
            try session.setCategory(.playback, mode: .default)
        }
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

enum PlaybackRemoteCommand: Equatable {
    case play
    case pause
    case previous
    case next
    case seek(TimeInterval)
}

@MainActor
protocol RemoteCommandRouting: AnyObject {
    func register(handler: @escaping @MainActor (PlaybackRemoteCommand) -> Void)
    func updateAvailability(canGoPrevious: Bool, canGoNext: Bool)
}

@MainActor
final class SystemRemoteCommandRouter: RemoteCommandRouting {
    func register(handler: @escaping @MainActor (PlaybackRemoteCommand) -> Void) {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { _ in
            Task { @MainActor in handler(.play) }
            return .success
        }
        commands.pauseCommand.addTarget { _ in
            Task { @MainActor in handler(.pause) }
            return .success
        }
        commands.previousTrackCommand.addTarget { _ in
            Task { @MainActor in handler(.previous) }
            return .success
        }
        commands.nextTrackCommand.addTarget { _ in
            Task { @MainActor in handler(.next) }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in handler(.seek(event.positionTime)) }
            return .success
        }
    }

    func updateAvailability(canGoPrevious: Bool, canGoNext: Bool) {
        let commands = MPRemoteCommandCenter.shared()
        commands.previousTrackCommand.isEnabled = canGoPrevious
        commands.nextTrackCommand.isEnabled = canGoNext
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
    @Published private(set) var queue: [QueueEntry] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var isShuffled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var lastReportingFailure: PlaybackReportFailure?

    private let defaults: UserDefaults
    private let audioSession: AudioSessionManaging
    private let remoteCommands: RemoteCommandRouting
    private let notificationCenter: NotificationCenter
    private let snapshotKey = "active-playback-snapshot-v1"
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var completionObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var preparationTask: Task<Void, Never>?
    private var reportingTask: Task<Void, Never>?
    private var originalQueue: [QueueEntry] = []
    /// Resolves a verified offline file for a track (set by the coordinator).
    /// When it returns a URL the track plays locally with no server plan and
    /// no progress reporting — offline playback must not require the network.
    var localAudioURL: (@MainActor (Track) -> URL?)?
    /// Resolves an ephemeral replay-cache file for a track (set by the
    /// coordinator). A hit plays immediately; the server plan and reporting
    /// attach in the background so a warm launch does not wait on the network.
    var replayCachedAudioURL: (@MainActor (Track) -> URL?)?
    /// Asks the coordinator to cache a direct-play track's audio for replay.
    var cacheAudioForReplay: (@MainActor (Track) -> Void)?
    /// Drops a corrupt replay-cache file so the next attempt streams.
    var forgetCachedAudio: (@MainActor (Track) -> Void)?
    /// True while the current player is reading an unverified replay-cache file
    /// (not a download). A decode failure falls back to streaming.
    private var usingReplayCache = false
    /// Track whose replay-cache file just failed; skip that file for this
    /// prepare so we cannot loop on a corrupt copy.
    private var replayCacheDisabledForTrackID: String?

    private var api: JellyfinAPI?
    private var userID: String?
    private var scope = ""
    private var plan: PlaybackPlan?
    private var generation = UUID()
    private var lastProgressBucket = -1
    private var lastPersistenceBucket = -1
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var wasPlayingBeforeInterruption = false
    private var audioInterruptionIsActive = false
    private var playbackRequested = false
    /// When set, remote pause commands are ignored until this date. Absorbs
    /// Lock Screen / Now Playing pauses queued for the item that just ended so
    /// shuffle/queue autoplay is not cancelled. Refreshed when the successor
    /// actually starts, because stop-reporting can burn the advance-time window
    /// before audible playback begins.
    private var suppressRemotePauseUntil: Date?
    var shouldStartPreparedPlayer: Bool { playbackRequested && !audioInterruptionIsActive }

    init(
        defaults: UserDefaults = .standard,
        audioSession: AudioSessionManaging = SystemAudioSessionManager(),
        remoteCommands: RemoteCommandRouting = SystemRemoteCommandRouter(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.audioSession = audioSession
        self.remoteCommands = remoteCommands
        self.notificationCenter = notificationCenter
        configureRemoteCommands()
        observeAudioLifecycle()
    }

    func play(
        _ track: Track,
        queue: [Track],
        using api: JellyfinAPI,
        userID: String,
        scope: String
    ) {
        let tracks = queue.isEmpty ? [track] : queue
        let entries = tracks.map { QueueEntry(track: $0) }
        let selectedIndex = tracks.firstIndex(of: track) ?? 0
        play(
            entries: entries,
            startingAt: entries[selectedIndex].id,
            using: api,
            userID: userID,
            scope: scope
        )
    }

    func play(
        entries: [QueueEntry],
        startingAt entryID: QueueEntry.ID,
        using api: JellyfinAPI,
        userID: String,
        scope: String
    ) {
        guard let selectedIndex = entries.firstIndex(where: { $0.id == entryID }) else { return }
        self.queue = entries
        originalQueue = self.queue
        currentIndex = selectedIndex
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
    func configureForUITesting(
        track: Track,
        upcoming: [Track] = [],
        elapsed: TimeInterval = 0,
        isPlaying: Bool = false,
        isPreparing: Bool = false,
        artwork: UIImage? = nil,
        errorMessage: String? = nil
    ) {
        queue = ([track] + upcoming).map { QueueEntry(track: $0) }
        originalQueue = queue
        currentIndex = 0
        currentTrack = track
        duration = track.duration
        self.elapsed = min(max(elapsed, 0), duration)
        self.isPlaying = isPlaying
        self.isPreparing = isPreparing
        self.artwork = artwork
        self.errorMessage = errorMessage
        canGoPrevious = false
        canGoNext = !upcoming.isEmpty
    }

    func configureForLifecycleTesting(
        queue: [Track],
        currentIndex: Int,
        elapsed: TimeInterval,
        isPlaying: Bool,
        isPreparing: Bool = false,
        playbackRequested: Bool? = nil,
        playerAvailable: Bool = true,
        scope: String = "test:scope"
    ) {
        self.queue = queue.map { QueueEntry(track: $0) }
        originalQueue = self.queue
        self.currentIndex = currentIndex
        currentTrack = queue[currentIndex]
        duration = currentTrack?.duration ?? 0
        self.elapsed = elapsed
        self.isPlaying = isPlaying
        self.isPreparing = isPreparing
        self.playbackRequested = playbackRequested ?? isPlaying
        self.scope = scope
        player = playerAvailable ? AVPlayer() : nil
        updateQueueControls()
        updateNowPlaying(track: queue[currentIndex])
    }

    func simulateNaturalCompletionForTesting() {
        advance(automatic: true)
    }

    func simulatePlaybackFailureForTesting(code: Int = -1) {
        handlePlayerFailure(NSError(domain: "PlaybackFailureTest", code: code))
    }

    /// Simulates a failure/completion callback that still carries a previous
    /// item's generation — must not affect the track prepared after advance.
    func simulateStaleObservedFailureForTesting(generation observedGeneration: UUID, code: Int = -1) {
        handleObservedPlayerFailure(
            NSError(domain: "PlaybackFailureTest", code: code),
            observedGeneration: observedGeneration
        )
    }

    var currentGenerationForTesting: UUID { generation }

    /// Marks the remote-pause suppress window as already expired (past), without
    /// clearing it. Simulates stop-reporting burning the advance-time window
    /// before the successor becomes audible.
    func expireRemotePauseSuppressionForTesting() {
        suppressRemotePauseUntil = Date().addingTimeInterval(-0.1)
    }

    /// Advances `elapsed` as the periodic time observer would. Must not clear
    /// remote-pause suppression (regression for the post-#21 autoplay hole).
    func simulateElapsedProgressForTesting(_ seconds: TimeInterval) {
        elapsed = max(0, seconds)
    }

    func waitForPendingReportingForTesting() async {
        await preparationTask?.value
        await reportingTask?.value
    }
#endif

    func toggle() {
        guard let player else { return }
        suppressRemotePauseUntil = nil
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        playbackRequested = isPlaying
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
        commitVisibleOrderForEditing()
        let entry = QueueEntry(track: track)
        let insertionIndex = min(currentIndex + 1, queue.count)
        queue.insert(entry, at: insertionIndex)
        insertIntoOriginalQueue(entry)
        updateQueueControls()
        refreshNowPlayingQueueMetadata()
        persistState()
    }

    func addToQueue(_ track: Track) {
        guard currentTrack != nil else { return }
        commitVisibleOrderForEditing()
        let entry = QueueEntry(track: track)
        queue.append(entry)
        originalQueue.append(entry)
        updateQueueControls()
        refreshNowPlayingQueueMetadata()
        persistState()
    }

    /// Replaces everything after the current item without restarting playback.
    /// Used to expand a Made for You mix after its seed track has already started.
    func replaceUpcoming(with tracks: [Track]) {
        guard queue.indices.contains(currentIndex) else { return }
        commitVisibleOrderForEditing()
        let upcoming = tracks.map { QueueEntry(track: $0) }
        queue = Array(queue.prefix(currentIndex + 1)) + upcoming
        originalQueue = queue
        queueDidMutate()
    }

    func toggleShuffle() {
        guard queue.indices.contains(currentIndex) else { return }
        let currentID = queue[currentIndex].id
        if isShuffled {
            queue = originalQueue
            currentIndex = queue.firstIndex(where: { $0.id == currentID }) ?? 0
            isShuffled = false
        } else {
            originalQueue = queue
            var generator = SystemRandomNumberGenerator()
            queue = QueueOrder.shuffled(queue, currentIndex: currentIndex, using: &generator)
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

    var upcomingEntries: [QueueEntry] {
        guard queue.indices.contains(currentIndex) else { return [] }
        return Array(queue.dropFirst(currentIndex + 1))
    }

    func jump(to entryID: QueueEntry.ID) {
        guard let index = queue.firstIndex(where: { $0.id == entryID }), index > currentIndex else { return }
        currentIndex = index
        prepareCurrent(resumeAt: 0, autoPlay: true)
    }

    func moveUpcoming(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !offsets.isEmpty else { return }
        commitVisibleOrderForEditing()
        var upcoming = Array(queue.dropFirst(currentIndex + 1))
        let validOffsets = offsets.filter { upcoming.indices.contains($0) }
        guard !validOffsets.isEmpty else { return }
        let moving = validOffsets.sorted().map { upcoming[$0] }
        for index in validOffsets.sorted(by: >) { upcoming.remove(at: index) }
        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertion = min(max(destination - removedBeforeDestination, 0), upcoming.count)
        upcoming.insert(contentsOf: moving, at: insertion)
        queue.replaceSubrange((currentIndex + 1)..<queue.count, with: upcoming)
        originalQueue = queue
        queueDidMutate()
    }

    func moveUpcoming(entryID: QueueEntry.ID, by offset: Int) {
        guard let source = upcomingEntries.firstIndex(where: { $0.id == entryID }) else { return }
        let destination = min(max(source + offset, 0), upcomingEntries.count - 1)
        guard source != destination else { return }
        moveUpcoming(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + 1 : destination)
    }

    func removeUpcoming(atOffsets offsets: IndexSet) {
        let ids = offsets.compactMap { upcomingEntries.indices.contains($0) ? upcomingEntries[$0].id : nil }
        removeUpcoming(entryIDs: Set(ids))
    }

    func removeUpcoming(entryIDs: Set<QueueEntry.ID>) {
        guard !entryIDs.isEmpty else { return }
        commitVisibleOrderForEditing()
        let currentID = queue[currentIndex].id
        queue.removeAll { entryIDs.contains($0.id) && $0.id != currentID }
        originalQueue = queue
        queueDidMutate()
    }

    func clearUpNext() {
        guard !upcomingEntries.isEmpty else { return }
        commitVisibleOrderForEditing()
        let current = queue[currentIndex]
        queue = [current]
        currentIndex = 0
        originalQueue = queue
        queueDidMutate()
    }

    private func advance(automatic: Bool) {
        if automatic {
            // Publish paused Now Playing rate before the async prepare so the
            // system does not treat the ended item as still playing.
            if isPlaying {
                isPlaying = false
                updatePlaybackRate()
            }
            // Absorb a deferred Lock Screen pause for the ended item. The
            // window is refreshed again when the successor actually starts
            // (see `noteSuccessorPlaybackStarted`).
            suppressRemotePauseUntil = Date().addingTimeInterval(2.0)
        }
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
        playbackRequested = false
        suppressRemotePauseUntil = nil
        if duration > 0 { elapsed = duration }
        updateNowPlayingElapsed()
        closeCurrentSession(lifecycle: .completed)
        updatePlaybackRate()
        persistState()
    }

    /// Keep ignoring deferred remote pauses after the successor becomes audible.
    /// Without this, a long `reportStopped` can exhaust the advance-time window
    /// before `play()`, and a Lock Screen pause then cancels autoplay.
    private func noteSuccessorPlaybackStarted() {
        guard suppressRemotePauseUntil != nil else { return }
        suppressRemotePauseUntil = Date().addingTimeInterval(2.0)
    }

    func seek(to seconds: TimeInterval) {
        let target = min(max(seconds, 0), duration)
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsed = target
        updateNowPlayingElapsed()
        reportProgress(lifecycle: .seeking)
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
        closeCurrentSession(lifecycle: .stopped)
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
        playbackRequested = false
        suppressRemotePauseUntil = nil
        isPreparing = false
        qualityLabel = ""
        updateQueueControls()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? audioSession.deactivateAfterPlayback()
        if clearSnapshot { defaults.removeObject(forKey: snapshotKey) }
    }

    func stopAndWait(clearSnapshot: Bool = true) async {
        let pendingPreparation = preparationTask
        stop(clearSnapshot: clearSnapshot)
        await pendingPreparation?.value
        await reportingTask?.value
    }

    private func prepareCurrent(resumeAt: TimeInterval, autoPlay: Bool) {
        guard queue.indices.contains(currentIndex) else { return }
        let previousTrack = currentTrack
        let previousPlan = plan
        let previousPosition = elapsed
        let priorPreparation = preparationTask
        let priorReporting = reportingTask
        generation = UUID()
        let expectedGeneration = generation
        priorPreparation?.cancel()
        tearDownPlayer()
        plan = nil
        artwork = nil
        currentTrack = queue[currentIndex].track
        elapsed = max(0, resumeAt)
        duration = currentTrack?.duration ?? 0
        isPlaying = false
        playbackRequested = autoPlay
        isPreparing = true
        usingReplayCache = false
        errorMessage = nil
        qualityLabel = "Preparing…"
        lastProgressBucket = -1
        lastPersistenceBucket = -1
        updateQueueControls()
        persistState()

        guard let track = currentTrack else { return }
        guard let api, let userID else {
            isPreparing = false
            qualityLabel = ""
            return
        }
        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                await priorPreparation?.value
                await priorReporting?.value
                guard !Task.isCancelled, generation == expectedGeneration else { return }
                try audioSession.activateForPlayback()
                if let previousTrack, let previousPlan {
                    let stopTask = Task {
                        let outcome = await api.reportStopped(
                            itemID: previousTrack.id,
                            plan: previousPlan,
                            position: previousPosition
                        )
                        self.recordReportingOutcome(
                            outcome,
                            operation: .stop,
                            lifecycle: .replacing,
                            method: previousPlan.method,
                            position: previousPosition,
                            successReason: .replaced
                        )
                    }
                    await stopTask.value
                }
                guard !Task.isCancelled, generation == expectedGeneration else { return }
                if let localURL = localAudioURL?(track) {
                    plan = nil
                    usingReplayCache = false
                    Diagnostics.event("playback_local_source_selected")
                    let started = await startFilePlayback(
                        url: localURL,
                        track: track,
                        resumeAt: resumeAt,
                        expectedGeneration: expectedGeneration,
                        quality: "Downloaded"
                    )
                    if started {
                        await applyArtwork(for: track, api: api, expectedGeneration: expectedGeneration)
                        prefetchUpcomingAudio()
                    }
                    return
                }
                // Cached original audio plays immediately. The playback plan
                // (needed only for Jellyfin reporting) attaches afterwards so a
                // warm launch does not block on PlaybackInfo.
                if track.id != replayCacheDisabledForTrackID,
                   let cached = replayCachedAudioURL?(track) {
                    usingReplayCache = true
                    Diagnostics.event("playback_local_source_selected")
                    let started = await startFilePlayback(
                        url: cached,
                        track: track,
                        resumeAt: resumeAt,
                        expectedGeneration: expectedGeneration,
                        quality: "Direct Play"
                    )
                    if started {
                        attachPlanAndReport(
                            api: api,
                            userID: userID,
                            track: track,
                            resumeAt: resumeAt,
                            expectedGeneration: expectedGeneration
                        )
                        await applyArtwork(for: track, api: api, expectedGeneration: expectedGeneration)
                        prefetchUpcomingAudio()
                    }
                    return
                }
                replayCacheDisabledForTrackID = nil
                let selectedPlan = try await api.playbackPlan(itemID: track.id, userID: userID)
                guard !Task.isCancelled, generation == expectedGeneration else { return }
                let startTask = Task {
                    let outcome = await api.reportStarted(
                        itemID: track.id,
                        plan: selectedPlan,
                        position: resumeAt,
                        paused: !shouldStartPreparedPlayer
                    )
                    self.recordReportingOutcome(
                        outcome,
                        operation: .start,
                        lifecycle: shouldStartPreparedPlayer ? .playing : .paused,
                        method: selectedPlan.method,
                        position: resumeAt
                    )
                }
                await startTask.value
                guard !Task.isCancelled, generation == expectedGeneration else {
                    let stopTask = Task {
                        let outcome = await api.reportStopped(itemID: track.id, plan: selectedPlan, position: resumeAt)
                        self.recordReportingOutcome(
                            outcome,
                            operation: .stop,
                            lifecycle: .replacing,
                            method: selectedPlan.method,
                            position: resumeAt,
                            successReason: .replaced
                        )
                    }
                    await stopTask.value
                    return
                }
                plan = selectedPlan
                usingReplayCache = false
                Diagnostics.event("playback_plan_selected", ["method_code": selectedPlan.method.diagnosticCode])
                qualityLabel = selectedPlan.method == .directPlay ? "Direct Play" : "AAC transcode"
                if selectedPlan.method == .directPlay { cacheAudioForReplay?(track) }
                let player = AVPlayer(url: selectedPlan.url)
                self.player = player
                lastProgressBucket = Int(resumeAt / 10)
                lastPersistenceBucket = Int(resumeAt / 5)
                observe(player)
                if resumeAt > 0 {
                    await player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
                }
                guard !Task.isCancelled, generation == expectedGeneration else { return }
                let shouldPlay = shouldStartPreparedPlayer
                if shouldPlay {
                    player.play()
                    noteSuccessorPlaybackStarted()
                }
                isPlaying = shouldPlay
                isPreparing = false
                updateNowPlaying(track: track)
                await applyArtwork(for: track, api: api, expectedGeneration: expectedGeneration)
                prefetchUpcomingAudio()
            } catch {
                guard generation == expectedGeneration else { return }
                isPreparing = false
                qualityLabel = "Playback unavailable"
                errorMessage = error.localizedDescription
                Diagnostics.event("playback_prepare_failed", ["code": (error as NSError).code])
            }
        }
    }

    /// Starts AVPlayer on a local file (download or replay cache). Returns
    /// false if this generation was cancelled mid-seek.
    @discardableResult
    private func startFilePlayback(
        url: URL,
        track: Track,
        resumeAt: TimeInterval,
        expectedGeneration: UUID,
        quality: String
    ) async -> Bool {
        qualityLabel = quality
        let player = AVPlayer(url: url)
        self.player = player
        lastProgressBucket = Int(resumeAt / 10)
        lastPersistenceBucket = Int(resumeAt / 5)
        observe(player)
        if resumeAt > 0 {
            await player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
        }
        guard !Task.isCancelled, generation == expectedGeneration else { return false }
        let shouldPlay = shouldStartPreparedPlayer
        if shouldPlay {
            player.play()
            noteSuccessorPlaybackStarted()
        }
        isPlaying = shouldPlay
        isPreparing = false
        updateNowPlaying(track: track)
        return true
    }

    /// Cache-first artwork for Now Playing / lock screen, then one write-through
    /// fetch so a server-side art change updates the cache.
    private func applyArtwork(for track: Track, api: JellyfinAPI, expectedGeneration: UUID) async {
        let itemID = track.artworkItemID ?? track.albumID
        guard let itemID else { return }
        let serverID = scope.split(separator: ":").first.map(String.init) ?? ""
        let cacheKey = ArtworkCache.key(serverID: serverID, itemID: itemID)
        if let cached = await ArtworkCache.shared.image(forKey: cacheKey),
           generation == expectedGeneration {
            artwork = cached
            updateNowPlaying(track: track)
        }
        guard await ArtworkCache.shared.takeRevalidation(forKey: cacheKey) else { return }
        if let data = try? await api.artworkData(itemID: itemID),
           let image = UIImage(data: data), generation == expectedGeneration {
            artwork = image
            updateNowPlaying(track: track)
            await ArtworkCache.shared.store(data, forKey: cacheKey)
        } else {
            await ArtworkCache.shared.allowRevalidation(forKey: cacheKey)
        }
    }

    /// Fetch the Jellyfin play session after cached audio has already started
    /// so reporting can catch up without delaying audible start.
    private func attachPlanAndReport(
        api: JellyfinAPI,
        userID: String,
        track: Track,
        resumeAt: TimeInterval,
        expectedGeneration: UUID
    ) {
        let priorReporting = reportingTask
        reportingTask = Task { [weak self] in
            await priorReporting?.value
            guard let self, self.generation == expectedGeneration else { return }
            do {
                let selectedPlan = try await api.playbackPlan(itemID: track.id, userID: userID)
                guard self.generation == expectedGeneration else { return }
                self.plan = selectedPlan
                Diagnostics.event("playback_plan_selected", ["method_code": selectedPlan.method.diagnosticCode])
                let outcome = await api.reportStarted(
                    itemID: track.id,
                    plan: selectedPlan,
                    position: self.elapsed,
                    paused: !self.shouldStartPreparedPlayer
                )
                guard self.generation == expectedGeneration else {
                    let stop = await api.reportStopped(itemID: track.id, plan: selectedPlan, position: self.elapsed)
                    self.recordReportingOutcome(
                        stop,
                        operation: .stop,
                        lifecycle: .replacing,
                        method: selectedPlan.method,
                        position: self.elapsed,
                        successReason: .replaced
                    )
                    return
                }
                self.recordReportingOutcome(
                    outcome,
                    operation: .start,
                    lifecycle: self.shouldStartPreparedPlayer ? .playing : .paused,
                    method: selectedPlan.method,
                    position: resumeAt
                )
            } catch {
                // Cached audio keeps playing; reporting is best-effort here.
            }
        }
    }

    private func prefetchUpcomingAudio() {
        let upcoming = queue.dropFirst(currentIndex + 1).prefix(3)
        for entry in upcoming {
            cacheAudioForReplay?(entry.track)
        }
    }

    private func observe(_ player: AVPlayer) {
        let observedGeneration = generation
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, self.generation == observedGeneration else { return }
                self.elapsed = time.seconds.isFinite ? max(0, time.seconds) : 0
                // Do not clear `suppressRemotePauseUntil` from elapsed progress.
                // Deferred Lock Screen pauses often arrive shortly after the
                // successor becomes audible (~0.3–1s); clearing early was the
                // hole that left shuffle/queue autoplay paused after track one.
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
            Task { @MainActor in
                guard let self, self.generation == observedGeneration else { return }
                self.advance(automatic: true)
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                ?? NSError(domain: AVFoundationErrorDomain, code: -1)
            Task { @MainActor in
                self?.handleObservedPlayerFailure(error, observedGeneration: observedGeneration)
            }
        }
        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == observedGeneration else { return }
                self.handlePlaybackStalled()
            }
        }
        itemStatusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let error = item.error
            Task { @MainActor in
                guard let self, self.generation == observedGeneration else { return }
                switch status {
                case .failed:
                    self.handlePlayerFailure(error ?? NSError(domain: AVFoundationErrorDomain, code: -1))
                case .readyToPlay:
                    self.resumePreparedPlayerIfNeeded()
                default:
                    break
                }
            }
        }
    }

    /// Drop late failure callbacks from a previous item after the queue has
    /// already advanced and bumped `generation`.
    private func handleObservedPlayerFailure(_ error: Error, observedGeneration: UUID) {
        guard generation == observedGeneration else { return }
        handlePlayerFailure(error)
    }

    /// `play()` before `readyToPlay` can no-op across a track transition; re-assert
    /// when the item is ready if autoplay is still requested.
    private func resumePreparedPlayerIfNeeded() {
        guard shouldStartPreparedPlayer, let player else { return }
        if player.rate == 0 || !isPlaying {
            player.play()
            isPlaying = true
            noteSuccessorPlaybackStarted()
            updatePlaybackRate()
        }
    }

    private func tearDownPlayer() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        if let stalledObserver { NotificationCenter.default.removeObserver(stalledObserver) }
        itemStatusObservation?.invalidate()
        timeObserver = nil
        completionObserver = nil
        failureObserver = nil
        stalledObserver = nil
        itemStatusObservation = nil
        player?.pause()
        player = nil
    }

    private func reportProgress(lifecycle: Diagnostics.PlaybackLifecycle? = nil) {
        guard let api, let track = currentTrack, let plan else { return }
        let position = elapsed
        let paused = !isPlaying
        let priorReporting = reportingTask
        reportingTask = Task { [weak self] in
            await priorReporting?.value
            let outcome = await api.reportProgress(itemID: track.id, plan: plan, position: position, paused: paused)
            self?.recordReportingOutcome(
                outcome,
                operation: .progress,
                lifecycle: lifecycle ?? (paused ? .paused : .playing),
                method: plan.method,
                position: position
            )
        }
    }

    private func closeCurrentSession(
        lifecycle: Diagnostics.PlaybackLifecycle,
        successReason: Diagnostics.ReportingReason? = nil
    ) {
        guard let api, let track = currentTrack, let plan else { return }
        self.plan = nil
        let position = elapsed
        let priorReporting = reportingTask
        reportingTask = Task { [weak self] in
            await priorReporting?.value
            let outcome = await api.reportStopped(itemID: track.id, plan: plan, position: position)
            self?.recordReportingOutcome(
                outcome,
                operation: .stop,
                lifecycle: lifecycle,
                method: plan.method,
                position: position,
                successReason: successReason
            )
        }
    }

    private func recordReportingOutcome(
        _ outcome: PlaybackReportOutcome,
        operation: Diagnostics.ReportingOperation,
        lifecycle: Diagnostics.PlaybackLifecycle,
        method: PlaybackMethod,
        position: TimeInterval,
        successReason: Diagnostics.ReportingReason? = nil
    ) {
        if let failure = outcome.failure {
            lastReportingFailure = failure
            Diagnostics.playbackReporting(
                operation: operation,
                status: failure.kind == .cancelled ? .cancelled : .failed,
                reason: failure.diagnosticReason,
                lifecycle: lifecycle,
                method: method.diagnosticMethod,
                position: position
            )
        } else {
            lastReportingFailure = nil
            Diagnostics.playbackReporting(
                operation: operation,
                status: .succeeded,
                reason: successReason,
                lifecycle: lifecycle,
                method: method.diagnosticMethod,
                position: position
            )
        }
    }

    private func handlePlaybackStalled() {
        qualityLabel = "Buffering…"
        reportProgress(lifecycle: .stalled)
        Diagnostics.playbackReporting(
            operation: .progress,
            status: .attempted,
            reason: .stalled,
            lifecycle: .stalled,
            method: plan?.method.diagnosticMethod ?? .unavailable,
            position: elapsed
        )
    }

    private func handlePlayerFailure(_ error: Error) {
        if usingReplayCache, let track = currentTrack {
            usingReplayCache = false
            replayCacheDisabledForTrackID = track.id
            forgetCachedAudio?(track)
            let resumeAt = elapsed
            let shouldPlay = playbackRequested
            prepareCurrent(resumeAt: resumeAt, autoPlay: shouldPlay)
            return
        }
        guard plan != nil else { return }
        player?.pause()
        isPlaying = false
        playbackRequested = false
        isPreparing = false
        qualityLabel = "Playback unavailable"
        errorMessage = "Playback stopped because the audio stream failed. Try again."
        closeCurrentSession(lifecycle: .failed, successReason: .playbackError)
        updatePlaybackRate()
        persistState()
        Diagnostics.event("playback_failed", ["code": (error as NSError).code])
    }

    private func updateQueueControls() {
        canGoPrevious = currentIndex > 0 || elapsed > 0
        canGoNext = currentIndex + 1 < queue.count
        remoteCommands.updateAvailability(
            canGoPrevious: currentIndex > 0,
            canGoNext: canGoNext || (repeatMode == .all && !queue.isEmpty)
        )
    }

    private func insertIntoOriginalQueue(_ entry: QueueEntry) {
        guard queue.indices.contains(currentIndex),
              let originalIndex = originalQueue.firstIndex(where: { $0.id == queue[currentIndex].id }) else {
            originalQueue.append(entry)
            return
        }
        originalQueue.insert(entry, at: min(originalIndex + 1, originalQueue.count))
    }

    private func commitVisibleOrderForEditing() {
        guard isShuffled else { return }
        originalQueue = queue
        isShuffled = false
    }

    private func queueDidMutate() {
        updateQueueControls()
        refreshNowPlayingQueueMetadata()
        persistState()
    }

    private func configureRemoteCommands() {
        remoteCommands.register { [weak self] command in
            self?.handleRemoteCommand(command)
        }
    }

    private func handleRemoteCommand(_ command: PlaybackRemoteCommand) {
        Diagnostics.event("playback_remote_command", ["code": command.diagnosticCode])
        switch command {
        case .play:
            if !isPlaying { toggle() }
        case .pause:
            // Now Playing can deliver a deferred pause for the item that just
            // ended — while the successor prepares, or just after it starts.
            if isPreparing { return }
            if let until = suppressRemotePauseUntil, Date() < until {
                // Re-assert play if a pause slipped through before suppress.
                if playbackRequested, let player, !isPlaying {
                    player.play()
                    isPlaying = true
                    updatePlaybackRate()
                }
                return
            }
            if isPlaying { toggle() }
        case .previous:
            previous()
        case .next:
            next()
        case let .seek(position):
            seek(to: position)
        }
    }

    private func observeAudioLifecycle() {
        lifecycleObservers = [
            notificationCenter.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let fieldCount = notification.userInfo?.count ?? 0
                Task { @MainActor in
                    self?.handleInterruption(rawType: rawType, rawOptions: rawOptions, fieldCount: fieldCount)
                }
            },
            notificationCenter.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                Task { @MainActor in self?.handleRouteChange(rawReason: rawReason) }
            },
            notificationCenter.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleMediaServicesReset() }
            },
        ]
    }

    private func handleInterruption(rawType: UInt?, rawOptions: UInt, fieldCount: Int) {
        guard let rawType,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            Diagnostics.event("playback_interruption_invalid", ["field_count": fieldCount])
            return
        }
        switch type {
        case .began:
            handleInterruptionBegan()
        case .ended:
            handleInterruptionEnded(shouldResume: AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume))
        @unknown default:
            Diagnostics.event("playback_interruption_unknown", ["code": rawType])
        }
    }

    func handleInterruptionBegan() {
        // Session churn from activateForPlayback during an automatic advance can
        // emit a began without a matching ended. If we latched that, every
        // successor would prepare paused until the user pressed play.
        if isPreparing, suppressRemotePauseUntil != nil, !isPlaying {
            Diagnostics.event("playback_interruption_began_ignored_during_advance")
            return
        }
        audioInterruptionIsActive = true
        wasPlayingBeforeInterruption = isPlaying || (isPreparing && playbackRequested)
        if isPlaying {
            player?.pause()
            isPlaying = false
            updatePlaybackRate()
            reportProgress()
            persistState()
        }
        Diagnostics.event("playback_interruption_began", ["was_playing": wasPlayingBeforeInterruption ? 1 : 0])
    }

    func handleInterruptionEnded(shouldResume: Bool) {
        let hadActiveInterruption = audioInterruptionIsActive || wasPlayingBeforeInterruption
        audioInterruptionIsActive = false
        // Preserve autoplay across spurious non-resume interruptions while the
        // successor of an automatic advance is still preparing.
        if isPreparing, wasPlayingBeforeInterruption, suppressRemotePauseUntil != nil, !shouldResume {
            wasPlayingBeforeInterruption = false
            Diagnostics.event("playback_interruption_ended", ["allowed": 0, "preserved_prepare": 1, "resumed": 0])
            return
        }
        // Stray `ended` (including after an interruption we ignored during
        // automatic-advance prepare) must not clear autoplay intent.
        guard hadActiveInterruption else {
            wasPlayingBeforeInterruption = false
            Diagnostics.event("playback_interruption_ended", ["allowed": shouldResume ? 1 : 0, "ignored_stray": 1, "resumed": 0])
            return
        }
        playbackRequested = shouldResume && wasPlayingBeforeInterruption
        let resume = playbackRequested && player != nil
        wasPlayingBeforeInterruption = false
        if playbackRequested {
            do {
                try audioSession.activateForPlayback()
                if resume {
                    player?.play()
                    isPlaying = true
                    noteSuccessorPlaybackStarted()
                    updatePlaybackRate()
                    reportProgress()
                    persistState()
                }
            } catch {
                isPlaying = false
                playbackRequested = false
                errorMessage = "Playback could not resume after an audio interruption."
                Diagnostics.event("playback_audio_session_failed", ["code": (error as NSError).code, "operation": 1])
            }
        }
        Diagnostics.event("playback_interruption_ended", ["allowed": shouldResume ? 1 : 0, "resumed": resume && isPlaying ? 1 : 0])
    }

    private func handleRouteChange(rawReason: UInt) {
        let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) ?? .unknown
        handleRouteChange(reason: reason)
    }

    func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        let shouldPause = reason == .oldDeviceUnavailable && (isPlaying || (isPreparing && playbackRequested))
        if shouldPause {
            player?.pause()
            isPlaying = false
            playbackRequested = false
            updatePlaybackRate()
            reportProgress()
            persistState()
        }
        Diagnostics.event("playback_route_changed", ["code": reason.rawValue, "paused": shouldPause ? 1 : 0])
    }

    func handleMediaServicesReset() {
        guard currentTrack != nil else {
            Diagnostics.event("playback_media_services_reset", ["active": 0, "resumed": 0])
            return
        }
        let shouldContinue = playbackRequested && !audioInterruptionIsActive
        do {
            try audioSession.activateForPlayback()
            if shouldContinue { player?.play() }
            updatePlaybackRate()
            reportProgress()
            persistState()
            Diagnostics.event("playback_media_services_reset", ["active": 1, "resumed": shouldContinue ? 1 : 0])
        } catch {
            player?.pause()
            isPlaying = false
            playbackRequested = false
            updatePlaybackRate()
            reportProgress()
            persistState()
            errorMessage = "Playback could not recover after the audio system restarted."
            Diagnostics.event("playback_audio_session_failed", ["code": (error as NSError).code, "operation": 2])
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

private extension PlaybackRemoteCommand {
    var diagnosticCode: Int {
        switch self {
        case .play: 1
        case .pause: 2
        case .previous: 3
        case .next: 4
        case .seek: 5
        }
    }
}

private extension PlaybackMethod {
    var diagnosticCode: Int {
        switch self {
        case .directPlay: 1
        case .transcode: 2
        }
    }

    var diagnosticMethod: Diagnostics.PlaybackMethod {
        switch self {
        case .directPlay: .directPlay
        case .transcode: .transcode
        }
    }
}

private extension PlaybackReportFailure {
    var diagnosticReason: Diagnostics.ReportingReason {
        switch kind {
        case .cancelled: .cancelled
        case .transport: .network
        case .server: .server
        case .invalidResponse: .invalidResponse
        case .encoding: .encoding
        case .unknown: .unknown
        }
    }
}
