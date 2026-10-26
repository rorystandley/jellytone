import SwiftUI

// MARK: - Jellytone theme
//
// Single source of truth for the "liquid glass" editorial look
// (see docs/design/design-system.md). No raw hex, point size, or magic
// spacing/radius value should appear outside this file — feature views compose
// `JellytoneTheme.*`, the `Color`/`Font` extensions below, and the
// ButtonStyle/ViewModifier helpers at the bottom. Semantic colours live in the
// asset catalog (light/dark variants) under the same JT-prefixed names.
// Haptics live in `Haptics.swift` (`JellytoneHaptics`) and are wired through
// shared controls plus intentional AppModel / DownloadManager entry points.

enum JellytoneTheme {

    // MARK: Spacing (base scale: 4/6/8/10/12/14/16/18/20/22/24/30/32/56)
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let smPlus: CGFloat = 10
        static let md: CGFloat = 12
        static let mdPlus: CGFloat = 14
        static let lg: CGFloat = 16
        static let lgPlus: CGFloat = 18
        /// Standard horizontal screen margin.
        static let screenMargin: CGFloat = 20
        static let xlMinus: CGFloat = 22
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 30
        static let xxxl: CGFloat = 32
        /// Top inset that clears the nav/status area on scroll screens.
        static let screenTop: CGFloat = 56
    }

    // MARK: Corner radius
    enum Radius {
        static let smallArtwork: CGFloat = 8
        static let rowArtwork: CGFloat = 9
        static let compactArtwork: CGFloat = 12
        static let groupedCard: CGFloat = 14
        static let gridArtwork: CGFloat = 14
        static let card: CGFloat = 16
        static let heroCard: CGFloat = 18
        static let largeArtwork: CGFloat = 20
        /// Capsules, chips, toggle tracks.
        static let pill: CGFloat = 999
    }

    // MARK: Motion
    enum Motion {
        /// The only pressed-state treatment in the app: scale down, ease out fast.
        static let press = Animation.easeOut(duration: 0.12)
        static let pressScaleDefault: CGFloat = 0.9
        static let pressScaleSmall: CGFloat = 0.85
        static let pressScaleLarge: CGFloat = 0.94
        /// Spring used by toggle switches and similar overshoot affordances.
        static let toggleSpring = Animation.interpolatingSpring(stiffness: 260, damping: 18)
        static let toggleDuration = 0.28
        /// Colour/opacity cross-fades (theme switch, lyric word highlight).
        static let crossfade = Animation.easeInOut(duration: 0.25)
        /// Gentle pulse for skeleton placeholder blocks during a cold load.
        static let skeletonPulse = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
        /// Standard content cross-fade (track change, lyrics toggle).
        static let standard = Animation.easeInOut(duration: 0.28)
        /// Snappy control-state change (play/pause, shuffle active).
        static let quick = Animation.easeOut(duration: 0.18)
    }

    // MARK: Player chrome metrics (Mini Player + Now Playing + Queue)
    enum Player {
        static let miniArtwork: CGFloat = 38
        static let miniTransport: CGFloat = 34
        static let miniProgressHeight: CGFloat = 2
        static let miniHorizontalInset: CGFloat = 8
        static let miniBottomInset: CGFloat = 6
        static let accessoryTransportIcon: CGFloat = 20
        static let nowPlayingPrimary: CGFloat = 68
        static let transportIcon: CGFloat = 20
        static let transportSkipIcon: CGFloat = 26
        static let nowPlayingArtworkMax: CGFloat = 290
        static let queueArtwork: CGFloat = 38
    }

    // MARK: Hue wheel for generated artwork-placeholder gradients
    static let placeholderHues: [Double] = [29, 260, 145, 200, 330, 55, 190, 15, 280, 100]

    /// Deterministic hue for an item so repeat visits render the same gradient.
    /// Uses a stable FNV-1a hash — `String.hashValue` is seeded per launch.
    static func placeholderHue(forID id: String) -> Double {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return placeholderHues[Int(hash % UInt64(placeholderHues.count))]
    }

    static func placeholderGradient(hue: Double) -> LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.55, lightness: 0.42),
                Color(hue: (hue + 30).truncatingRemainder(dividingBy: 360), saturation: 0.55, lightness: 0.20),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Color

