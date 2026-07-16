import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: UserSession?
    @Published private(set) var libraries: [MusicLibrary] = []
    @Published var selectedLibraryID: String?
    @Published private(set) var albums: [Album] = []
    @Published private(set) var tracksByAlbum: [String: [Track]] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let playback = PlaybackController()

    private let defaults: UserDefaults
    private static let profileKey = "active-profile"
    private static let deviceIDKey = "installation-device-id"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            defaults.removeObject(forKey: Self.profileKey)
            KeychainTokenStore.delete()
        }
        if defaults.string(forKey: Self.deviceIDKey) == nil {
            defaults.set(UUID().uuidString, forKey: Self.deviceIDKey)
        }
        restoreSession()
    }

    var api: JellyfinAPI? {
        guard let session else { return nil }
        return JellyfinAPI(baseURL: session.serverURL, deviceID: session.deviceID, token: session.accessToken)
    }

    func connect(server: String, username: String, password: String) async {
        Diagnostics.event("connect_started")
        guard let serverURL = normalizedServerURL(server) else {
            errorMessage = APIError.invalidServerURL.localizedDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let deviceID = installationDeviceID
            let unauthenticated = JellyfinAPI(baseURL: serverURL, deviceID: deviceID)
            let info = try await unauthenticated.publicInfo()
            let authentication = try await unauthenticated.authenticate(username: username, password: password)
            Diagnostics.event("authentication_succeeded")
            try KeychainTokenStore.save(authentication.token)
            let session = UserSession(
                serverURL: serverURL,
                serverID: info.id,
                serverName: info.serverName,
                serverVersion: info.version,
                userID: authentication.userID,
                username: authentication.username,
                accessToken: authentication.token,
                deviceID: deviceID
            )
            self.session = session
            persistProfile(session)
            try await refreshLibraries()
        } catch {
            let failure = error as NSError
            Diagnostics.event("connect_failed", ["code": failure.code, "domain": failure.domain])
            errorMessage = error.localizedDescription
        }
    }

    func refreshLibraries() async throws {
        guard let session, let api else { return }
        Diagnostics.event("library_refresh_started")
        libraries = try await api.musicLibraries(userID: session.userID)
        Diagnostics.event("music_views_loaded", ["count": libraries.count])
        if selectedLibraryID == nil || !libraries.contains(where: { $0.id == selectedLibraryID }) {
            selectedLibraryID = libraries.first?.id
        }
        try await refreshAlbums(libraryID: selectedLibraryID)
    }

    func refreshAlbums(libraryID: String?) async throws {
        guard let session, let api else { return }
        isLoading = true
        defer { isLoading = false }
        albums = try await api.albums(userID: session.userID, libraryID: libraryID)
        Diagnostics.event("albums_loaded", ["count": albums.count, "scoped": libraryID != nil])
    }

    func selectLibrary(_ id: String) async {
        selectedLibraryID = id
        do { try await refreshAlbums(libraryID: id) }
        catch { errorMessage = error.localizedDescription }
    }

    func tracks(for album: Album) async -> [Track] {
        if let existing = tracksByAlbum[album.id] { return existing }
        guard let session, let api else { return [] }
        do {
            let tracks = try await api.tracks(userID: session.userID, albumID: album.id)
            tracksByAlbum[album.id] = tracks
            return tracks
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func play(_ track: Track) {
        guard let api else { return }
        playback.play(track, using: api)
    }

    func logout() {
        playback.stop()
        KeychainTokenStore.delete()
        defaults.removeObject(forKey: Self.profileKey)
        session = nil
        libraries = []
        albums = []
        tracksByAlbum = [:]
        selectedLibraryID = nil
    }

    private var installationDeviceID: String {
        defaults.string(forKey: Self.deviceIDKey) ?? "jellyfin-audio-installation"
    }

    private func normalizedServerURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              components.host != nil else { return nil }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func persistProfile(_ session: UserSession) {
        struct Profile: Codable {
            let serverURL: URL
            let serverID: String
            let serverName: String
            let serverVersion: String
            let userID: String
            let username: String
            let deviceID: String
        }
        let profile = Profile(serverURL: session.serverURL, serverID: session.serverID,
                              serverName: session.serverName, serverVersion: session.serverVersion,
                              userID: session.userID, username: session.username, deviceID: session.deviceID)
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: Self.profileKey) }
    }

    private func restoreSession() {
        struct Profile: Codable {
            let serverURL: URL
            let serverID: String
            let serverName: String
            let serverVersion: String
            let userID: String
            let username: String
            let deviceID: String
        }
        guard let data = defaults.data(forKey: Self.profileKey),
              let profile = try? JSONDecoder().decode(Profile.self, from: data),
              let token = KeychainTokenStore.load() else { return }
        session = UserSession(serverURL: profile.serverURL, serverID: profile.serverID,
                              serverName: profile.serverName, serverVersion: profile.serverVersion,
                              userID: profile.userID, username: profile.username,
                              accessToken: token, deviceID: profile.deviceID)
        Diagnostics.event("session_restored")
        Task {
            do { try await refreshLibraries() }
            catch {
                let failure = error as NSError
                Diagnostics.event("restore_refresh_failed", ["code": failure.code, "domain": failure.domain])
                errorMessage = error.localizedDescription
            }
        }
    }
}
