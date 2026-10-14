import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    var coordinator: DeviceProofCoordinator?
    private var pendingBackgroundSession: (String, () -> Void)?
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        if let coordinator {
            Task { @MainActor in coordinator.restoreBackgroundSession(identifier: identifier, completion: completionHandler) }
        } else {
            pendingBackgroundSession = (identifier, completionHandler)
        }
    }

    @MainActor func attach(_ coordinator: DeviceProofCoordinator) {
        self.coordinator = coordinator
        if let pendingBackgroundSession {
            coordinator.restoreBackgroundSession(identifier: pendingBackgroundSession.0, completion: pendingBackgroundSession.1)
            self.pendingBackgroundSession = nil
        }
    }
}

@main
struct DeviceProofApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var coordinator = DeviceProofCoordinator()

    init() { }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 18) {
                Text("Phase 0 Device Proof").font(.title2).bold()
                Text(coordinator.status).accessibilityIdentifier("proof-status")
                Button("Run synthetic proof") { coordinator.runAll(probeURL: Self.probeURL) }
                    .buttonStyle(.borderedProminent)
                Text("No credentials or private media are used. Results are redacted before persistence.")
                    .font(.footnote).multilineTextAlignment(.center)
            }
            .padding()
            .onAppear {
                delegate.attach(coordinator)
                if ProcessInfo.processInfo.arguments.contains("--autorun") {
                    if ProcessInfo.processInfo.arguments.contains("--reset-evidence") {
                        coordinator.resetEvidence()
                    }
                    coordinator.runAll(probeURL: Self.probeURL)
                }
            }
        }
    }

    private static var probeURL: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--probe-url"), arguments.indices.contains(index + 1) else { return nil }
        return URL(string: arguments[index + 1])
    }
}
