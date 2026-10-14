import Foundation

enum PlaylistRenameGatewayOutcome: Sendable, Equatable {
    case succeeded, alreadyApplied, authenticationExpired, transient, conflict(JellyfinAPI.PlaylistRenameRemoteState)
    case notFound, permissionDenied, validationFailed, cancelled
}
enum PlaylistRenameConflictChoice: Sendable, Equatable { case keepServerVersion, useMyName }

extension PlaylistRenameMutation {
    func resolving(_ choice: PlaylistRenameConflictChoice, remote: JellyfinAPI.PlaylistRenameRemoteState) -> PlaylistRenameMutation {
        var copy = self
        switch choice {
        case .keepServerVersion:
            copy.baseRevision = remote.revision
            copy.baseName = remote.name
            copy.desiredName = remote.name
            copy.state = .completed
        case .useMyName:
            copy.baseRevision = remote.revision
            copy.baseName = remote.name
            copy.state = .pending
            copy.attempts = 0
            copy.nextRetryAt = 0
        }
        return copy
    }
}

protocol PlaylistRenameGateway: Sendable {
    func renamePlaylist(userID: String, playlistID: String, expectedRevision: String, desiredName: String) async -> PlaylistRenameGatewayOutcome
}

actor PlaylistRenameReconciler {
    private let store: any LibraryStoring
    init(store: any LibraryStoring) { self.store = store }
    func reconcile(scope: LibraryScope, gateway: any PlaylistRenameGateway, now: Int64 = 0, resumeAuthentication: Bool = false) async {
        guard let rows = try? await store.pendingPlaylistRenames(scope: scope) else { return }
        for row in rows where (row.state == .pending || (resumeAuthentication && row.state == .pausedAuth)) && row.nextRetryAt <= now {
            switch await gateway.renamePlaylist(userID: scope.accountID, playlistID: row.playlistID, expectedRevision: row.baseRevision, desiredName: row.desiredName) {
            case .succeeded, .alreadyApplied: var next=row; next.state = .completed; try? await store.updatePlaylistRename(next)
            case .authenticationExpired: var next=row; next.state = .pausedAuth; try? await store.updatePlaylistRename(next)
            case .conflict: var next=row; next.state = .conflict; try? await store.updatePlaylistRename(next)
            case .notFound, .permissionDenied, .validationFailed: var next=row; next.state = .terminal; try? await store.updatePlaylistRename(next)
            case .cancelled: break
            case .transient: var next=row; next.attempts += 1; next.nextRetryAt = now + Int64(min(3600, 1 << min(next.attempts, 10))); try? await store.updatePlaylistRename(next)
            }
        }
    }
}

extension JellyfinAPI: PlaylistRenameGateway {}

struct EmptyResponse: Decodable, Sendable {}
