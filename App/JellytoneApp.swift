import SwiftUI

@main
struct JellytoneApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(appearance.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.runFavouriteReconciliation() }
            } else {
                model.playback.persistState()
            }
        }
    }
}
