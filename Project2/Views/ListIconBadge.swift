//
//  ListIconBadge.swift
//  Project2
//

import SwiftUI

/// The list icon on a circle of the list color: an SF Symbol or an emoji.
///
/// The color appears only here (and in thin progress bars), never as a large
/// background, so tiles and rows keep the system backgrounds in both themes.
/// Decorative for VoiceOver: the tile / row label already names the list.
struct ListIconBadge: View {
    let iconName: String
    let iconKind: ListIconKind
    let color: FavoriteColor
    let diameter: CGFloat

    init(iconName: String, iconKind: ListIconKind, color: FavoriteColor, diameter: CGFloat) {
        self.iconName = iconName
        self.iconKind = iconKind
        self.color = color
        self.diameter = diameter
    }

    init(list: ListModel, diameter: CGFloat) {
        self.init(iconName: list.iconName, iconKind: list.iconKind, color: list.color, diameter: diameter)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.color.gradient)
            switch iconKind {
            case .symbol:
                // A white glyph on a saturated fill reads well in light and dark mode.
                Image(systemName: iconName)
                    .font(.system(size: diameter * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            case .emoji:
                Text(verbatim: iconName)
                    .font(.system(size: diameter * 0.52))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        ListIconBadge(iconName: "cart", iconKind: .symbol, color: .blue, diameter: 32)
        ListIconBadge(iconName: "🧸", iconKind: .emoji, color: .magenta, diameter: 44)
        ListIconBadge(iconName: "bed.double", iconKind: .symbol, color: .orange, diameter: 72)
    }
}
