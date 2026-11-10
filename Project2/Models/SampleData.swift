import Foundation
import SwiftData
import SwiftUI

/// Deterministic demo content used by SwiftUI previews and by UI tests
/// (launch argument `-UITests`). QA relies on these exact values; change them
/// together with the UI tests.
///
/// | List (Home order)      | Pinned | Icon         | Color   | Currency | Budget | Groups → items (price × qty)                                                                 | Planned | Bought |
/// |------------------------|--------|--------------|---------|----------|--------|-----------------------------------------------------------------------------------------------|---------|--------|
/// | Alex                   | yes    | airplane (symbol) | blue | USD    | 500    | Vacation: Sunglasses 60, Swimsuit 55, Flip-flops 30 (completed); Birthday: Appetizers 30, BBQ food 55 × 2, Country house rental 85 | 370 | 30 |
/// | Eva                    | no     | 🧸 (emoji)   | magenta | USD      | —      | Toys: Teddy Bear 30, Puss in Boots 25, Scooter 40; Clothes: T-Shirt 20 × 2, Sneakers 45, Jacket (no price) | 180 | 0 |
/// | Victoria               | no     | gift (symbol)| green   | EUR      | 300    | Vacation: Sunglasses 60, Swimsuit 55, Flip-flops 30; Birthday: Appetizers 30, BBQ food 55, Country house rental 85 | 315 (over budget) | 0 |
///
/// Dates are fixed (from 2026-01-01 00:00 UTC), so ordering never depends on the clock.
enum SeedData {
    struct Lists {
        let alex: ListModel
        let eva: ListModel
        let victoria: ListModel
    }

    static let baseDate = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00:00 UTC

    @MainActor
    @discardableResult
    static func populate(_ context: ModelContext) throws -> Lists {
        var clock = baseDate
        func tick() -> Date {
            clock = clock.addingTimeInterval(60)
            return clock
        }

        func makeList(_ name: String, icon: String, kind: ListIconKind, color: FavoriteColor,
                      pinned: Bool, sortIndex: Double, currency: String, budget: Decimal?) -> ListModel {
            let list = ListModel(name: name, iconName: icon, iconKind: kind, color: color, isPinned: pinned,
                                 sortIndex: sortIndex, budget: budget, currencyCode: currency, createdAt: tick())
            context.insert(list)
            return list
        }

        func addGroup(_ name: String, to list: ListModel, sortIndex: Double,
                      items: [(String, Decimal?, Int, Bool)]) {
            let group = GroupModel(name: name, sortIndex: sortIndex, createdAt: tick())
            context.insert(group)
            group.list = list
            for (index, entry) in items.enumerated() {
                let (itemName, price, quantity, isComplete) = entry
                let createdAt = tick()
                let item = ItemModel(
                    name: itemName,
                    quantity: quantity,
                    price: price,
                    isComplete: isComplete,
                    completedAt: isComplete ? createdAt.addingTimeInterval(86_400) : nil,
                    sortIndex: Double(index),
                    createdAt: createdAt
                )
                context.insert(item)
                item.group = group
            }
        }

        let alex = makeList("Alex", icon: "airplane", kind: .symbol, color: .blue,
                            pinned: true, sortIndex: 0, currency: "USD", budget: 500)
        addGroup("Vacation", to: alex, sortIndex: 0, items: [
            ("Sunglasses", 60, 1, false),
            ("Swimsuit", 55, 1, false),
            ("Flip-flops", 30, 1, true),
        ])
        addGroup("Birthday", to: alex, sortIndex: 1, items: [
            ("Appetizers", 30, 1, false),
            ("BBQ food", 55, 2, false),
            ("Country house rental", 85, 1, false),
        ])

        let eva = makeList("Eva", icon: "🧸", kind: .emoji, color: .magenta,
                           pinned: false, sortIndex: 0, currency: "USD", budget: nil)
        addGroup("Toys", to: eva, sortIndex: 0, items: [
            ("Teddy Bear", 30, 1, false),
            ("Puss in Boots", 25, 1, false),
            ("Scooter", 40, 1, false),
        ])
        addGroup("Clothes", to: eva, sortIndex: 1, items: [
            ("T-Shirt", 20, 2, false),
            ("Sneakers", 45, 1, false),
            ("Jacket", nil, 1, false),
        ])

        let victoria = makeList("Victoria", icon: "gift", kind: .symbol, color: .green,
                                pinned: false, sortIndex: 1, currency: "EUR", budget: 300)
        addGroup("Vacation", to: victoria, sortIndex: 0, items: [
            ("Sunglasses", 60, 1, false),
            ("Swimsuit", 55, 1, false),
            ("Flip-flops", 30, 1, false),
        ])
        addGroup("Birthday", to: victoria, sortIndex: 1, items: [
            ("Appetizers", 30, 1, false),
            ("BBQ food", 55, 1, false),
            ("Country house rental", 85, 1, false),
        ])

        try context.save()
        return Lists(alex: alex, eva: eva, victoria: victoria)
    }
}

/// In-memory data for SwiftUI previews.
@MainActor
final class SampleData {
    static let shared = SampleData()

    let modelContainer: ModelContainer
    let store: PlannerStore
    let uiState = LocalUIState.inMemory()

    let evaList: ListModel
    let victoriaList: ListModel
    let alexList: ListModel

    var context: ModelContext {
        modelContainer.mainContext
    }

    private init() {
        do {
            modelContainer = try Persistence.makeContainer(inMemory: true)
            let lists = try SeedData.populate(modelContainer.mainContext)
            evaList = lists.eva
            victoriaList = lists.victoria
            alexList = lists.alex
            store = PlannerStore(context: modelContainer.mainContext)
        } catch {
            // Previews only: there is no user to show an error screen to.
            fatalError("Could not create preview data: \(error)")
        }
    }
}

extension View {
    /// Injects the preview container, store and UI state, like the app does.
    @MainActor
    func sampleDataEnvironment() -> some View {
        modelContainer(SampleData.shared.modelContainer)
            .environment(SampleData.shared.store)
            .environment(SampleData.shared.uiState)
    }
}
