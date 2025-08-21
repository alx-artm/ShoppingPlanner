//
//  NewListView.swift
//  Project #2
//
//  Created by Alex on 15.05.25.
//

import SwiftUI

struct ListViewInside: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var list: ListModel
    
    @State private var showDeleteConfirmation: Bool = false
    @State private var newItem: ItemModel?
    @State private var newGroup: GroupModel?
    @State private var showEditList: Bool = false
    
    var body: some View {
        
        List {
            if list.groups.isEmpty {
                
                ContentUnavailableView {
                    Label("No Groups", systemImage: "folder.badge.plus")
                } description: {
                    Text("Start by adding your first group.\nTap the folder icon above.")
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(minHeight: UIScreen.main.bounds.height * 0.6) // центрирование
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            
            else {
                
                ForEach($list.groups) { $group in
                    
                    Section(isExpanded: $group.isExpanded) {
                            if group.isExpanded {
                                ForEach(list.showCompleted ? group.sortedItems : group.itemsNotComplete) { item in
                                    ItemRowView(item: item)
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        let item = group.sortedItems[index]
                                        context.delete(item)
                                    }
                                    try? context.save()
                                }
                                
                                //MARK: КНОПКА ДОБАВЛЕНИЯ АЙТЕМОВ ДЛЯ ВСЕХ ГРУПП
                                Button {
                                    
                                    let newItem = ItemModel(name: "")
                                    group.items.append(newItem)
                                    try! context.save()
                                    self.newItem = newItem
                                    
                                } label: {
                                    HStack {
                                        Image(systemName: "plus")
                                            .font(.title2)
                                            .frame(width: 28)
                                        Text("Add new item...")
                                    }
                                    .opacity(0.4)
                                }
                            }
                        } header: {
                            GroupHeaderView(group: group)
                        }
                    
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 32 }
            }
            
            
            Group {
                if !list.totalAmount.isZero {
                    Section {} header: {
                        HStack {
                            Text("Total")
                            Spacer()
                            Text(list.remainingAmount, format: .number)
                        }
                        .font(.title2)
                        .bold()
                        .headerProminence(.standard)
                    }
                }
            }
        }
        
        .headerProminence(.increased)
        
        .toolbar {
            Button("Add group", systemImage: "folder.badge.plus") {
                let newGroup = GroupModel(name: "")
                list.groups.append(newGroup)
                self.newGroup = newGroup
            }
            
            Menu {
                Button {
                    showEditList = true
                } label: {
                    Label("Edit list", systemImage: "pencil")
                }
                
                Button {
                    withAnimation {
                        list.showCompleted.toggle()
                    }
                } label: {
                    Label("\(list.showCompleted ? "Hide" : "Show") completed", systemImage: list.showCompleted ? "eye.slash" : "eye")
                }
                
                // по нажатию на эту кнопку будет появляться .alert, см. код ниже
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete list", systemImage: "trash")
                }
                
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .navigationTitle(list.name)
        .listStyle(.plain)
        // МОЖНО СДЕЛАТЬ ТАК - будет вшитая фикша листа со скрывабщейся секцией, но фон листа будет серым
        // .listStyle(.sidebar)
        .navigationBarTitleDisplayMode(.inline)
        
        .sheet(item: $newItem) { item in
            NavigationStack {
                ItemView(item: item, isNew: true)
            }
            .interactiveDismissDisabled()
        }
        
        .sheet(item: $newGroup) { group in
            NavigationStack {
                GroupEditView(group: group, isNew: true)
            }
            .interactiveDismissDisabled()
        }
        
        .sheet(isPresented: $showEditList) {
            NavigationStack {
                ListEditView(list: list)
            }
        }
        
        // если алерт = true, то появляется сообщение с кнопками
        .alert("Delete list?\nAll groups and items in this list will disappear forever.", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                context.delete(list)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