private extension Color {
    /// HSL initializer for the generated placeholder-artwork gradients (OKLCH in the
    /// source spec approximates closely enough to HSL for placeholder purposes).
    init(hue: Double, saturation: Double, lightness: Double) {
        self.init(Color(hue: hue / 360, saturation: saturation, brightness: lightness + saturation * min(lightness, 1 - lightness)))
    }
}

extension Color {
    // Semantic surface/text tokens, resolved from the asset catalog so the
    // light/dark pair follows the trait collection (and the app's explicit
    // Dark/Light/Auto setting via `.preferredColorScheme`). Now Playing always
    // forces `.dark` colorScheme regardless of the app setting.
    static let jtBackground = Color("JTBackground")
    static let jtSurface = Color("JTSurface")
    static let jtTextPrimary = Color("JTTextPrimary")
    static let jtTextSecondary = Color("JTTextSecondary")
    static let jtTextTertiary = Color("JTTextTertiary")
    static let jtBorder = Color("JTBorder")
    static let jtTrackOff = Color("JTTrackOff")

    /// The one and only accent hue in the app. Never introduce a second brand colour —
    /// destructive/warning actions reuse this, not red.
    static let jtAccent = Color("JTAccent")
    static let jtAccentDim = Color.jtAccent.opacity(0.16)

    // Glass chrome fills (always tinted dark-neutral; sit above artwork or blur).
    static let jtGlassChromeFill = Color(white: 0.5, opacity: 0.20)
    static let jtGlassMiniPlayerFill = Color(white: 0.5, opacity: 0.28)
    static let jtGlassCardFill = Color(white: 0.5, opacity: 0.20)
    static let jtGlassButtonFill = Color.white.opacity(0.14)
    static let jtGlassBorder = Color.white.opacity(0.15)
    static let jtGlassBorderSubtle = Color.white.opacity(0.10)
    static let jtGlassBorderOverArtwork = Color.white.opacity(0.25)
}

// MARK: - Typography
// System font (SF) only, per spec — no custom typefaces.

extension Font {
    static let jtLargeTitle = Font.system(size: 38, weight: .heavy)
    static let jtOnboardingHero = Font.system(size: 32, weight: .bold)
    static let jtDetailTitle = Font.system(size: 24, weight: .heavy)
    static let jtSectionHeader = Font.system(size: 22, weight: .heavy)
    static let jtHeroCardTitle = Font.system(size: 18, weight: .heavy)
    static let jtSubsectionHeader = Font.system(size: 17, weight: .heavy)
    static let jtNowPlayingTitle = Font.system(size: 21, weight: .heavy)
    static let jtRowTitle = Font.system(size: 14.5, weight: .semibold)
    static let jtBody = Font.system(size: 14.5, weight: .regular)
    static let jtRowSubtitle = Font.system(size: 12.5, weight: .medium)
    static let jtCaption = Font.system(size: 12, weight: .semibold)
    static let jtEyebrow = Font.system(size: 11, weight: .bold)
}

extension View {
    /// The full eyebrow treatment: `.jtEyebrow` font, uppercase, wide tracking.
    func jtEyebrowStyle() -> some View {
        font(.jtEyebrow)
            .textCase(.uppercase)
            .tracking(1.5)
    }
}

// MARK: - Glass chrome view modifiers

struct JellytoneGlassChrome: ViewModifier {
    var fill: Color = .jtGlassChromeFill
    var border: Color = .jtGlassBorder
    var cornerRadius: CGFloat = 0
    var withShadow = false

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: withShadow ? .black.opacity(0.35) : .clear, radius: withShadow ? 6 : 0, y: withShadow ? 2 : 0)
    }
}

