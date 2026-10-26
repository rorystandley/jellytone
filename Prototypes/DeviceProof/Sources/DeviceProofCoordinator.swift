@preconcurrency import AVFoundation
@preconcurrency import MediaPlayer
import CryptoKit
import Foundation

@MainActor
final class DeviceProofCoordinator: NSObject, ObservableObject {
    @Published private(set) var status = "Ready"
    private let events = ProofEventStore.shared
    private let downloadState = DownloadProofStateStore()
    private var player: AVPlayer?
    private var backgroundDelegate: BackgroundDownloadDelegate?
    private var hasRun = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            Task { @MainActor in self?.recordRoute(reason) }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in self?.recordInterruption(raw) }
        }
    }

    func runAll(probeURL: URL?) {
        guard !hasRun else { return }
        hasRun = true
        configureAudio()
        prepareCodecs(remoteBaseURL: probeURL?.deletingLastPathComponent())
        probeNetwork(URL(string: "https://example.com/")!)
        if let probeURL { probeNetwork(probeURL); startBackgroundDownloads(baseURL: probeURL.deletingLastPathComponent()) }
        else { events.append(category: "network", action: "lan_probe", result: "blocked", facts: ["reason": "missing_runtime_endpoint"]) }
    }

    func resetEvidence() {
        guard !hasRun else { return }
        events.reset()
        downloadState.reset()
    }

    func configureAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            installRemoteCommands()
            events.append(category: "route", action: "baseline", result: "observed", facts: [
                "route_type": session.currentRoute.outputs.first?.portType.rawValue ?? "none"
            ])
            guard let url = Bundle.main.url(forResource: "tone-a", withExtension: "m4a") else { throw ProofError.missingFixture }
            let player = AVPlayer(url: url)
            self.player = player
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: "Synthetic Phase 0 Tone",
                MPMediaItemPropertyPlaybackDuration: 2.0,
                MPNowPlayingInfoPropertyPlaybackRate: 0.0
            ]
            player.play()
            observeBackgroundContinuity()
            status = "Synthetic audio playing"
            events.append(category: "playback", action: "background_audio_started", result: "pass", facts: ["fixture": "synthetic", "route_type": session.currentRoute.outputs.first?.portType.rawValue ?? "none"])
        } catch {
            events.append(category: "playback", action: "background_audio_started", result: "fail", facts: ["reason": String(describing: error)])
        }
    }

    func prepareCodecs(remoteBaseURL: URL?) {
        let requiredCodecIDs = ["mp3", "aac", "alac", "flac", "vorbis_ogg", "opus_ogg", "opus_mp4"]
        guard let manifest = try? ProofMediaManifest.bundled() else {
            events.append(category: "codec", action: "prepare", result: "fail", facts: ["reason": "manifest_missing"])
            return
        }
        for codec in requiredCodecIDs {
            guard let entry = manifest.entry(id: codec),
                  let localURL = Bundle.main.url(forResource: entry.file, withExtension: nil) else {
                events.append(category: "codec", action: "prepare", result: "fail", facts: ["codec": codec, "reason": "fixture_missing"])
                continue
            }
            prepareCodec(codec, url: localURL, source: "local_synthetic")
            if let remoteBaseURL {
                prepareCodec(codec, url: remoteBaseURL.appendingPathComponent(entry.file), source: "remote_http_synthetic")
            } else {
                events.append(category: "codec", action: "prepare", result: "blocked", facts: ["codec": codec, "source": "remote_http_synthetic", "reason": "missing_runtime_endpoint"])
            }
        }
    }

    private func prepareCodec(_ codec: String, url: URL, source: String) {
        Task {
            do {
                let asset = AVURLAsset(url: url)
                let playable = try await asset.load(.isPlayable)
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                events.append(category: "codec", action: "prepare", result: playable && !tracks.isEmpty ? "pass" : "fail", facts: ["codec": codec, "source": source, "audio_tracks": String(tracks.count)])
            } catch {
                events.append(category: "codec", action: "prepare", result: "fail", facts: ["codec": codec, "source": source, "reason": String(describing: error)])
            }
        }
    }

    func probeNetwork(_ url: URL) {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        URLSession.shared.dataTask(with: request) { [events] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            let result = error == nil && status.map { 200..<300 ~= $0 } == true ? "pass" : "fail"
            events.append(category: "network", action: "ats_lan_probe", result: result, facts: [
                "transport": url.scheme == "https" ? "https" : "local_http",
                "status_class": status.map { "\($0 / 100)xx" } ?? "none",
                "byte_count": String(data?.count ?? 0),
                "error": error.map { String(describing: $0) } ?? "none",
                "url": url.absoluteString
            ])
        }.resume()
    }

    func startBackgroundDownloads(baseURL: URL) {
        guard let manifest = try? ProofMediaManifest.bundled() else {
            events.append(category: "download", action: "scheduled", result: "fail", facts: ["reason": "manifest_entry_missing"])
            return
        }
        let expectedEntries = ["aac", "mp3", "flac"].compactMap(manifest.entry)
        guard expectedEntries.count == 3 else {
            events.append(category: "download", action: "scheduled", result: "fail", facts: ["reason": "manifest_entry_missing"])
            return
        }
        let runIdentifier = events.activeRunIdentifier()
        let runSuffix = runIdentifier.replacingOccurrences(of: "-", with: "").prefix(12)
        let identifier = Bundle.main.bundleIdentifier.map { "\($0).background.\(runSuffix)" }
            ?? "org.example.phase0.deviceproof.background.\(runSuffix)"
        let delegate = BackgroundDownloadDelegate(events: events, stateStore: downloadState, runIdentifier: runIdentifier)
        backgroundDelegate = delegate
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let tasks = expectedEntries.map { entry in
            (session.downloadTask(with: baseURL.appendingPathComponent(entry.file)), entry)
        }
        do {
            try downloadState.save(DownloadProofState(
                sessionIdentifier: identifier,
                runIdentifier: runIdentifier,
                tasks: tasks.map { DownloadProofTask(taskIdentifier: $0.0.taskIdentifier, media: $0.1, phase: .scheduled) },
                acknowledgementCount: 0
            ))
        } catch {
            events.append(category: "download", action: "scheduled", result: "fail", facts: ["reason": "state_persistence_failed"])
            session.invalidateAndCancel()
            return
        }
        tasks.forEach { $0.0.resume() }
        events.append(category: "download", action: "scheduled", result: "pass", facts: ["task_count": String(tasks.count), "media_identities": expectedEntries.map(\.id).joined(separator: ","), "url": baseURL.absoluteString])
        events.append(category: "download", action: "cancellation_resume", result: "blocked", facts: ["reason": DownloadProofPolicy.cancellationResumeStatus])
    }

    func restoreBackgroundSession(identifier: String, completion: @escaping () -> Void) {
        guard let state = try? downloadState.load(),
              state.sessionIdentifier == identifier,
              state.runIdentifier == events.activeRunIdentifier() else {
            events.append(category: "download", action: "session_restored", result: "fail", facts: ["reason": "restoration_state_missing_or_mismatched"])
            completion()
            return
        }
        let delegate = BackgroundDownloadDelegate(
            events: events,
            stateStore: downloadState,
            runIdentifier: state.runIdentifier,
            completion: completion
        )
        backgroundDelegate = delegate
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        _ = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        events.append(category: "download", action: "session_restored", result: "pass")
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        // These callbacks are nonisolated. The player lives on the main actor.
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.player?.play()
                self?.events.append(category: "remote", action: "play", result: "pass")
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.player?.pause()
                self?.events.append(category: "remote", action: "pause", result: "pass")
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.player?.timeControlStatus == .playing ? self.player?.pause() : self.player?.play()
                self.events.append(category: "remote", action: "toggle", result: "pass")
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = position.positionTime
            Task { @MainActor in
                self?.player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
                self?.events.append(category: "remote", action: "seek", result: "pass")
            }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.player?.seek(to: .zero)
                self?.events.append(category: "remote", action: "previous", result: "pass")
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.player?.seek(to: .zero)
                self?.events.append(category: "remote", action: "next", result: "pass")
            }
            return .success
        }
        events.append(category: "remote", action: "registered", result: "pass", facts: [
            "commands": "play,pause,toggle,seek,previous,next"
        ])
    }

    private func observeBackgroundContinuity() {
        let started = DispatchTime.now().uptimeNanoseconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            guard let self else { return }
            let elapsed = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
            let playing = self.player?.timeControlStatus == .playing
            self.events.append(
                category: "playback",
                action: "background_continuity_observed",
                result: playing && elapsed >= 300 ? "pass" : "fail",
                facts: ["elapsed_seconds": String(elapsed), "player_state": playing ? "playing" : "not_playing"]
            )
        }
    }

    private func recordInterruption(_ raw: UInt?) {
        guard let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        events.append(
            category: "interruption",
            action: type == .began ? "began" : "ended",
            result: "observed",
            facts: ["type_code": String(raw)]
        )
    }

    private func recordRoute(_ reason: AVAudioSession.RouteChangeReason?) {
        events.append(category: "route", action: "changed", result: "observed", facts: ["reason_code": String(reason?.rawValue ?? 0), "route_type": AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "none"])
    }
}

