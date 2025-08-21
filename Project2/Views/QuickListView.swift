//
//  QuickListViewNew.swift
//  Project #2
//
//  Created by Alex on 11.06.25.
//

import SwiftUI
import SwiftData

struct QuickListView: View {
    @Query var quickItems: [QuickItemModel]
    @Environment(\.modelContext) private var context
    
    @State private var newItemName = ""
    @FocusState private var isNewItemFocused: Bool
    
    @State private var showClearConfirmation = false
    
    // то, что активно (не куплено) — отсортировано по дате создания (старое выше)
    private var activeItems: [QuickItemModel] {
        quickItems
            .filter { !$0.isComplete }
            .sorted { $0.createdAt < $1.createdAt }
    }
    
    // то, что куплено раньше всего - в самом конце, а то, что недавно - в начале
    private var completedItems: [QuickItemModel] {
        let items = quickItems.filter { $0.isComplete }
        return items.sorted {
            let lhs = $0.completedAt ?? .distantPast
            let rhs = $1.completedAt ?? .distantPast
            return lhs > rhs
        }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            NavigationStack {
                List {
                    Section("Active") {
                        ForEach(activeItems) { item in
                            QuickItemRowView(item: item)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let item = activeItems[index]
                                context.delete(item)
                            }
                            try? context.save()
                        }
                        
                        
                        HStack {
                            Image(systemName: "circle")
                                .font(.title2)
                                .frame(width: 28)
                                .foregroundColor(.accent)
                            
                            TextField("Add new item...", text: $newItemName)
                                .focused($isNewItemFocused)
                                .onSubmit {
                                    addNewItem()
                                }
                        }
                        
                        //MARK: - КАСТОМНАЯ ДЛИНА СЕПАРАТОРА (ТУТ ДЛЯ BLUE)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 32 }
                        .id("NewItemInput")
                    }
                    
                    if !completedItems.isEmpty {
                        Section("Done") {
                            ForEach(completedItems) { item in
                                QuickItemRowView(item: item)
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    let item = completedItems[index]
                                    context.delete(item)
                                }
                                try? context.save()
                            }
                        }
                    }
                }
                
                .navigationTitle("Quick List")
                .listStyle(.plain)
                .headerProminence(.increased)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem {
                        Button(action: {
                            showClearConfirmation = true
                        }) {
                            Label("Clear list", systemImage: "arrow.trianglehead.counterclockwise")
                            
                        }
                        .alert("Clear entire list?", isPresented: $showClearConfirmation) {
                            Button("Clear", role: .destructive) {
                                clearList()
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                    }
                    
                    ToolbarItem {
                        Button("Add item", systemImage: "plus") {
                            DispatchQueue.main.async {
                                isNewItemFocused = true
                                withAnimation {
                                    proxy.scrollTo("NewItemInput", anchor: .center)
                                }
                            }
                        }
                    } 
                }
            }
        }
    }
    
    private func clearList() {
        for item in quickItems {
            context.delete(item)
        }
        try? context.save()
    }
    
    private func addNewItem() {
        let trimmed = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let newItem = QuickItemModel(name: trimmed, quantity: 1, isComplete: false)
        context.insert(newItem)
        try? context.save()
        
        newItemName = ""
        isNewItemFocused = true // снова фокус на следующий ввод
    }
}

// MARK: - ПРЕВЬЮ
#Preview {
    QuickListView()
        .modelContainer(SampleData.shared.modelContainer)
}

#Preview {
    QuickListView()
        .modelContainer(for: QuickItemModel.self, inMemory: true)
}