extension View {
    /// Tab bar / sheet nav chrome: 24pt-blur translucent surface with a hairline edge.
    func jtGlassChrome(cornerRadius: CGFloat = 0, withShadow: Bool = false) -> some View {
        modifier(JellytoneGlassChrome(cornerRadius: cornerRadius, withShadow: withShadow))
    }

    /// Mini player card.
    func jtGlassMiniPlayer(cornerRadius: CGFloat = JellytoneTheme.Radius.card) -> some View {
        modifier(JellytoneGlassChrome(fill: .jtGlassMiniPlayerFill, cornerRadius: cornerRadius, withShadow: true))
    }

    /// Settings grouped rows, Downloads toggle row, unselected library filter pills.
    func jtGlassCard(cornerRadius: CGFloat = JellytoneTheme.Radius.groupedCard) -> some View {
        modifier(JellytoneGlassChrome(fill: .jtGlassCardFill, border: .jtGlassBorderSubtle, cornerRadius: cornerRadius))
    }

    /// Icon/pill buttons floating over artwork (Shuffle, heart, download, back, more).
    func jtGlassButtonOverArtwork(cornerRadius: CGFloat = JellytoneTheme.Radius.pill) -> some View {
        modifier(JellytoneGlassChrome(fill: .jtGlassButtonFill, border: .jtGlassBorderOverArtwork, cornerRadius: cornerRadius))
    }

    /// Standard 20pt screen margin + 56pt top clearance used by every top-level tab screen.
    func jtScreenPadding() -> some View {
        padding(.horizontal, JellytoneTheme.Space.screenMargin)
            .padding(.top, JellytoneTheme.Space.screenTop)
    }

    /// Hairline rule under a section header (`border` token, full content width).
    func jtHairline() -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(Color.jtBorder).frame(height: 1)
        }
    }

    /// Drop shadow for small horizontal-scroll cards that float on the plain
    /// background (grid/list content directly on the background gets none).
    func jtFloatingCardShadow() -> some View {
        shadow(color: .black.opacity(0.3), radius: 7, y: 6)
    }

    /// Full-bleed hero vignette: a dark wash at the top keeps overlaid header
    /// chrome legible (chrome over artwork is always dark-tinted), and the
    /// bottom melts into the screen background so the artwork dissolves into
    /// the page — adapts to light/dark via the background token.
    func jtHeroVignette() -> some View {
        overlay(
            LinearGradient(
                colors: [.black.opacity(0.45), .clear],
                startPoint: .top, endPoint: .init(x: 0.5, y: 0.45)
            )
        )
        .overlay(
            LinearGradient(
                colors: [Color.jtBackground.opacity(0), Color.jtBackground],
                startPoint: .init(x: 0.5, y: 0.4), endPoint: .bottom
            )
        )
    }

    /// Bottom-anchored scrim for title text laid over artwork/hero imagery.
    func jtArtworkScrim(strength: Double = 0.72) -> some View {
        overlay(
            LinearGradient(
                colors: [.black.opacity(strength), .black.opacity(0.05)],
                startPoint: .bottom, endPoint: .init(x: 0.5, y: 0.45)
            )
        )
    }
}

// MARK: - Skeleton placeholder rows (cold-load state for track lists)

