import SwiftUI

/// Small semantic building blocks shared by the connection and playback shell.
/// Feature views should compose these instead of choosing unrelated local colours,
/// radii, or placeholder treatments.
enum AudioDesign {
    static let accent = Color(red: 0.93, green: 0.34, blue: 0.27)
    static let destructive = Color.red

    enum Space {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
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
                Button(actionTitle, action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding(AudioDesign.Space.lg)
        .frame(maxWidth: 420)
        .audioElevatedSurface()
        .accessibilityElement(children: .combine)
    }
}
