import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.session == nil {
                ConnectionView()
            } else {
                LibraryView()
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil || model.playback.errorMessage != nil },
            set: {
                if !$0 {
                    model.errorMessage = nil
                    model.playback.clearError()
                }
            }
        )) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
                model.playback.clearError()
            }
        } message: {
            Text(model.errorMessage ?? model.playback.errorMessage ?? "Unknown error")
        }
    }
}
