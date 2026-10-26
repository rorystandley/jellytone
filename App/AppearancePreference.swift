import SwiftUI

/// The user's app-wide appearance choice, persisted in `UserDefaults` through
/// `AppStorage`. `system` intentionally maps to `nil`, allowing iOS to follow
/// the current device appearance.
enum AppearancePreference: String, CaseIterable, Identifiable {
    static let storageKey = "appearance-preference"

    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
