//
//  ListIconView.swift
//  Project2
//

import SwiftUI

/// Renders `ListModel.iconName` as an SF Symbol or an emoji, depending on `iconKind`.
struct ListIconView: View {
    let list: ListModel

    var body: some View {
        switch list.iconKind {
        case .symbol:
            Image(systemName: list.iconName)
                .foregroundStyle(list.color.color)
        case .emoji:
            Text(verbatim: list.iconName)
        }
    }
}
