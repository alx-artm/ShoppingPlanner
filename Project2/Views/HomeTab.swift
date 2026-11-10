//
//  GridBoot.swift
//  Project2
//
//  Created by Alex on 10.07.25.
//

import SwiftUI
import SwiftData

struct HomeTab: View {

    @Environment(PlannerStore.self) private var store

    // Namespace для matchedGeometryEffect. Он создает уникальный идентификатор,
    // который позволяет SwiftUI отслеживать одно и то же представление,
    // когда оно перемещается или меняет свою иерархию/внешний вид.
    @Namespace var listItemAnimation

    @Query var lists: [ListModel]
    /// Not inserted into the context until the user taps Done in `ListEditView`.
    @State private var draftList: ListModel?
    @State private var selectedListForEditing: ListModel?
    @State private var showDeleteConfirmationGrid = false
    @State private var listToDelete: ListModel?

    var pinnedLists: [ListModel] {
        PlannerOrdering.sortedLists(lists.filter(\.isPinned))
    }

    var unpinnedLists: [ListModel] {
        PlannerOrdering.sortedLists(lists.filter { !$0.isPinned })
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
                    .containerRelativeFrame(.vertical) { length, _ in length * 0.6 }
                    .accessibilityIdentifier("home.emptyState")

                } else {
                    LazyVGrid(columns: colomnsFirstGrid) {

                        ForEach (pinnedLists) { list in
                            FavoriteCardView(list: list)
                                .id(list.id) // Важно: Уникальный ID для элемента
                            // isSource: true, когда это представление является "оригиналом" (избранной карточкой)
                                .matchedGeometryEffect(id: list.id, in: listItemAnimation, isSource: list.isPinned)
                                .transition(.asymmetric(insertion: .move(edge: .leading), removal: .scale))
                                .contextMenu {
                                    Button("Remove from favorites", systemImage: "star.slash") {
                                        withAnimation(.bouncy){
                                            store.togglePin(list)
                                        }
                                    }
                                    .accessibilityIdentifier("home.menu.togglePin")
                                    listMenuCommonButtons(for: list)
                                }
                        }
                    }
                    .padding()
                    // Анимация на LazyVGrid для общей компоновки
                    .animation(.bouncy, value: pinnedLists.count)
                }

                // MARK: - Non-Favorite Lists

                VStack(spacing: 0) {
                    ForEach(unpinnedLists) { list in
                        ListRowView(list: list)
                            .id(list.id) // Важно: Уникальный ID для элемента
                            .matchedGeometryEffect(id: list.id, in: listItemAnimation, isSource: !list.isPinned)
                            .animation(nil, value: list.isPinned)
                            .contextMenu {
                                Button("Add to favorites", systemImage: "star") {
                                    withAnimation(.bouncy){
                                        store.togglePin(list)
                                    }
                                }
                                .accessibilityIdentifier("home.menu.togglePin")
                                listMenuCommonButtons(for: list)
                            }
                        Divider()
                            .padding(.leading, 52)
                    }
                }
                .padding(.horizontal)
                // Анимация на VStack для общей компоновки
                .animation(.bouncy, value: unpinnedLists.count)

            }
            .navigationTitle(Text("Lists"))
            .toolbar {
                Button("New list", systemImage: "plus") {
                    draftList = ListModel(currencyCode: store.defaultCurrencyCode)
                }
                .accessibilityIdentifier("home.newListButton")
            }
        }
        .scrollIndicators(.hidden)
        .sheet(item: $draftList) { list in
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
                    // The list is not open on another screen here, so it can be deleted right away.
                    store.deleteList(list)
                }
                listToDelete = nil
            }
            .accessibilityIdentifier("home.deleteAlert.confirmButton")
            Button("Cancel", role: .cancel) {
                listToDelete = nil
            }
            .accessibilityIdentifier("home.deleteAlert.cancelButton")
        } message: {
            Text("All groups and items in this list will disappear forever.")
        }
    }

    @ViewBuilder
    private func listMenuCommonButtons(for list: ListModel) -> some View {
        Button("Edit list", systemImage: "pencil") {
            selectedListForEditing = list
        }
        .accessibilityIdentifier("home.menu.edit")
        Button("Delete list", systemImage: "trash", role: .destructive) {
            listToDelete = list
            showDeleteConfirmationGrid = true
        }
        .accessibilityIdentifier("home.menu.delete")
    }
}

#Preview {
    HomeTab()
        .sampleDataEnvironment()
}
