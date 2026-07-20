import Foundation
import OSLog

enum Diagnostics {
    enum ReportingOperation: String, Sendable {
        case start
        case progress
        case stop
    }

    enum ReportingStatus: String, Sendable {
        case attempted
        case succeeded
        case failed
        case cancelled
    }

    enum ReportingReason: String, Sendable {
        case cancelled
        case encoding
        case invalidResponse = "invalid_response"
        case network
        case playbackError = "playback_error"
        case replaced
        case server
        case stalled
        case unknown
    }

    enum PlaybackLifecycle: String, Sendable {
        case preparing
        case playing
        case paused
        case seeking
        case replacing
        case completed
        case stopped
        case failed
        case stalled
        case restored
    }

    enum PlaybackMethod: String, Sendable {
        case directPlay = "direct_play"
        case transcode
        case unavailable
    }

    private static let logger = Logger(subsystem: "org.example.jellytone", category: "state")
    private static let fileLock = NSLock()

    private static let allowedEvents: Set<String> = [
        "albums_loaded",
        "albums_page_loaded",
        "authentication_succeeded",
        "connect_failed",
        "connect_started",
        "library_refresh_started",
        "music_search_loaded",
        "music_views_loaded",
        "playback_audio_session_failed",
        "playback_failed",
        "playback_interruption_began",
        "playback_interruption_ended",
        "playback_interruption_invalid",
        "playback_interruption_unknown",
        "playback_local_source_selected",
        "playback_media_services_reset",
        "playback_plan_selected",
        "playback_prepare_failed",
        "playback_remote_command",
        "playback_reporting",
        "playback_restored",
        "playback_route_changed",
        "report_failed",
        "request_cancelled",
        "request_failed",
        "request_started",
        "response_decode_failed",
        "response_received",
        "restore_refresh_failed",
        "session_restored",
    ]

    private static let allowedOperations: Set<String> = [
        "albums",
        "artist_albums",
        "authenticate",
        "favourite_albums",
        "favourite_artists",
        "favourite_tracks",
        "genre_albums",
        "genre_tracks",
        "genres",
        "music_search",
        "music_views",
        "playback_info",
        "playback_progress",
        "playback_started",
        "playback_stopped",
        "playlist_entries",
        "playlists",
        "public_info",
        "tracks",
        "track_favourite_mutation",
        "track_favourite_set",
        "track_favourite_clear",
        "playlist_rename_read",
        "playlist_rename_write",
    ]

    static func event(_ name: String, _ values: [String: CustomStringConvertible] = [:]) {
        let message = renderedEvent(name, values)
        logger.notice("\(message, privacy: .public)")
        print(message)
        persist("\(Int(Date().timeIntervalSince1970)) \(message)\n")
    }

    static func playbackReporting(
        operation: ReportingOperation,
        status: ReportingStatus,
        reason: ReportingReason? = nil,
        lifecycle: PlaybackLifecycle,
        method: PlaybackMethod? = nil,
        position: TimeInterval? = nil
    ) {
        var values: [String: CustomStringConvertible] = [
            "lifecycle": lifecycle.rawValue,
            "operation": operation.rawValue,
            "status": status.rawValue,
        ]
        if let reason { values["reason"] = reason.rawValue }
        if let method { values["method"] = method.rawValue }
        if let position { values["position_seconds"] = position }
        event("playback_reporting", values)
    }

    // This pure formatter is internal so privacy regression tests can exercise
    // the exact payload shared by OSLog, stdout, persistence, and export.
    static func renderedEvent(
        _ name: String,
        _ values: [String: CustomStringConvertible] = [:]
    ) -> String {
        guard allowedEvents.contains(name) else { return "JA_DIAG diagnostic_event_rejected" }
        let fields = values.compactMap { key, value -> (String, String)? in
            guard let safeValue = sanitizedValue(String(describing: value), for: key) else { return nil }
            return (key, safeValue)
        }
        .sorted { $0.0 < $1.0 }
        .map { "\($0.0)=\($0.1)" }
        .joined(separator: " ")
        return fields.isEmpty ? "JA_DIAG \(name)" : "JA_DIAG \(name) \(fields)"
    }

    private static func sanitizedValue(_ value: String, for key: String) -> String? {
        switch key {
        case "active", "allowed", "has_more", "paused", "resumed", "scoped", "was_playing":
            return sanitizedBoolean(value)
        case "album_count", "artist_count", "bytes", "count", "field_count", "queue_count", "total":
            return sanitizedInteger(value, range: 0...1_000_000_000)
        case "code":
            return sanitizedInteger(value, range: -1_000_000...1_000_000)
        case "domain":
            return sanitizedDomain(value)
        case "lifecycle":
            return PlaybackLifecycle(rawValue: value)?.rawValue
        case "method":
            return PlaybackMethod(rawValue: value)?.rawValue
        case "method_code":
            return sanitizedInteger(value, range: 0...32)
        case "operation":
            if allowedOperations.contains(value) { return value }
            if ReportingOperation(rawValue: value) != nil { return value }
            return sanitizedInteger(value, range: 0...32)
        case "outcome": return ["success", "authentication_expired", "transient", "permanent", "cancelled"].contains(value) ? value : nil
        case "retry_class": return ["none", "auth", "transient", "permanent", "cancelled"].contains(value) ? value : nil
        case "position_seconds":
            guard let position = Double(value), position.isFinite else { return nil }
            let boundedPosition = min(max(position, 0), 604_800)
            return String(Int(boundedPosition.rounded(.down)))
        case "reason":
            return ReportingReason(rawValue: value)?.rawValue
        case "status":
            if ReportingStatus(rawValue: value) != nil { return value }
            return sanitizedInteger(value, range: 100...599)
        default:
            return nil
        }
    }

    private static func sanitizedBoolean(_ value: String) -> String? {
        switch value.lowercased() {
        case "true", "1": return "1"
        case "false", "0": return "0"
        default: return nil
        }
    }

    private static func sanitizedInteger(_ value: String, range: ClosedRange<Int>) -> String? {
        guard let integer = Int(value) else { return nil }
        return String(integer.clamped(to: range))
    }

    private static func sanitizedDomain(_ value: String) -> String {
        switch value {
        case NSURLErrorDomain: return "network"
        case NSCocoaErrorDomain: return "cocoa"
        case NSPOSIXErrorDomain: return "posix"
        case NSOSStatusErrorDomain: return "os_status"
        default: return "other"
        }
    }

    private static func persist(_ line: String) {
        fileLock.lock()
        defer { fileLock.unlock() }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = line.data(using: .utf8) else { return }
        let url = documents.appending(path: "diagnostics.log")
        let existingSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if existingSize > 64 * 1_024 {
            try? data.write(to: url, options: .atomic)
            return
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
