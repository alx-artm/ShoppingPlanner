//
//  NewGroupHeaderView.swift
//  Project #2
//
//

import SwiftUI

struct GroupHeaderView: View {
    @Bindable var group: GroupModel
    @State private var showEditSheet: Bool = false
    
    var body: some View {
        HStack{
            Button {
                withAnimation {
                    group.isExpanded.toggle()
                }
            } label: {
                ZStack {
                    // expand & collapse (можно добавить как опцию в меню свернуть и развернуть все группы) подумать об этом
                    Image(systemName: "chevron.down")
                        .opacity(group.isExpanded ? 1 : 0)
                    Image(systemName: "chevron.right")
                        .opacity(group.isExpanded ? 0 : 1)
                }
                .animation(.interactiveSpring, value: group.isExpanded)
                .fontWeight(.bold)
                .imageScale(.medium)
                .foregroundColor(Color(#colorLiteral(red: 0.2549019754, green: 0.2745098174, blue: 0.3019607961, alpha: 1)))
            }
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
                    
                    Text(group.remainingAmount, format: .number)
                }
                .contentShape(Rectangle()) // Опять же, чтобы кликабельной была вся область
                .foregroundStyle(Color.primary) // Стандартный цвет текста
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showEditSheet) {
            GroupEditView(group: group)
        }
    }
}