/// Pulsing placeholder rows shown only when a list has nothing cached to
/// paint. Cached content always renders immediately instead of this.
struct JellytoneSkeletonRows: View {
    var rows = 8
    var label = "Loading"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    private static var thumbSide: CGFloat { 42 }
    private static var titleBarSize: CGSize { .init(width: 160, height: 12) }
    private static var subtitleBarSize: CGSize { .init(width: 90, height: 10) }
    private static var dimOpacity: Double { 0.55 }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: JellytoneTheme.Space.md) {
                    RoundedRectangle(cornerRadius: JellytoneTheme.Radius.smallArtwork, style: .continuous)
                        .fill(Color.jtSurface)
                        .frame(width: Self.thumbSide, height: Self.thumbSide)
                    VStack(alignment: .leading, spacing: JellytoneTheme.Space.xs) {
                        Capsule().fill(Color.jtSurface)
                            .frame(width: Self.titleBarSize.width, height: Self.titleBarSize.height)
                        Capsule().fill(Color.jtSurface)
                            .frame(width: Self.subtitleBarSize.width, height: Self.subtitleBarSize.height)
                    }
                    Spacer()
                }
                .padding(.vertical, JellytoneTheme.Space.smPlus)
            }
        }
        .opacity(dimmed ? Self.dimOpacity : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(JellytoneTheme.Motion.skeletonPulse) { dimmed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// Pulsing placeholder grid for album/playlist cold loads. Prefer cached
/// content; only show this when the grid has nothing to paint yet.
struct JellytoneSkeletonGrid: View {
    var columns = 2
    var rows = 3
    var label = "Loading"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    private static var dimOpacity: Double { 0.55 }

    var body: some View {
        let items = Array(0..<(columns * rows))
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: JellytoneTheme.Space.mdPlus), count: columns),
            spacing: JellytoneTheme.Space.mdPlus
        ) {
            ForEach(items, id: \.self) { _ in
                VStack(alignment: .leading, spacing: JellytoneTheme.Space.sm) {
                    RoundedRectangle(cornerRadius: JellytoneTheme.Radius.gridArtwork, style: .continuous)
                        .fill(Color.jtSurface)
                        .aspectRatio(1, contentMode: .fit)
                    Capsule().fill(Color.jtSurface)
                        .frame(width: 96, height: 10)
                    Capsule().fill(Color.jtSurface)
                        .frame(width: 64, height: 9)
                }
            }
        }
        .opacity(dimmed ? Self.dimOpacity : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(JellytoneTheme.Motion.skeletonPulse) { dimmed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

// MARK: - Press-scale (the only pressed-state affordance in the app)

struct JellytonePressScaleStyle: ButtonStyle {
    var scale: CGFloat = JellytoneTheme.Motion.pressScaleDefault
    /// Optional press-down haptic. Leave `nil` for navigation rows; use `.light`
    /// / `.selection` for intentional controls that aren't covered elsewhere.
    var haptic: JellytoneHaptics.Style? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(JellytoneTheme.Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                guard pressed, let haptic else { return }
                JellytoneHaptics.play(haptic)
            }
    }
}

// MARK: - Capsule buttons (Play / Shuffle)

struct JellytoneCapsuleButtonStyle: ButtonStyle {
    enum Kind {
        /// Solid white fill, black content — used over dark artwork headers.
        case primaryOverArtwork
        /// Translucent glass fill, white content — used over dark artwork headers.
        case secondaryOverArtwork
        /// Solid accent fill, white content — used in flat/dark contexts (e.g. playlist header).
        case primaryFlat
        /// Accent-tinted glass fill, accent content — used in flat/dark contexts.
        case secondaryFlat
    }

    var kind: Kind = .primaryFlat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.jtRowTitle.weight(.bold))
            .padding(.horizontal, JellytoneTheme.Space.xlMinus)
            .padding(.vertical, JellytoneTheme.Space.md)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? JellytoneTheme.Motion.pressScaleLarge : 1)
            .animation(JellytoneTheme.Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                // Primary capsules usually fire a semantic haptic from AppModel
                // (play/shuffle). Keep press-haptics for secondary/retry only.
                guard pressed else { return }
                switch kind {
                case .primaryOverArtwork, .primaryFlat:
                    break
                case .secondaryOverArtwork, .secondaryFlat:
                    JellytoneHaptics.play(.light)
                }
            }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primaryOverArtwork: Color.white
        case .secondaryOverArtwork: Capsule().fill(Color.clear).jtGlassButtonOverArtwork(cornerRadius: JellytoneTheme.Radius.pill)
        case .primaryFlat: Color.jtAccent
        case .secondaryFlat: Color.jtAccentDim
        }
    }

    private var foreground: Color {
        switch kind {
        case .primaryOverArtwork: return .black
        case .secondaryOverArtwork: return .white
        case .primaryFlat: return .white
        case .secondaryFlat: return .jtAccent
        }
    }
}

// MARK: - Circular icon buttons (back, more, heart, download, nav)

