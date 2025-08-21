//
//  GridBoot.swift
//  Project2
//
//  Created by Alex on 10.07.25.
//

import SwiftUI
import SwiftData

struct HomeTab: View {
    
    @Environment(\.modelContext) var context
    
    // Namespace для matchedGeometryEffect. Он создает уникальный идентификатор,
    // который позволяет SwiftUI отслеживать одно и то же представление,
    // когда оно перемещается или меняет свою иерархию/внешний вид.
    @Namespace var listItemAnimation
    
    @Query var lists: [ListModel]
    @State private var newList: ListModel?
    @State private var selectedListForEditing: ListModel?
    @State private var showDeleteConfirmationGrid = false
    @State private var listToDelete: ListModel?
    
    var sortedLists: [ListModel] {
        lists.sorted { $0.name < $1.name }
    }
    
    var favoriteLists: [ListModel] {
        sortedLists
            .filter { $0.isFavorited }
            .sorted { $0.createdAt < $1.createdAt }
    }
    
    var nonFavoriteLists: [ListModel] {
        sortedLists
            .filter { !$0.isFavorited }
            .sorted { $0.createdAt < $1.createdAt }
    }
    
    let colomnsFirstGrid: [GridItem] = [
        GridItem(.flexible(), spacing: nil, alignment: nil),
        GridItem(.flexible(), spacing: nil, alignment: nil),
    ]
    
    var body: some View {
        
        NavigationStack {
            
            ScrollView {
                
                // MARK: - Favorite Lists Grid
                if lists.isEmpty {
                    
                    ContentUnavailableView {
                        Label("No Lists", systemImage: "plus")
                    } description: {
                        Text("Start by adding your first list.\nTap the plus button above.")
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    // центрирование
                    .frame(minHeight: UIScreen.main.bounds.height * 0.6)
                    
                } else {
                    LazyVGrid(columns: colomnsFirstGrid) {
                        
                        ForEach (favoriteLists) { list in
                            FavoriteCardView(list: list)
                                .id(list.id) // Важно: Уникальный ID для элемента
                            // isSource: true, когда это представление является "оригиналом" (избранной карточкой)
                                .matchedGeometryEffect(id: list.id, in: listItemAnimation, isSource: list.isFavorited)
                                .transition(.asymmetric(insertion: .move(edge: .leading), removal: .scale))
                                .contextMenu {
                                    Button("Remove from favorites", systemImage: "star.slash") {
                                        withAnimation(.bouncy){
                                            list.isFavorited = false
                                        }
                                    }
                                    Button("Edit list", systemImage: "pencil") {
                                        selectedListForEditing = list
                                    }
                                    Button("Delete list", systemImage: "trash", role: .destructive) {
                                        listToDelete = list
                                        showDeleteConfirmationGrid = true
                                    }
                                }
                        }
                    }
                    .padding()
                    // Анимация на LazyVGrid для общей компоновки
                    .animation(.bouncy, value: favoriteLists.count)
                }
                
                // MARK: - Non-Favorite Lists
                
                VStack(spacing: 0) {
                    ForEach(nonFavoriteLists) { list in
                        ListRowView(list: list)
                            .id(list.id) // Важно: Уникальный ID для элемента
                        // isSource: false, когда это представление является "целью" (строкой списка)
                        // False, потому что оно становится источником, когда isFavorited == false.
                        // Но здесь оно является *целью* анимации, когда list.isFavorited меняется с true на false
                            .matchedGeometryEffect(id: list.id, in: listItemAnimation, isSource: !list.isFavorited)
                            .animation(nil, value: list.isFavorited)
                            .contextMenu {
                                Button("Add to favorites", systemImage: "star") {
                                    withAnimation(.bouncy){
                                        list.isFavorited = true
                                    }
                                }
                                Button("Edit list", systemImage: "pencil") {
                                    selectedListForEditing = list
                                }
                                Button("Delete list", systemImage: "trash", role: .destructive) {
                                    listToDelete = list
                                    showDeleteConfirmationGrid = true
                                }
                            }
                        Divider()
                            .padding(.leading, 52)
                    }
                }
                .padding(.horizontal)
                // Анимация на VStack для общей компоновки
                .animation(.bouncy, value: nonFavoriteLists.count)
                
            }
            .navigationTitle(Text("Lists"))
            .toolbar {
                Button("New list", systemImage: "plus") {
                    let newList = ListModel()
                    context.insert(newList)
                    self.newList = newList
                }
            }
        }
        .scrollIndicators(.hidden)
        .sheet(item: $newList) { list in
            NavigationStack {
                ListEditView(list: list, isNew: true)
            }
            .interactiveDismissDisabled()
        }
        .sheet(item: $selectedListForEditing) { list in
            NavigationStack {
                ListEditView(list: list, isNew: false)
            }
        }
        .alert("Delete list \(listToDelete?.name ?? "")?", isPresented: $showDeleteConfirmationGrid) {
            Button("Delete", role: .destructive) {
                if let list = listToDelete {
                    context.delete(list)
                }
            }
            Button("Cancel", role: .cancel) {
                listToDelete = nil
            }
        } message: {
            Text("All groups and items in this list will disappear forever.")
        }
    }
}

#Preview {
    HomeTab()
        .modelContainer(SampleData.shared.modelContainer)
}
