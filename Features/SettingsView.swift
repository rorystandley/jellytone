import SwiftUI

/// Settings sheet (opened from the Home avatar): account identity with
/// sign-out, and data/storage controls including the image-cache purge.
/// Themed per docs/design/design-system.md — grouped rows in surface cards,
/// coral for every action, no second accent colour.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    @State private var imageCacheBytes: Int64?
    @State private var isSigningOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                    header
                    appearanceSection
                    accountSection
                    dataSection
                }
                .padding(.horizontal, JellytoneTheme.Space.screenMargin)
                .padding(.top, JellytoneTheme.Space.xl)
                .padding(.bottom, JellytoneTheme.Space.xxxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.jtBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings-done")
                }
            }
            .tint(Color.jtAccent)
            .task { imageCacheBytes = await ArtworkCache.shared.diskBytes() }
        }
    }

    private var header: some View {
        Text("Settings")
            .font(.jtLargeTitle)
            .foregroundStyle(Color.jtTextPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        section(title: "Appearance") {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                HStack(spacing: JellytoneTheme.Space.md) {
                    Text("Appearance")
                        .font(.jtRowTitle)
                        .foregroundStyle(Color.jtTextPrimary)
                    Spacer(minLength: JellytoneTheme.Space.sm)
                    Text(appearance.title)
                        .font(.jtRowTitle)
                        .foregroundStyle(Color.jtTextSecondary)
                }
            }
            .padding(.vertical, JellytoneTheme.Space.mdPlus)
            .accessibilityIdentifier("settings-appearance")
        }
    }

    // MARK: Account

    private var accountSection: some View {
        section(title: "Account") {
            infoRow(label: "Server", value: model.session?.serverName ?? "—")
            rowDivider
            infoRow(label: "User", value: model.session?.username ?? "—")
            rowDivider
            Button {
                guard !isSigningOut else { return }
                isSigningOut = true
                Task {
                    await model.logout()
                    dismiss()
                }
            } label: {
                Text("Sign Out")
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, JellytoneTheme.Space.mdPlus)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
            .accessibilityIdentifier("settings-sign-out")
        }
    }

    // MARK: Data & Storage

    private var dataSection: some View {
        section(title: "Data & Storage") {
            infoRow(label: "Image Cache", value: imageCacheLabel)
            rowDivider
            Button {
                Task {
                    await ArtworkCache.shared.clear()
                    imageCacheBytes = await ArtworkCache.shared.diskBytes()
                }
            } label: {
                Text("Clear Image Cache")
                    .font(.jtRowTitle)
                    .foregroundStyle(Color.jtAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, JellytoneTheme.Space.mdPlus)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleLarge))
            .accessibilityIdentifier("settings-clear-image-cache")
        }
    }

    private var imageCacheLabel: String {
        guard let bytes = imageCacheBytes else { return "Calculating…" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: Building blocks

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: JellytoneTheme.Space.mdPlus) {
            Text(title)
                .font(.jtSectionHeader)
                .foregroundStyle(Color.jtTextPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, JellytoneTheme.Space.lg)
                .background(Color.jtSurface, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous))
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: JellytoneTheme.Space.md) {
            Text(label)
                .font(.jtRowTitle)
                .foregroundStyle(Color.jtTextPrimary)
            Spacer(minLength: JellytoneTheme.Space.sm)
            Text(value)
                .font(.jtRowTitle)
                .foregroundStyle(Color.jtTextSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, JellytoneTheme.Space.mdPlus)
        .accessibilityElement(children: .combine)
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.jtBorder).frame(height: 1)
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JellytoneTheme.Space.xl) {
                Text("Choose how Jellytone appears.")
                    .font(.jtBody)
                    .foregroundStyle(Color.jtTextSecondary)

                VStack(spacing: 0) {
                    ForEach(AppearancePreference.allCases) { preference in
                        appearanceOption(preference)
                        if preference != AppearancePreference.allCases.last {
                            Rectangle().fill(Color.jtBorder).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, JellytoneTheme.Space.lg)
                .background(Color.jtSurface, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous))
            }
            .padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.vertical, JellytoneTheme.Space.xl)
        }
        .background(Color.jtBackground.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func appearanceOption(_ preference: AppearancePreference) -> some View {
        Button {
            appearance = preference
        } label: {
            HStack(spacing: JellytoneTheme.Space.md) {
                VStack(alignment: .leading, spacing: JellytoneTheme.Space.xxs) {
                    Text(preference.title)
                        .font(.jtRowTitle)
                        .foregroundStyle(Color.jtTextPrimary)
                    if preference == .system {
                        Text("Uses your device appearance")
                            .font(.jtRowSubtitle)
                            .foregroundStyle(Color.jtTextSecondary)
                    }
                }
                Spacer()
                if appearance == preference {
                    Image(systemName: "checkmark")
                        .font(.jtRowTitle)
                        .foregroundStyle(Color.jtAccent)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, JellytoneTheme.Space.mdPlus)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(appearance == preference ? .isSelected : [])
        .accessibilityIdentifier("settings-appearance-option-\(preference.rawValue)")
    }
}