struct JellytoneIconButtonStyle: ButtonStyle {
    enum Kind {
        /// 34×34 nav chrome (back/more) — glass fill.
        case nav
        /// 44×44 detail-header actions over artwork — glass fill.
        case detailAction
        /// Mini player transport buttons — subtle white-tinted glass, no border.
        case transportCompact
        /// Now Playing primary transport (68×68 solid white circle, black glyph).
        case transportPrimary
    }

    var kind: Kind = .nav
    var isActive = false

    private var diameter: CGFloat {
        switch kind {
        case .nav: return 34
        case .detailAction: return 44
        case .transportCompact: return 34
        case .transportPrimary: return 68
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.34, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background(background)
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? JellytoneTheme.Motion.pressScaleSmall : 1)
            .animation(JellytoneTheme.Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                guard pressed else { return }
                switch kind {
                case .transportPrimary:
                    JellytoneHaptics.primaryAction()
                case .transportCompact, .detailAction:
                    JellytoneHaptics.transport()
                case .nav:
                    JellytoneHaptics.play(.soft)
                }
            }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .nav, .detailAction:
            Circle().fill(Color.clear).jtGlassButtonOverArtwork()
        case .transportCompact:
            Circle().fill(Color.white.opacity(0.14))
        case .transportPrimary:
            Circle().fill(Color.white)
        }
    }

    private var foreground: Color {
        switch kind {
        case .transportPrimary: return .black
        default: return isActive ? .jtAccent : .white
        }
    }
}

// MARK: - Toggle switch (Gapless Playback, Volume Normalisation, Wi-Fi only)

struct JellytoneToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let onColor = Color.jtAccent
        let offColor = Color.jtTrackOff
        return HStack {
            configuration.label
            Spacer()
            RoundedRectangle(cornerRadius: JellytoneTheme.Radius.pill, style: .continuous)
                .fill(configuration.isOn ? onColor : offColor)
                .frame(width: 44, height: 26)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                        .padding(2),
                    alignment: configuration.isOn ? .trailing : .leading
                )
                .onTapGesture {
                    JellytoneHaptics.toggle()
                    withAnimation(JellytoneTheme.Motion.toggleSpring) {
                        configuration.isOn.toggle()
                    }
                }
        }
    }
}

// MARK: - Library filter / genre chip

struct JellytoneChipButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.jtRowSubtitle.weight(.bold))
            .padding(.horizontal, JellytoneTheme.Space.lg)
            .padding(.vertical, JellytoneTheme.Space.sm)
            .foregroundStyle(isSelected ? Color.white : Color.jtTextPrimary.opacity(0.85))
            .background {
                if isSelected {
                    Capsule().fill(Color.jtAccent.opacity(0.85))
                } else {
                    Capsule().fill(Color.clear).jtGlassCard(cornerRadius: JellytoneTheme.Radius.pill)
                }
            }
            .scaleEffect(configuration.isPressed ? JellytoneTheme.Motion.pressScaleDefault : 1)
            .animation(JellytoneTheme.Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                guard pressed else { return }
                JellytoneHaptics.chip()
            }
    }
}

extension ButtonStyle where Self == JellytonePressScaleStyle {
    static func jtPressScale(
        _ scale: CGFloat = JellytoneTheme.Motion.pressScaleDefault,
        haptic: JellytoneHaptics.Style? = nil
    ) -> Self {
        .init(scale: scale, haptic: haptic)
    }
}

extension ButtonStyle where Self == JellytoneCapsuleButtonStyle {
    static func jtCapsule(_ kind: JellytoneCapsuleButtonStyle.Kind) -> Self { .init(kind: kind) }
}

extension ButtonStyle where Self == JellytoneIconButtonStyle {
    static func jtIcon(_ kind: JellytoneIconButtonStyle.Kind, isActive: Bool = false) -> Self { .init(kind: kind, isActive: isActive) }
}

extension ButtonStyle where Self == JellytoneChipButtonStyle {
    static func jtChip(isSelected: Bool) -> Self { .init(isSelected: isSelected) }
}

