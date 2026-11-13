//
//  ItemDraftTests.swift
//  Project2Tests
//
//  Spec 05 item details: the draft (ID-01...ID-05), the link rules (ID-06,
//  LP-08 chip) and `PlannerStore.updateItem` (one save, move to group, ID-08).
//

import Foundation
import Testing
@testable import Project2

@Suite("ItemDraft", .tags(.validation))
@MainActor
struct ItemDraftTests {

    // MARK: - Draft

    @Test("ID-01 a draft of an item copies every editable value")
    func copiesItem() throws {
        let fixture = try StoreFixture()
        let (_, group) = fixture.makeGroup()
        let item = fixture.addItem("Sofa", to: group, quantity: 2, price: dec("450"))
        item.urlString = "ikea.com"
        item.notes = "grey"

        let draft = ItemDraft(item: item)
        #expect(draft.name == "Sofa")
        #expect(draft.price == dec("450"))
        #expect(draft.quantity == 2)
        #expect(draft.urlString == "ikea.com")
        #expect(draft.notes == "grey")
        #expect(draft.groupID == group.uuid)
        #expect(draft == ItemDraft(item: item), "unchanged draft = no changes")
    }

    @Test("ID-02 ✓ needs a name that isn't blank after trimming",
          arguments: [("", false), ("   ", false), ("\n", false), (" Sofa ", true)] as [(String, Bool)])
    func nameValidation(name: String, valid: Bool) {
        var draft = ItemDraft()
        draft.name = name
        #expect(draft.canSave == valid)
    }

    @Test("ID-03 no price is valid, a negative price is not")
    func priceValidation() {
        var draft = ItemDraft()
        draft.name = "Sofa"
        #expect(draft.canSave)
        draft.price = -1
        #expect(!draft.canSave)
        draft.price = 0
        #expect(draft.canSave)
    }

    @Test("ID-04 total = price × quantity; nil without a price")
    func total() {
        var draft = ItemDraft()
        #expect(draft.lineTotal(listCurrencyCode: "USD") == nil)
        draft.price = dec("12.5")
        draft.quantity = 2
        #expect(draft.lineTotal(listCurrencyCode: "USD") == 25)
    }

    @Test("ID-05 the quantity field clamps to 1...999; empty keeps the old value",
          arguments: [("0", 1), ("5000", 999), ("7", 7), ("999", 999), ("1", 1),
                      ("99999999999999999999999", 999), ("1 2", 12)] as [(String, Int)])
    func quantityFromText(text: String, expected: Int) {
        #expect(ItemDraft.quantity(from: text) == expected)
    }

    @Test("ID-05 an empty quantity field is not a value yet", arguments: ["", " ", "abc"])
    func quantityEmpty(text: String) {
        #expect(ItemDraft.quantity(from: text) == nil)
    }

    // MARK: - Link

    @Test("A link without a scheme opens as https; blank or non-web text has no URL",
          arguments: [
            ("ikea.com/sofa", "https://ikea.com/sofa"),
            ("  https://www.ikea.com  ", "https://www.ikea.com"),
            ("http://shop.example.org/a?b=1", "http://shop.example.org/a?b=1"),
          ] as [(String, String)])
    func linkURL(text: String, expected: String) {
        #expect(ItemLink.url(from: text)?.absoluteString == expected)
    }

    @Test("No URL for text that isn't a web address", arguments: ["", "  ", "sofa", "ftp://x.com", "a b.com", "mailto:a@b.com"])
    func notALink(text: String) {
        #expect(ItemLink.url(from: text) == nil)
    }

    @Test("LP-08 the chip shows the host without www.",
          arguments: [("https://www.ikea.com/sofa", "ikea.com"), ("Amazon.DE/dp/1", "amazon.de"),
                      ("shop.example.org", "shop.example.org")] as [(String, String)])
    func displayHost(text: String, expected: String) {
        #expect(ItemLink.displayHost(of: text) == expected)
    }

