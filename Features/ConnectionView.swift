import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showingHTTPWarning = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://jellyfin.example.com", text: $server)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                } header: {
                    Text("Your Jellyfin server")
                } footer: {
                    Text("Your access token is stored in Keychain. The password is used only for this sign-in request.")
                }

                Button {
                    if URLComponents(string: server)?.scheme?.lowercased() == "http" {
                        showingHTTPWarning = true
                    } else {
                        connect()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if model.isLoading { ProgressView() } else { Text("Connect") }
                        Spacer()
                    }
                }
                .disabled(server.isEmpty || username.isEmpty || password.isEmpty || model.isLoading)
            }
            .navigationTitle("Jellyfin Audio")
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
