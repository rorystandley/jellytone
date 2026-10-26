import SwiftUI

/// First-run connect screen — themed per `docs/design/design-system.md` /
/// onboarding mockup in `Jellytone.dc.html`. Connect/auth behavior is unchanged.
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
                    VStack(alignment: .leading, spacing: 0) {
                        appMark
                            .padding(.bottom, JellytoneTheme.Space.xl)

                        Text("Your music,\non your terms.")
                            .font(.jtOnboardingHero)
                            .foregroundStyle(Color.jtTextPrimary)
                            .tracking(-0.5)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, JellytoneTheme.Space.smPlus)
                            .accessibilityAddTraits(.isHeader)

                        Text("Jellytone connects directly to your own Jellyfin server. Nothing leaves your library.")
                            .font(.jtBody)
                            .foregroundStyle(Color.jtTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, JellytoneTheme.Space.xxxl)

                        credentialsCard
                            .padding(.bottom, JellytoneTheme.Space.screenMargin)

                        connectButton
                            .padding(.bottom, JellytoneTheme.Space.screenMargin)

                        Label("Your token stays in this device's Keychain.", systemImage: "lock.fill")
                            .font(.jtCaption)
                            .foregroundStyle(Color.jtTextTertiary)
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, JellytoneTheme.Space.xxl)
                    .padding(.top, JellytoneTheme.Space.screenTop)
                    .padding(.bottom, JellytoneTheme.Space.xxxl)
                    .frame(
                        maxWidth: proxy.size.width > 700 ? 540 : .infinity,
                        minHeight: proxy.size.height,
                        alignment: .topLeading
                    )
                }
            }
            .background(Color.jtBackground.ignoresSafeArea())
            .tint(Color.jtAccent)
            .navigationTitle("Jellytone")
            .navigationBarTitleDisplayMode(.inline)
            .alert("HTTP is not encrypted", isPresented: $showingHTTPWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Connect over Tailscale") { connect() }
            } message: {
                Text("Your password and music traffic are not protected by TLS. Continue only when this address is reached through your trusted Tailscale network.")
            }
        }
    }

    private var appMark: some View {
        Image(systemName: "music.note.list")
            .font(.system(size: ConnectionMetrics.markIcon, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: ConnectionMetrics.markSide, height: ConnectionMetrics.markSide)
            .background(Color.jtAccent, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.largeArtwork, style: .continuous))
            .shadow(color: Color.jtAccent.opacity(0.35), radius: JellytoneTheme.Space.md, y: JellytoneTheme.Space.sm)
            .accessibilityHidden(true)
    }

    private var credentialsCard: some View {
        VStack(spacing: 0) {
            TextField("https://jellyfin.example.com", text: $server)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textContentType(.URL)
                .font(.jtSubsectionHeader.weight(.regular))
                .foregroundStyle(Color.jtTextPrimary)
                .padding(JellytoneTheme.Space.lg)
            Rectangle().fill(Color.jtTrackOff).frame(height: 1)
            TextField("Username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .font(.jtSubsectionHeader.weight(.regular))
                .foregroundStyle(Color.jtTextPrimary)
                .padding(JellytoneTheme.Space.lg)
            Rectangle().fill(Color.jtTrackOff).frame(height: 1)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .font(.jtSubsectionHeader.weight(.regular))
                .foregroundStyle(Color.jtTextPrimary)
                .padding(JellytoneTheme.Space.lg)
        }
        .background(
            Color.jtSurface,
            in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.card, style: .continuous)
        )
    }

    private var connectButton: some View {
        Button {
            // Immediate press cue from #10; connect success/error haptics fire in AppModel.
            JellytoneHaptics.play(.light)
            if URLComponents(string: server)?.scheme?.lowercased() == "http" {
                showingHTTPWarning = true
            } else {
                connect()
            }
        } label: {
            HStack(spacing: JellytoneTheme.Space.sm) {
                Spacer(minLength: 0)
                if model.isLoading {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel("Connecting")
                } else {
                    Text("Connect")
                }
                Spacer(minLength: 0)
            }
            .font(.jtSubsectionHeader.weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, JellytoneTheme.Space.lg)
            .frame(maxWidth: .infinity)
            .background(
                Color.jtAccent,
                in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.card, style: .continuous)
            )
            .opacity(canConnect ? 1 : 0.45)
        }
        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
        .disabled(!canConnect)
        .accessibilityIdentifier("connection-connect")
    }

    private var canConnect: Bool {
        !server.isEmpty && !username.isEmpty && !password.isEmpty && !model.isLoading
    }

    private func connect() {
        Task { await model.connect(server: server, username: username, password: password) }
    }
}

private enum ConnectionMetrics {
    /// App mark tile from the onboarding mockup (64×64, 20pt radius via `largeArtwork`).
    static let markSide: CGFloat = 64
    static let markIcon: CGFloat = 28
}
