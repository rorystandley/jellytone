import UIKit

/// Purposeful, short haptic cues for premium controls.
///
/// Call from shared chrome and intentional action entry points — not from every
/// navigation-row tap. Generators are prepared lazily so the first press feels
/// immediate. System haptic settings are respected automatically.
///
/// See `docs/design/design-system.md` §8 and `AGENTS.md` / `PRODUCT_PLAN.md`.
///
/// UIKit feedback generators are main-actor types. The namespace is isolated
/// so the shared generators, `prepare()`, and the test observer stay on that actor.
@MainActor
enum JellytoneHaptics {
    enum Style: Equatable {
        /// Index rails, scrub ticks, chips, toggles, segmented choices.
        case selection
        /// Transport, play-from-row, secondary actions, light chrome taps.
        case light
        /// Primary play/pause, favouriting on.
        case medium
        /// Soft dismiss / unfavourite / collapse.
        case soft
        /// Emphasised discrete control (rare).
        case rigid
        /// Connection / download completed successfully.
        case success
        /// Destructive or cautionary confirmations (remove, sign out, clear).
        case warning
        /// Connection / hard failure.
        case error
    }

    /// Test seam. Observes plays without replacing the real generators.
    static var testObserver: (@MainActor (Style) -> Void)?

    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// Warm generators so the next interaction has no first-tap latency.
    static func prepare(_ styles: Style...) {
        let targets = styles.isEmpty ? [Style.light, .selection, .medium] : styles
        for style in targets {
            switch style {
            case .selection: selectionGenerator.prepare()
            case .light: lightImpact.prepare()
            case .medium: mediumImpact.prepare()
            case .soft: softImpact.prepare()
            case .rigid: rigidImpact.prepare()
            case .success, .warning, .error: notificationGenerator.prepare()
            }
        }
    }

    static func play(_ style: Style) {
        testObserver?(style)
        switch style {
        case .selection:
            selectionGenerator.selectionChanged()
        case .light:
            lightImpact.impactOccurred(intensity: 0.9)
        case .medium:
            mediumImpact.impactOccurred(intensity: 1.0)
        case .soft:
            softImpact.impactOccurred(intensity: 0.8)
        case .rigid:
            rigidImpact.impactOccurred(intensity: 1.0)
        case .success:
            notificationGenerator.notificationOccurred(.success)
        case .warning:
            notificationGenerator.notificationOccurred(.warning)
        case .error:
            notificationGenerator.notificationOccurred(.error)
        }
    }

    // MARK: Semantic shortcuts

    static func transport() { play(.light) }
    static func primaryAction() { play(.medium) }
    static func playFromLibrary() { play(.light) }
    static func favourite(adding: Bool) { play(adding ? .medium : .soft) }
    static func scrubTick() { play(.selection) }
    static func toggle() { play(.selection) }
    static func chip() { play(.selection) }
    static func destructive() { play(.warning) }
    static func success() { play(.success) }
    static func error() { play(.error) }
}
