//
//  ListRowView.swift
//  Project #2
//
//

import SwiftUI

struct ListRowView: View {
    let list: ListModel
    
    var body: some View {
        NavigationLink {
            ListViewInside(list: list)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    // ТАКОЕ НАЛОЖЕНИЕ СОХРАНЯЕТ ЦВЕТА .quaternary одинаковым в dark и light модах
                    Circle()
                        .fill(.white)
                        .frame(width: 36)
                    Circle()
                        .fill(list.color.color.quaternary)
                        .frame(width: 36)
                    ListIconView(list: list)
                }
                
                Text(list.name)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 0) {
                    MoneyText(list.summary.toBuy, currencyCode: list.currencyCode)
                        .accessibilityIdentifier("home.listRow.toBuy.\(list.name)")
                    // What the number means (BUG-08).
                    Text("To buy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .bold(true)
                    .opacity(0.3)
            }
        }
        .padding(.leading, 4)
        .padding(.vertical, 6)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("home.listRow.\(list.name)")
    }
}
