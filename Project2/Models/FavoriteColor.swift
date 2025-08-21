//
//  FavoriteColor.swift
//  Project2
//
//  Created by Alex on 2.07.25.
//

import SwiftUI

enum FavoriteColor: String, CaseIterable, Codable {
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
            case .gray: return .gray
            case .red: return .red
            case .orange: return .orange
            case .yellow: return .yellow
            case .green: return .green
            case .mint: return .mint
            case .blue: return .blue
            case .purple: return .purple
            case .magenta: return .pink
            }
        }
    }
