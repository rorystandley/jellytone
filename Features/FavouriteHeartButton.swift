import SwiftUI

/// Reusable like/favourite toggle for songs, albums, and artists. Reads and
/// writes the shared AppModel favourite registry, so one tap optimistically
/// flips the heart and durably enqueues the server write. Themed per
/// docs/design/design-system.md.
struct FavouriteHeartButton: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let itemID: String
    var font: Font = .jtSubsectionHeader
    var identifierPrefix: String = "favourite"

    private var isFavourite: Bool { model.isFavourite(itemID) }

    var body: some View {
        Button {
            model.toggleFavourite(id: itemID)
        } label: {
            Image(systemName: isFavourite ? "heart.fill" : "heart")
                .font(font)
                .foregroundStyle(isFavourite ? Color.jtAccent : Color.jtTextPrimary)
                .frame(width: DetailMetrics.secondaryActionSide, height: DetailMetrics.secondaryActionSide)
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isFavourite)
        }
        .buttonStyle(.jtPressScale(JellytoneTheme.Motion.pressScaleSmall))
        .accessibilityIdentifier("\(identifierPrefix)-favourite-toggle")
        .accessibilityLabel(isFavourite ? "Remove from favourites" : "Add to favourites")
        .accessibilityAddTraits(isFavourite ? .isSelected : [])
    }
}
