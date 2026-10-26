import XCTest
@testable import Jellytone

/// Deterministic gateway so reconciliation outcomes are asserted without a network.
private actor FakeFavouriteGateway: FavouriteWriteGateway {
    private let outcome: FavouriteMutationOutcome
    private(set) var calls: [(itemID: String, desired: Bool)] = []
    init(outcome: FavouriteMutationOutcome) { self.outcome = outcome }
    func setFavourite(userID: String, itemID: String, desired: Bool) async -> FavouriteMutationOutcome {
        calls.append((itemID, desired))
        return outcome
    }
}

final class FavouriteOutboxTests: XCTestCase {
    private let scope = LibraryScope(serverID: "server-a", accountID: "account-a")

    func testEnqueuePersistsAndCompleteClearsAcrossItemKinds() async throws {
        let store = try SQLiteLibraryStore(databaseURL: temporaryDatabaseURL())

        let song = try await store.enqueueFavourite(scope: scope, itemID: "song-1", desired: true, sequence: 1)
        _ = try await store.enqueueFavourite(scope: scope, itemID: "album-1", desired: true, sequence: 2)
        _ = try await store.enqueueFavourite(scope: scope, itemID: "artist-1", desired: false, sequence: 3)

        let pending = try await store.pendingFavourites(scope: scope)
        XCTAssertEqual(pending.map(\.itemID), ["song-1", "album-1", "artist-1"])
        XCTAssertEqual(pending.map(\.desired), [true, true, false])

        try await store.completeFavourite(song)
        let afterComplete = try await store.pendingFavourites(scope: scope)
        XCTAssertEqual(afterComplete.map(\.itemID), ["album-1", "artist-1"])
    }

    func testReenqueueSupersedesDesiredForSameItem() async throws {
        let store = try SQLiteLibraryStore(databaseURL: temporaryDatabaseURL())
        _ = try await store.enqueueFavourite(scope: scope, itemID: "album-1", desired: true, sequence: 1)
        _ = try await store.enqueueFavourite(scope: scope, itemID: "album-1", desired: false, sequence: 2)

        let pending = try await store.pendingFavourites(scope: scope)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.desired, false)
        XCTAssertEqual(pending.first?.sequence, 2)
    }

    func testReconcileSuccessDrainsTheOutbox() async throws {
        let store = try SQLiteLibraryStore(databaseURL: temporaryDatabaseURL())
        _ = try await store.enqueueFavourite(scope: scope, itemID: "album-1", desired: true, sequence: 1)
        let reconciler = FavouriteReconciler(store: store)
        let gateway = FakeFavouriteGateway(outcome: .succeeded)

        await reconciler.reconcile(scope: scope, gateway: gateway, now: 0)

        let calls = await gateway.calls
        XCTAssertEqual(calls.map(\.itemID), ["album-1"])
        let pending = try await store.pendingFavourites(scope: scope)
        XCTAssertTrue(pending.isEmpty, "A succeeded write is marked completed and no longer pending")
    }

    func testAuthenticationExpiryPausesInsteadOfRetrying() async throws {
        let store = try SQLiteLibraryStore(databaseURL: temporaryDatabaseURL())
        _ = try await store.enqueueFavourite(scope: scope, itemID: "song-1", desired: true, sequence: 1)
        let reconciler = FavouriteReconciler(store: store)
        let gateway = FakeFavouriteGateway(outcome: .authenticationExpired)

        await reconciler.reconcile(scope: scope, gateway: gateway, now: 0)
        // A second pass must not re-hit the gateway while paused for auth.
        await reconciler.reconcile(scope: scope, gateway: gateway, now: 0)

        let calls = await gateway.calls
        XCTAssertEqual(calls.count, 1)
        let rows = try await store.pendingFavourites(scope: scope)
        XCTAssertEqual(rows.first?.state, .pausedAuth)
    }

    func testTransientFailureBacksOffAndStaysPending() async throws {
        let store = try SQLiteLibraryStore(databaseURL: temporaryDatabaseURL())
        _ = try await store.enqueueFavourite(scope: scope, itemID: "artist-1", desired: true, sequence: 1)
        let reconciler = FavouriteReconciler(store: store)
        let gateway = FakeFavouriteGateway(outcome: .transient)

        await reconciler.reconcile(scope: scope, gateway: gateway, now: 0)

        let rows = try await store.pendingFavourites(scope: scope)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.state, .pending)
        XCTAssertEqual(row.attempts, 1)
        XCTAssertGreaterThan(row.nextRetryAt, 0, "Backoff defers the next attempt")
    }

    private func temporaryDatabaseURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("favourite-outbox-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("library.sqlite")
    }
}