extension ToggleStyle where Self == JellytoneToggleStyle {
    static var jellytone: Self { .init() }
}

// MARK: - Transport buttons (Mini Player + Now Playing)

/// Shared play/pause/skip/shuffle/repeat control used by player chrome only.
/// Primary = solid white circle (Now Playing); compact = glass circle (legacy
/// Mini Player); secondary = bare icon with active accent (shuffle/repeat).
struct JellytoneTransportButton: View {
    enum Kind {
        case primary
        case compact
        case secondary
    }

    let systemImage: String
    let label: String
    var value: String? = nil
    var kind: Kind = .secondary
    var isActive = false
    var action: () -> Void

    var body: some View {
        Button {
            switch kind {
            case .primary:
                JellytoneHaptics.primaryAction()
            case .compact, .secondary:
                JellytoneHaptics.transport()
            }
            action()
        } label: {
            Image(systemName: systemImage)
                .font(iconFont)
                .foregroundStyle(foreground)
                .frame(width: hitSide, height: hitSide)
                .background(background)
                .contentShape(Circle())
        }
        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
        .accessibilityLabel(label)
        .accessibilityValue(value ?? (isActive ? "On" : "Off"))
    }

    private var hitSide: CGFloat {
        switch kind {
        case .primary: return JellytoneTheme.Player.nowPlayingPrimary
        case .compact: return JellytoneTheme.Player.miniTransport
        case .secondary: return 44
        }
    }

    private var iconFont: Font {
        switch kind {
        case .primary:
            return .system(size: JellytoneTheme.Player.nowPlayingPrimary * 0.34, weight: .semibold)
        case .compact:
            return .system(size: JellytoneTheme.Player.accessoryTransportIcon, weight: .semibold)
        case .secondary:
            // Skip arrows read larger than mode toggles (design-system.md §4.5).
            let size = (systemImage.contains("backward") || systemImage.contains("forward"))
                ? JellytoneTheme.Player.transportSkipIcon
                : JellytoneTheme.Player.transportIcon
            return .system(size: size, weight: .semibold)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .black
        case .compact, .secondary: return isActive ? .jtAccent : Color.jtTextPrimary.opacity(0.85)
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            Circle().fill(Color.white)
        case .compact:
            Circle().fill(Color.white.opacity(0.14))
        case .secondary:
            Color.clear
        }
    }
}

// MARK: - Empty / loading state card (Queue, detail fallbacks)

/// Compact empty/error/loading card used inside lists and player sheets.
/// Replaces legacy `AudioStateView` on player chrome surfaces.
struct JellytoneStateCard: View {
    enum Kind { case loading, empty, error }

    let kind: Kind
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: JellytoneTheme.Space.md) {
            Group {
                switch kind {
                case .loading: ProgressView().controlSize(.large)
                case .empty: Image(systemName: "music.note.list")
                case .error: Image(systemName: "exclamationmark.triangle.fill")
                }
            }
            .font(.jtSubsectionHeader)
            .foregroundStyle(Color.jtAccent)
            Text(title)
                .font(.jtRowTitle)
                .foregroundStyle(Color.jtTextPrimary)
            Text(detail)
                .font(.jtRowSubtitle)
                .foregroundStyle(Color.jtTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(JellytoneTheme.Space.lg)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .background(Color.jtSurface, in: RoundedRectangle(cornerRadius: JellytoneTheme.Radius.groupedCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Now-playing / local UIImage artwork (player chrome)

/// Artwork for the active playback item. Prefers the in-memory image from
/// `PlaybackController`; falls back to the generated gradient placeholder
/// (never a grey box — design-system.md §6).
struct JellytoneLocalArtwork: View {
    let image: UIImage?
    let label: String
    var itemID: String? = nil
    var cornerRadius: CGFloat = JellytoneTheme.Radius.largeArtwork

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                JellytoneTheme.placeholderGradient(
                    hue: JellytoneTheme.placeholderHue(forID: itemID ?? label)
                )
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(image == nil ? "No artwork for \(label)" : "Artwork for \(label)")
    }
}
