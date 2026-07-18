import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showingHTTPWarning = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AudioDesign.Space.lg) {
                        VStack(alignment: .leading, spacing: AudioDesign.Space.sm) {
                            Image(systemName: "music.note.house.fill")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(AudioDesign.accent)
                                .accessibilityHidden(true)
                            Text("Your music, on your terms.")
                                .font(.largeTitle.weight(.bold))
                            Text("Sign in directly to a Jellyfin server you trust. Your password is used only for this request.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 0) {
                            TextField("https://jellyfin.example.com", text: $server)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textContentType(.URL)
                                .padding(AudioDesign.Space.md)
                            Divider()
                            TextField("Username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .padding(AudioDesign.Space.md)
                            Divider()
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .padding(AudioDesign.Space.md)
                        }
                        .audioElevatedSurface(cornerRadius: AudioDesign.Radius.compact)

                        Button {
                            if URLComponents(string: server)?.scheme?.lowercased() == "http" {
                                showingHTTPWarning = true
                            } else {
                                connect()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if model.isLoading { ProgressView().tint(.white) } else { Text("Connect") }
                                Spacer()
                            }
                            .font(.headline)
                            .frame(minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AudioDesign.accent)
                        .disabled(server.isEmpty || username.isEmpty || password.isEmpty || model.isLoading)

                        Label("Your access token is stored in Keychain. We never save your password.", systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, AudioDesign.Space.lg)
                    .padding(.vertical, AudioDesign.Space.xl)
                    .frame(maxWidth: proxy.size.width > 700 ? 540 : .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
            .audioCanvas()
            .navigationTitle("Jellyfin Audio")
            .navigationBarTitleDisplayMode(.inline)
            .alert("HTTP is not encrypted", isPresented: $showingHTTPWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Connect over Tailscale") { connect() }
            } message: {
                Text("Your password and music traffic are not protected by TLS. Continue only when this address is reached through your trusted Tailscale network.")
            }
        }
    }

    private func connect() {
        Task { await model.connect(server: server, username: username, password: password) }
    }
}
