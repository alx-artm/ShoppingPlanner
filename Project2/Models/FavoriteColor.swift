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
