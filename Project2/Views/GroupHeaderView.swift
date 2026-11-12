//
//  NewGroupHeaderView.swift
//  Project #2
//
//

import SwiftUI

struct GroupHeaderView: View {
    let group: GroupModel
    @Environment(LocalUIState.self) private var uiState
    @State private var showEditSheet: Bool = false

    var body: some View {
        let isExpanded = uiState.isExpanded(group.uuid)

        HStack{
            Button {
                withAnimation {
                    uiState.setExpanded(!isExpanded, for: group.uuid)
                }
            } label: {
                ZStack {
                    // expand & collapse (можно добавить как опцию в меню свернуть и развернуть все группы) подумать об этом
                    Image(systemName: "chevron.down")
                        .opacity(isExpanded ? 1 : 0)
                    Image(systemName: "chevron.right")
                        .opacity(isExpanded ? 0 : 1)
                }
                .animation(.interactiveSpring, value: isExpanded)
                .fontWeight(.bold)
                .imageScale(.medium)
                // A semantic color: readable in light and dark mode (BUG-09).
                .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("group.expandButton.\(group.name)")
            Button {
                showEditSheet = true
            } label: {
                HStack {
                    Text(group.name)
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)


                    Spacer()

                    // What the number means (BUG-08); M4 switches the header to `planned` (LD-04).
                    Text("To buy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MoneyText(group.summary.toBuy, currencyCode: group.listCurrencyCode)
                        .accessibilityIdentifier("group.total.\(group.name)")
                }
                .contentShape(Rectangle()) // Опять же, чтобы кликабельной была вся область
                .foregroundStyle(Color.primary) // Стандартный цвет текста
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("group.editButton.\(group.name)")
        }
        .sheet(isPresented: $showEditSheet) {
            GroupEditView(group: group)
        }
    }
}
