//
//  ListInkContrastTests.swift
//  Project2Tests
//
//  M7.5 colour system: the list screen is tinted with the list's ink, and the rest of the
//  app with the Plum accent. Both are text colors ("＋ New Item", "Open in Safari", Undo), so
//  they need ≥ 4.5:1 (WCAG 1.4.3) against every background they are drawn on; the bought
//  checkbox is a fill and needs ≥ 3:1 (WCAG 1.4.11). The assets are resolved with UIKit
//  traits, exactly as the app draws them: light / dark, normal / Increase Contrast, and the
//  base / elevated level (sheets are elevated in dark mode).
//

import Testing
import UIKit
@testable import Project2

@Suite("M7.5 ink and accent contrast")
@MainActor
struct ListInkContrastTests {
    static let textContrast = 4.5
    static let fillContrast = 3.0

    enum Appearance: String, CaseIterable, CustomTestStringConvertible {
        case light, dark, lightHighContrast, darkHighContrast

        var testDescription: String { rawValue }

        var style: UIUserInterfaceStyle {
            switch self {
            case .light, .lightHighContrast: .light
            case .dark, .darkHighContrast: .dark
            }
        }

        var contrast: UIAccessibilityContrast {
            switch self {
            case .light, .dark: .normal
            case .lightHighContrast, .darkHighContrast: .high
            }
        }

        @MainActor func traits(level: UIUserInterfaceLevel) -> UITraitCollection {
            UITraitCollection { traits in
                traits.userInterfaceStyle = style
                traits.accessibilityContrast = contrast
                traits.userInterfaceLevel = level
            }
        }
    }

    /// Screens (plain list, grouped forms) and sheets (elevated) where the tint is drawn.
    static func backgrounds(_ appearance: Appearance) -> [ColorContrast.RGB] {
        let colors: [UIColor] = [.systemBackground, .secondarySystemBackground,
                                 .systemGroupedBackground, .secondarySystemGroupedBackground]
        return [UIUserInterfaceLevel.base, .elevated].flatMap { level in
            colors.map { ColorContrast.RGB($0, traits: appearance.traits(level: level)) }
        }
    }

    static func worstContrast(of color: UIColor, _ appearance: Appearance) -> Double {
        let rgb = ColorContrast.RGB(color, traits: appearance.traits(level: .base))
        return PurchaseBarColors.worstContrast(rgb, against: backgrounds(appearance))
    }

    @Test("Every list ink is readable text (≥ 4.5:1) and a visible fill (≥ 3:1)",
          arguments: FavoriteColor.allCases, Appearance.allCases)
    func inkContrast(color: FavoriteColor, appearance: Appearance) {
        let contrast = Self.worstContrast(of: UIColor(resource: color.inkResource), appearance)
        #expect(contrast >= Self.textContrast, "\(color) text: \(contrast)")
        #expect(contrast >= Self.fillContrast, "\(color) fill: \(contrast)")
    }

    @Test("The ink is the list color made darker in light mode and lighter in dark mode",
          arguments: FavoriteColor.allCases, [Appearance.light, .dark])
    func inkFollowsListColor(color: FavoriteColor, appearance: Appearance) {
        let traits = appearance.traits(level: .base)
        let ink = ColorContrast.relativeLuminance(ColorContrast.RGB(UIColor(resource: color.inkResource), traits: traits))
        let base = ColorContrast.relativeLuminance(ColorContrast.RGB(color.uiColor, traits: traits))
        if appearance.style == .light {
            #expect(ink < base, "\(color)")
        } else {
            #expect(ink >= base - 0.02, "\(color)")
        }
    }

    @Test("Increase Contrast makes the ink stronger", arguments: FavoriteColor.allCases)
    func highContrastIsStronger(color: FavoriteColor) {
        // Both variants against the same (normal-contrast) backgrounds: Increase Contrast
        // changes the backgrounds too.
        let ink = UIColor(resource: color.inkResource)
        for (normal, high) in [(Appearance.light, Appearance.lightHighContrast), (.dark, .darkHighContrast)] {
            let normalInk = ColorContrast.RGB(ink, traits: normal.traits(level: .base))
            let highInk = ColorContrast.RGB(ink, traits: high.traits(level: .base))
            let backgrounds = Self.backgrounds(normal)
            #expect(PurchaseBarColors.worstContrast(highInk, against: backgrounds)
                    >= PurchaseBarColors.worstContrast(normalInk, against: backgrounds), "\(color) \(normal)")
        }
    }

    @Test("The Plum accent is readable text everywhere", arguments: Appearance.allCases)
    func accentContrast(appearance: Appearance) throws {
        let accent = try #require(UIColor(named: "AccentColor"))
        let contrast = Self.worstContrast(of: accent, appearance)
        #expect(contrast >= Self.textContrast, "accent: \(contrast)")
    }
}