    // MARK: - PlannerStore.updateItem

    @Test("ID-01 ✓ applies every value; the name is trimmed, the link too")
    func updateItem() throws {
        let fixture = try StoreFixture()
        let (_, group) = fixture.makeGroup()
        let item = fixture.addItem("Sofa", to: group)

        var draft = ItemDraft(item: item)
        draft.name = "  Big sofa "
        draft.price = dec("450.5")
        draft.quantity = 2
        draft.urlString = " ikea.com "
        draft.notes = "grey"
        fixture.store.updateItem(item, with: draft)

        #expect(item.name == "Big sofa")
        #expect(item.price == dec("450.5"))
        #expect(item.quantity == 2)
        #expect(item.urlString == "ikea.com")
        #expect(item.notes == "grey")
        #expect(item.lineTotal == dec("901"))
        #expect(!fixture.context.hasChanges, "saved")
    }

    @Test("DM-12...DM-14 invalid values don't overwrite: blank name, negative price; quantity is clamped")
    func updateItemValidation() throws {
        let fixture = try StoreFixture()
        let (_, group) = fixture.makeGroup()
        let item = fixture.addItem("Sofa", to: group, price: 10)

        var draft = ItemDraft(item: item)
        draft.name = "  "
        draft.price = -5
        draft.quantity = 5000
        fixture.store.updateItem(item, with: draft)

        #expect(item.name == "Sofa")
        #expect(item.price == 10)
        #expect(item.quantity == 999)
    }

    @Test("ID-03 clearing the price saves 'no price'")
    func updateItemClearsPrice() throws {
        let fixture = try StoreFixture()
        let (_, group) = fixture.makeGroup()
        let item = fixture.addItem("Sofa", to: group, price: 10)

        var draft = ItemDraft(item: item)
        draft.price = nil
        fixture.store.updateItem(item, with: draft)
        #expect(item.price == nil)
    }

    @Test("ID-08 another group moves the item to the end of that group's not-completed items")
    func updateItemMovesGroup() throws {
        let fixture = try StoreFixture()
        let (list, kitchen) = fixture.makeGroup(groupName: "Kitchen")
        let bath = fixture.store.createGroup(name: "Bath", in: list)
        let towel = fixture.addItem("Towel", to: bath)
        let done = fixture.addItem("Soap", to: bath)
        fixture.store.toggleComplete(done)
        let sofa = fixture.addItem("Sofa", to: kitchen)

        var draft = ItemDraft(item: sofa)
        draft.groupID = bath.uuid
        fixture.store.updateItem(sofa, with: draft)

        #expect(sofa.group === bath)
        #expect(bath.sortedItems.map(\.name) == ["Towel", "Sofa", "Soap"])
        #expect(kitchen.sortedItems.isEmpty)
        _ = towel
    }

    @Test("A group of another list is ignored")
    func updateItemIgnoresForeignGroup() throws {
        let fixture = try StoreFixture()
        let (_, group) = fixture.makeGroup()
        let (_, other) = fixture.makeGroup(listName: "Other")
        let item = fixture.addItem("Sofa", to: group)

        var draft = ItemDraft(item: item)
        draft.groupID = other.uuid
        fixture.store.updateItem(item, with: draft)
        #expect(item.group === group)
    }

    @Test("A new item from a draft goes to the end of the group")
    func addFromDraft() throws {
        let fixture = try StoreFixture()
        let (_, group) = fixture.makeGroup()
        fixture.addItem("First", to: group)

        var draft = ItemDraft(groupID: group.uuid)
        draft.name = " Lamp "
        draft.price = 60
        draft.quantity = 2
        let item = try #require(fixture.store.addItem(from: draft, to: group))
        #expect(item.name == "Lamp")
        #expect(item.lineTotal == 120)
        #expect(group.sortedItems.map(\.name) == ["First", "Lamp"])
    }
}
