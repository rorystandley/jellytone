import XCTest
@testable import Jellytone

@MainActor
final class JellytoneHapticsTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run {
            JellytoneHaptics.testObserver = nil
        }
        try await super.tearDown()
    }

    func testEveryStyleInvokesObserverWithoutCrashing() {
        var played: [JellytoneHaptics.Style] = []
        JellytoneHaptics.testObserver = { played.append($0) }

        let styles: [JellytoneHaptics.Style] = [
            .selection, .light, .medium, .soft, .rigid, .success, .warning, .error
        ]
        for style in styles {
            JellytoneHaptics.prepare(style)
            JellytoneHaptics.play(style)
        }

        XCTAssertEqual(played, styles)
    }

    func testSemanticShortcutsMapToExpectedStyles() {
        var played: [JellytoneHaptics.Style] = []
        JellytoneHaptics.testObserver = { played.append($0) }

        JellytoneHaptics.transport()
        JellytoneHaptics.primaryAction()
        JellytoneHaptics.playFromLibrary()
        JellytoneHaptics.favourite(adding: true)
        JellytoneHaptics.favourite(adding: false)
        JellytoneHaptics.scrubTick()
        JellytoneHaptics.toggle()
        JellytoneHaptics.chip()
        JellytoneHaptics.destructive()
        JellytoneHaptics.success()
        JellytoneHaptics.error()

        XCTAssertEqual(played, [
            .light, .medium, .light, .medium, .soft,
            .selection, .selection, .selection,
            .warning, .success, .error
        ])
    }
}
