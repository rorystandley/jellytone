import Foundation

// The production gateway's diagnostic call sites remain compiled and executed,
// but the host harness does not write into the macOS user's Documents folder.
// Request/response truth is independently asserted by the controlled capture.
enum Diagnostics {
    static func event(_ name: String, _ values: [String: CustomStringConvertible] = [:]) {
        _ = name
        _ = values
    }
}

enum HarnessFailure: Error {
    case invalidArguments
    case versionMismatch
    case fixtureMissing
    case wrongPlaybackMethod
    case deliveryFailed
    case reportingFailed
}

@main
struct ProductionGatewayHarness {
    static func main() async throws {
        guard CommandLine.arguments.count == 6 else { throw HarnessFailure.invalidArguments }
        let endpoint = CommandLine.arguments[1]
        let expectedVersion = CommandLine.arguments[2]
        let passwordPath = CommandLine.arguments[3]
        let outputPath = CommandLine.arguments[4]
        let fixtureMarker = CommandLine.arguments[5]
        guard let baseURL = URL(string: endpoint) else { throw HarnessFailure.invalidArguments }

        var password = try String(contentsOfFile: passwordPath, encoding: .utf8)
        let anonymous = JellyfinAPI(baseURL: baseURL, deviceID: "phase2-live-integration")
        let info = try await anonymous.publicInfo()
        guard info.version == expectedVersion else { throw HarnessFailure.versionMismatch }
        let authentication = try await anonymous.authenticate(username: "root", password: password)
        password = ""
        let api = JellyfinAPI(
            baseURL: baseURL,
            deviceID: "phase2-live-integration",
            token: authentication.token
        )

        let libraries = try await api.musicLibraries(userID: authentication.userID)
        var selectedTrack: Track?
        for _ in 0..<30 where selectedTrack == nil {
            for library in libraries {
                let albums = try await api.albums(userID: authentication.userID, libraryID: library.id)
                for album in albums.albums {
                    let tracks = try await api.tracks(userID: authentication.userID, albumID: album.id)
                    if let match = tracks.first(where: { $0.name == fixtureMarker }) {
                        selectedTrack = match
                        break
                    }
                }
                if selectedTrack != nil { break }
            }
            if selectedTrack == nil { try await Task.sleep(for: .seconds(1)) }
        }
        guard let selectedTrack else { throw HarnessFailure.fixtureMissing }
        let plan = try await api.playbackPlan(itemID: selectedTrack.id, userID: authentication.userID)
        guard plan.method == .transcode else { throw HarnessFailure.wrongPlaybackMethod }

        var request = URLRequest(url: plan.url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              200..<300 ~= response.statusCode,
              !data.isEmpty else { throw HarnessFailure.deliveryFailed }
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)

        try requireAccepted(await api.reportStarted(
            itemID: selectedTrack.id, plan: plan, position: 0, paused: false
        ))
        try requireAccepted(await api.reportProgress(
            itemID: selectedTrack.id, plan: plan, position: 0.25, paused: false
        ))
        try requireAccepted(await api.reportProgress(
            itemID: selectedTrack.id, plan: plan, position: 0.25, paused: true
        ))
        try requireAccepted(await api.reportProgress(
            itemID: selectedTrack.id, plan: plan, position: 0.25, paused: false
        ))
        try requireAccepted(await api.reportProgress(
            itemID: selectedTrack.id, plan: plan, position: 0.75, paused: false
        ))
        try requireAccepted(await api.reportStopped(
            itemID: selectedTrack.id, plan: plan, position: 1.0
        ))

        // Only fixed allowlisted values reach stdout. Production diagnostics also
        // emit operation/status metadata, never credentials, endpoints or identity.
        print("LIVE_GATEWAY_RESULT version=pass transcode=aac-mp4 lifecycle=complete")
    }

    private static func requireAccepted(_ outcome: PlaybackReportOutcome) throws {
        guard case let .accepted(status) = outcome, 200..<300 ~= status else {
            throw HarnessFailure.reportingFailed
        }
    }
}
