import Foundation

/// Transport failures that mean the server could not be reached at all —
/// airplane mode, dead Wi-Fi, the server being down — as opposed to a
/// server-side or authentication problem. Background refreshes swallow these
/// so already-painted cached content stays on screen instead of a blocking
/// "Something went wrong" alert; the next successful refresh catches the UI
/// up silently.
enum OfflineError {
    static func isOffline(_ error: Error) -> Bool {
        switch (error as? URLError)?.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .timedOut,
             .internationalRoamingOff, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    /// Alert text for a failed background refresh: offline failures are silent
    /// (the cached UI stands), everything else surfaces as before.
    static func backgroundRefreshAlert(for error: Error) -> String? {
        isOffline(error) ? nil : error.localizedDescription
    }

    /// Combined failure line for multi-shelf refreshes (Home). Offline
    /// failures stay silent while cached shelves are on screen; with nothing
    /// cached they remain visible so the empty screen can explain itself.
    static func visibleFailureMessage(
        _ failures: [(message: String, isOffline: Bool)],
        hasCachedContent: Bool
    ) -> String? {
        let visible = failures.filter { !(hasCachedContent && $0.isOffline) }
        return visible.isEmpty ? nil : visible.map(\.message).joined(separator: " ")
    }
}
