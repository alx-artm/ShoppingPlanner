//
//  ListRowView.swift
//  Project #2
//
//

import SwiftUI

struct ListRowView: View {
    @Environment(\.modelContext) var context
    @Bindable var list: ListModel
    @State private var showDeleteConfirmationDialog = false
    @State private var showEditListView: ListModel?
    
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
                    Text(list.iconName)
                }
                
                Text(list.name)
                
                Spacer()
                
                Text(list.remainingAmount, format: .number)
                
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .bold(true)
                    .opacity(0.3)
            }
        }
        .padding(.leading, 4)
        .padding(.vertical, 6)
        .foregroundStyle(.primary)
        
    }
}
