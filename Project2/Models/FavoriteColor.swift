//
//  FavoriteColor.swift
//  Project2
//
//  Created by Alex on 2.07.25.
//

import SwiftUI

/// The color of a list. Every case maps to a system color, which adapts to
/// light/dark mode and Increase Contrast by itself (BUG-09).
enum FavoriteColor: String, CaseIterable, Codable, Sendable {
    case gray
    case red
    case orange
    case yellow
    case green
    case mint
    case blue
    case purple
    case magenta

    var color: Color {
        switch self {
        case .gray: .gray
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .blue: .blue
        case .purple: .purple
        case .magenta: .pink
        }
    }

    /// The list color for text and controls on the list screen (M7.5): a darker (light mode) /
    /// lighter (dark mode) shade of `color` with ≥ 4.5:1 against the backgrounds, so tinted
    /// text and the bought checkbox stay readable. Icons and the purchase bar keep `color`.
    var ink: Color { Color(inkResource) }

    /// The asset of `ink`: light, dark and Increase Contrast variants (`Assets/ListInk`).
    var inkResource: ColorResource {
        switch self {
        case .gray: .inkGray
        case .red: .inkRed
        case .orange: .inkOrange
        case .yellow: .inkYellow
        case .green: .inkGreen
        case .mint: .inkMint
        case .blue: .inkBlue
        case .purple: .inkPurple
        case .magenta: .inkMagenta
        }
    }

    /// Name read by VoiceOver for the color circles of List Info (LI-04).
    var title: LocalizedStringResource {
        switch self {
        case .gray: "Gray"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .mint: "Mint"
        case .blue: "Blue"
        case .purple: "Purple"
        case .magenta: "Pink"
        }
    }
}
