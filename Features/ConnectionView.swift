import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

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
                    Task { await model.connect(server: server, username: username, password: password) }
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
        }
    }
}
