//
//  PurchaseBarColors.swift
//  Project2
//
//  Colors of the purchase bar (spec 04 LD-29): segments in the list color,
//  filled when bought and outlined when not. The outline is a graphic that
//  carries meaning, so it needs ≥ 3:1 contrast with the background
//  (WCAG 1.4.11) in light and dark mode. Some system colors don't have it on
//  white (yellow ≈ 1.6:1, orange, green, mint ≈ 2:1); for those the bar uses
//  the system's own high-contrast variant of the same color, and darkens or
//  lightens it further only if that is still not enough.
//

import SwiftUI
import UIKit

/// WCAG 2 contrast of sRGB colors.
enum ColorContrast {
    /// sRGB components in 0...1.
    struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// The color as it is drawn with `traits` (light / dark, Increase Contrast).
        init(_ color: UIColor, traits: UITraitCollection) {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            self.init(red: Self.clamped(red), green: Self.clamped(green), blue: Self.clamped(blue))
        }

        /// `amount` (0...1) of the way to `other`.
        func mixed(with other: RGB, amount: Double) -> RGB {
            RGB(red: red + (other.red - red) * amount,
                green: green + (other.green - green) * amount,
                blue: blue + (other.blue - blue) * amount)
        }

        var uiColor: UIColor {
            UIColor(red: red, green: green, blue: blue, alpha: 1)
        }

        private static func clamped(_ value: CGFloat) -> Double {
            min(max(Double(value), 0), 1)
        }
    }

    static func relativeLuminance(_ color: RGB) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }

    /// 1...21.
    static func ratio(_ first: RGB, _ second: RGB) -> Double {
        let a = relativeLuminance(first), b = relativeLuminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

enum PurchaseBarColors {
    /// WCAG 1.4.11 for graphical objects (LD-29).
    static let minimumContrast = 3.0

    /// The color of filled and outlined segments of a list with `color`; follows
    /// light / dark mode and Increase Contrast.
    static func segment(_ color: FavoriteColor) -> Color {
        Color(uiColor: UIColor { traits in segmentRGB(color, traits: traits).uiColor })
    }

    /// The dashed squares of items without a price (LD-29: secondary). A plain gray, not
    /// the hierarchical `.secondary`, which inside a tinted view is a faded tint.
    static let unpriced = Color(uiColor: .secondaryLabel)

    /// The list color, or the closest variant of it with ≥ 3:1 against every background
    /// the summary bar can show in `traits`.
    static func segmentRGB(_ color: FavoriteColor, traits: UITraitCollection) -> ColorContrast.RGB {
        let backgrounds = backgrounds(traits: traits)
        func isEnough(_ rgb: ColorContrast.RGB) -> Bool {
            worstContrast(rgb, against: backgrounds) >= minimumContrast
        }

        let base = ColorContrast.RGB(color.uiColor, traits: traits)
        if isEnough(base) { return base }

        // The system's own darker (light mode) / brighter (dark mode) version of the color.
        let highContrast = ColorContrast.RGB(color.uiColor, traits: traits.modifyingTraits {
            $0.accessibilityContrast = .high
        })
        if isEnough(highContrast) { return highContrast }

        // Last resort: step toward black (light) / white (dark) until it is enough.
        let target = traits.userInterfaceStyle == .dark
            ? ColorContrast.RGB(red: 1, green: 1, blue: 1)
            : ColorContrast.RGB(red: 0, green: 0, blue: 0)
        var amount = 0.05
        while amount < 1 {
            let candidate = highContrast.mixed(with: target, amount: amount)
            if isEnough(candidate) { return candidate }
            amount += 0.05
        }
        return target
    }

    /// The glass capsule of the summary bar shows the list under it, which is the plain
    /// background or a grouped / secondary one; the bar must work on both.
    static func backgrounds(traits: UITraitCollection) -> [ColorContrast.RGB] {
        [UIColor.systemBackground, .secondarySystemBackground].map { ColorContrast.RGB($0, traits: traits) }
    }

    static func worstContrast(_ color: ColorContrast.RGB, against backgrounds: [ColorContrast.RGB]) -> Double {
        backgrounds.map { ColorContrast.ratio(color, $0) }.min() ?? 1
    }
}

extension FavoriteColor {
    /// The same system color as `color`, for code that resolves it with UIKit traits.
    var uiColor: UIColor {
        switch self {
        case .gray: .systemGray
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .magenta: .systemPink
        }
    }
}