private enum ProofError: Error { case missingFixture }

final class BackgroundDownloadDelegate: NSObject, URLSessionDownloadDelegate, URLSessionDelegate, @unchecked Sendable {
    private let events: ProofEventStore
    private let stateStore: DownloadProofStateStore
    private let runIdentifier: String
    private var completion: (() -> Void)?
    init(
        events: ProofEventStore,
        stateStore: DownloadProofStateStore,
        runIdentifier: String,
        completion: (() -> Void)? = nil
    ) {
        self.events = events
        self.stateStore = stateStore
        self.runIdentifier = runIdentifier
        self.completion = completion
    }

    private func record(category: String, action: String, result: String, facts: [String: String] = [:]) {
        events.append(
            category: category,
            action: action,
            result: result,
            facts: facts,
            expectedRunIdentifier: runIdentifier
        )
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let taskState = try stateStore.task(downloadTask.taskIdentifier)
            let expected = taskState.media
            guard let response = downloadTask.response as? HTTPURLResponse else { throw DownloadProofError.unexpectedStatus }
            let destination = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("verified-downloads").appendingPathComponent(expected.file)
            try DownloadFileInstaller.installValidated(temporaryURL: location, response: response, expected: expected, destination: destination)
            try stateStore.updatePhase(.installed, taskIdentifier: downloadTask.taskIdentifier)
            record(category: "download", action: "completed_atomically", result: "pass", facts: ["byte_count": String(expected.bytes), "media_identity": expected.id, "sha256": expected.sha256])
            Task {
                do {
                    try await DownloadFileInstaller.probeFinalAudio(at: destination)
                    try stateStore.updatePhase(.probed, taskIdentifier: downloadTask.taskIdentifier)
                    self.record(category: "download", action: "final_file_probed", result: "pass", facts: ["media_identity": expected.id])
                } catch {
                    self.record(category: "download", action: "final_file_probed", result: "fail", facts: ["reason": String(describing: error)])
                }
            }
        } catch {
            record(category: "download", action: "completed_atomically", result: "fail", facts: ["reason": String(describing: error)])
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        record(category: "download", action: "task_finished", result: error == nil ? "pass" : "fail", facts: ["error": error.map { String(describing: $0) } ?? "none"])
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        do {
            let first = try stateStore.recordAcknowledgement()
            record(category: "download", action: first ? "events_acknowledged" : "duplicate_acknowledgement_rejected", result: "pass", facts: ["exactly_once": first ? "true" : "false"])
            if first {
                completion?()
                completion = nil
            }
        } catch {
            record(category: "download", action: "events_acknowledged", result: "fail", facts: ["reason": "acknowledgement_state_failed"])
        }
    }
}
