import Foundation
import SwiftData

@MainActor
class SampleData {
    static let shared = SampleData()
    
    let modelContainer: ModelContainer
    
    var context: ModelContext {
        modelContainer.mainContext
    }
    
    // Добавляем переменные для списков
    var evaList: ListModel
    var victoriaList: ListModel
    var alexList: ListModel
    
    private init() {
        let schema = Schema([
            ItemModel.self,
            GroupModel.self,
            ListModel.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Создаём списки ДО вставки в context
            evaList = ListModel(
                name: "Eva",
                groups: [
                    GroupModel(
                        name: "Toys",
                        items: [
                            ItemModel(name: "Taddy Bear", price: 30),
                            ItemModel(name: "Puss in Boots", price: 25),
                            ItemModel(name: "Scooter", price: 40),
                        ]),
                    GroupModel(
                        name: "Clothes",
                        items: [
                            ItemModel(name: "T-Shirt", price: 20),
                            ItemModel(name: "Sneakers", price: 45),
                            ItemModel(name: "Jacket", price: 45),
                        ]),
                ]
            )
            
            victoriaList = ListModel(
                name: "Victoria Vrubleusckaya",
                groups: [
                    GroupModel(
                        name: "Vacation",
                        items: [
                            ItemModel(name: "Sunglasses", price: 60),
                            ItemModel(name: "Swimsuit", price: 55),
                            ItemModel(name: "Flip-flops", price: 30),
                        ]),
                    GroupModel(
                        name: "Birthday",
                        items: [
                            ItemModel(name: "Appetizers", price: 30),
                            ItemModel(name: "BBQ food", price: 55),
                            ItemModel(name: "Сountry house rental", price: 85),
                        ]),
                ]
            )
            
            alexList = ListModel(
                name: "Alex",
                isFavorited: true,
                groups: [
                    GroupModel(
                        name: "Vacation",
                        items: [
                            ItemModel(name: "Sunglasses", price: 60),
                            ItemModel(name: "Swimsuit", price: 55),
                            ItemModel(name: "Flip-flops", price: 30),
                        ]),
                    GroupModel(
                        name: "Birthday",
                        items: [
                            ItemModel(name: "Appetizers", price: 30),
                            ItemModel(name: "BBQ food", price: 55),
                            ItemModel(name: "Сountry house rental", price: 85),
                        ]),
                ]
            )

            
            context.insert(evaList)
            context.insert(victoriaList)
            context.insert(alexList)
            
            try context.save()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
