//
//  ListTemplateTests.swift
//  Project2Tests
//
//  Spec 03 LI-12 / LI-13: five quick-start templates. Each one fills a draft
//  with a name, icon and color, and creates 3–5 empty groups in order.
//

import Foundation
import SwiftData
import Testing
@testable import Project2

@MainActor
@Suite("ListTemplate", .tags(.listInfo))
struct ListTemplateTests {

    @Test("LI-12 there are exactly five templates in display order")
    func fiveTemplates() {
        #expect(ListTemplate.allCases == [.roomRenovation, .moving, .gifts, .trip, .backToSchool])
        #expect(Set(ListTemplate.allCases.map(\.id)).count == 5)
    }

    @Test("LI-12 every template has a name, a catalog symbol and 3–5 distinct groups",
          arguments: ListTemplate.allCases)
    func templateShape(_ template: ListTemplate) {
        #expect(!template.name.isEmpty)
        #expect(IconCatalog.symbols.contains(template.iconName),
                "\(template.iconName) is not offered in List Info, so it wouldn't show as selected")
        #expect((3...5).contains(template.groupNames.count))
        #expect(Set(template.groupNames).count == template.groupNames.count)
        #expect(template.groupNames.allSatisfy { PlannerStore.normalizedName($0) == $0 })
    }

    struct Expected: CustomTestStringConvertible, Sendable {
        let template: ListTemplate
        let name: String
        let icon: String
        let color: FavoriteColor
        let groups: [String]

        var testDescription: String { name }
    }

    nonisolated static let english: [Expected] = [
        Expected(template: .roomRenovation, name: "Room Renovation", icon: "paintbrush", color: .orange,
                 groups: ["Furniture", "Materials", "Decor", "Lighting"]),
        Expected(template: .moving, name: "Moving", icon: "shippingbox", color: .purple,
                 groups: ["Packing", "Furniture", "Appliances", "Services"]),
        Expected(template: .gifts, name: "Gifts", icon: "gift", color: .red,
                 groups: ["Family", "Friends", "Colleagues"]),
        Expected(template: .trip, name: "Trip", icon: "airplane", color: .mint,
                 groups: ["Tickets", "Accommodation", "Gear", "Food"]),
        Expected(template: .backToSchool, name: "Back to School", icon: "backpack", color: .green,
                 groups: ["Stationery", "Clothes", "Books", "Electronics"]),
    ]

    @Test("LI-12 createList(from: template draft) makes the expected list and empty groups in order",
          .englishUI, arguments: english)
    func createFromTemplate(_ e: Expected) throws {
        let (template, name, icon, color, groups) = (e.template, e.name, e.icon, e.color, e.groups)
        let f = try StoreFixture(currency: "EUR")
        let draft = ListDraft(template: template, currencyCode: "EUR")
        #expect(draft.name == name)
        #expect(draft.canSave)

        let list = f.store.createList(from: draft)

        #expect(list.name == name)
        #expect(list.iconName == icon)
        #expect(list.iconKind == .symbol)
        #expect(list.color == color)
        #expect(list.currencyCode == "EUR", "templates use the main currency (LI-03)")
        #expect(list.budget == nil)
        #expect(list.isPinned == false)
        #expect(list.sortedGroups.map(\.name) == groups)
        #expect(list.allItems.isEmpty, "template groups are empty")
        #expect(try f.count(GroupModel.self) == groups.count)
    }

    @Test("LI-13 after creation template names are plain user strings: they can be renamed",
          arguments: ListTemplate.allCases)
    func editableAfterCreation(_ template: ListTemplate) throws {
        let f = try StoreFixture()
        let list = f.store.createList(from: ListDraft(template: template, currencyCode: "USD"))
        let group = try #require(list.sortedGroups.first)

        f.store.renameList(list, to: "Mine")
        f.store.renameGroup(group, to: "First")

        #expect(list.name == "Mine")
        #expect(list.sortedGroups.first?.name == "First")
    }

    @Test("LI-12 the template's values can be changed in List Info before ✓")
    func draftIsEditable() throws {
        let f = try StoreFixture()
        var draft = ListDraft(template: .trip, currencyCode: "USD")
        draft.name = "Rome"
        draft.color = .blue
        draft.groupNames.removeLast()

        let list = f.store.createList(from: draft)

        #expect(list.name == "Rome")
        #expect(list.color == .blue)
        #expect(list.sortedGroups.count == ListTemplate.trip.groupNames.count - 1)
    }
}
