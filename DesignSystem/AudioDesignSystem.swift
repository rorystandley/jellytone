import SwiftUI

/// Small semantic building blocks shared by the connection and playback shell.
/// Feature views should compose these instead of choosing unrelated local colours,
/// radii, or placeholder treatments.
enum AudioDesign {
    static let accent = Color(red: 0.93, green: 0.34, blue: 0.27)
    static let destructive = Color.red

    enum Space {
        static let xxs: CGFloat = 3
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let smallArtwork: CGFloat = 9
        static let compact: CGFloat = 12
        static let card: CGFloat = 20
        static let artwork: CGFloat = 28
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.18)
        static let standard = Animation.easeInOut(duration: 0.28)
    }

    static func titleFont(_ size: DynamicTypeSize) -> Font {
        size.isAccessibilitySize ? .title2.weight(.bold) : .largeTitle.weight(.bold)
    }

    static let readableContentWidth: CGFloat = 1_080
    static let readableTextWidth: CGFloat = 620
}

extension View {
    func audioCanvas() -> some View {
        background(Color(uiColor: .systemGroupedBackground))
            .tint(AudioDesign.accent)
    }

    func audioElevatedSurface(cornerRadius: CGFloat = AudioDesign.Radius.card) -> some View {
        background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct AudioArtwork: View {
    let image: UIImage?
    let label: String
    var cornerRadius: CGFloat = AudioDesign.Radius.artwork

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color(uiColor: .systemGray), Color(uiColor: .systemGray4), Color.black.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .accessibilityHidden(true)
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(image == nil ? "No artwork for \(label)" : "Artwork for \(label)")
    }
}

struct AudioIconButton: View {
    enum Kind { case primary, secondary }

    let systemImage: String
    let label: String
    var value: String? = nil
    var kind: Kind = .secondary
    var isActive = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(kind == .primary ? .title2.weight(.bold) : .body.weight(.semibold))
                .frame(width: kind == .primary ? 64 : 48, height: kind == .primary ? 64 : 48)
                .foregroundStyle(kind == .primary ? Color.white : (isActive ? AudioDesign.accent : Color.primary))
                .background {
                    Circle().fill(kind == .primary ? AudioDesign.accent : Color.primary.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(label)
        .accessibilityValue(value ?? (isActive ? "On" : "Off"))
    }
}

struct AudioStateView: View {
    enum Kind { case loading, empty, error }

    let kind: Kind
    let title: String
    let detail: String
    var actionTitle: String? = nil
    var actionIdentifier: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AudioDesign.Space.md) {
            Group {
                switch kind {
                case .loading: ProgressView().controlSize(.large)
                case .empty: Image(systemName: "music.note.list")
                case .error: Image(systemName: "exclamationmark.triangle.fill")
                }
            }
            .font(.title)
            .foregroundStyle(kind == .error ? AudioDesign.destructive : AudioDesign.accent)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(actionIdentifier ?? "")
            }
        }
        .padding(AudioDesign.Space.lg)
        .frame(maxWidth: 420)
        .audioElevatedSurface()
        .accessibilityElement(children: .combine)
    }
}

/// A shared music-first canvas that keeps regular-width screens composed instead
/// of stretching phone layouts across the full iPad display.
struct AudioBrowseContainer<Content: View>: View {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = AudioDesign.Space.lg
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: alignment, spacing: spacing) {
                content()
            }
            .frame(maxWidth: AudioDesign.readableContentWidth, alignment: .leading)
            .padding(.horizontal, AudioDesign.Space.md)
            .padding(.vertical, AudioDesign.Space.sm)
            .frame(maxWidth: .infinity)
        }
        .audioCanvas()
    }
}

struct AudioSectionHeading: View {
    let title: String
    var detail: String? = nil
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AudioDesign.Space.xxs) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.title2.bold())
            } else {
                Text(title).font(.title2.bold())
            }
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct AudioMissingArtwork: View {
    let label: String
    var systemImage = "music.note"
    var cornerRadius = AudioDesign.Radius.card

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(uiColor: .systemGray3), Color(uiColor: .systemGray5), Color.black.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .accessibilityHidden(true)
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel("No artwork for \(label)")
    }
}

struct AudioMusicCard<Artwork: View>: View {
    let title: String
    let subtitle: String?
    var detail: String? = nil
    var circular = false
    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        VStack(alignment: circular ? .center : .leading, spacing: AudioDesign.Space.xs) {
            artwork()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: AudioDesign.Radius.compact, style: .continuous)))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(circular ? .center : .leading)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(circular ? .center : .leading)
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: circular ? .center : .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AudioTrackRow: View {
    let position: Int?
    let title: String
    let artist: String
    var album: String? = nil
    var duration: String? = nil
    var showsArtwork = false
    var artworkItemID: String? = nil
    var artworkImageTag: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: AudioDesign.Space.sm) {
            if showsArtwork, let artworkItemID {
                Group {
                    if artworkImageTag != nil {
                        AuthenticatedArtworkView(itemID: artworkItemID, accessibilityLabel: "Artwork for \(title)")
                    } else {
                        AudioMissingArtwork(label: title, cornerRadius: AudioDesign.Radius.smallArtwork)
                    }
                }
                .frame(width: 52, height: 52)
            } else if let position {
                Text(String(position))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: AudioDesign.Space.xxs) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                Text(artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let album, !album.isEmpty {
                    Text(album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let duration {
                Text(duration).font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
            }
        }
        .padding(.vertical, AudioDesign.Space.xs)
        .contentShape(Rectangle())
    }
}

struct AudioPaginationView: View {
    let isLoading: Bool
    let message: String?
    let loadingTitle: String
    let retryTitle: String
    var identifier: String? = nil
    let retry: () -> Void

    @ViewBuilder var body: some View {
        if isLoading {
            ProgressView(loadingTitle)
                .frame(maxWidth: .infinity, minHeight: 56)
        } else if let message {
            VStack(spacing: AudioDesign.Space.sm) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(retryTitle, action: retry)
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(identifier ?? "")
            }
            .padding(AudioDesign.Space.md)
            .frame(maxWidth: AudioDesign.readableTextWidth)
            .frame(maxWidth: .infinity)
            .audioElevatedSurface(cornerRadius: AudioDesign.Radius.compact)
        }
    }
}

struct AudioPlayActions: View {
    let isDisabled: Bool
    let play: () -> Void
    let shuffle: () -> Void
    var playIdentifier: String? = nil
    var shuffleIdentifier: String? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AudioDesign.Space.sm) { buttons }
            VStack(spacing: AudioDesign.Space.sm) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        Button(action: play) {
            HStack(spacing: AudioDesign.Space.xs) {
                Image(systemName: "play.fill")
                Text("Play All").lineLimit(1)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, AudioDesign.Space.md)
            .frame(minHeight: 50)
            .background(AudioDesign.accent, in: Capsule())
        }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: true)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.45 : 1)
            .accessibilityIdentifier(playIdentifier ?? "")
        Button(action: shuffle) {
            HStack(spacing: AudioDesign.Space.xs) {
                Image(systemName: "shuffle")
                Text("Shuffle").lineLimit(1)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(AudioDesign.accent)
            .padding(.horizontal, AudioDesign.Space.md)
            .frame(minHeight: 50)
            .background(AudioDesign.accent.opacity(0.14), in: Capsule())
        }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: true)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.45 : 1)
            .accessibilityIdentifier(shuffleIdentifier ?? "")
    }
}
