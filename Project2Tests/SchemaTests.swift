//
//  SchemaTests.swift
//  Project2Tests
//
//  CloudKit-compatibility rules of SchemaV1 (spec 01, DM-01...DM-05, DM-09),
//  checked through SwiftData's Schema introspection.
//

import Foundation
import SwiftData
import Testing
@testable import Project2

@Suite("SchemaV1", .tags(.schema))
struct SchemaTests {

    private let schema = Persistence.schema

    @Test("DM-01 the schema contains exactly ListModel, GroupModel, ItemModel")
    func entities() {
        #expect(Set(schema.entities.map(\.name)) == ["ListModel", "GroupModel", "ItemModel"])
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(PlannerMigrationPlan.schemas.count == 1)
    }

    @Test("DM-02 no unique attributes or uniqueness constraints", .bug(id: "BUG-15"))
    func noUniqueConstraints() {
        for entity in schema.entities {
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name)")
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) is unique")
            }
        }
    }

    @Test("DM-02 no relationship uses the .deny delete rule")
    func noDenyRule() {
        for entity in schema.entities {
            for relationship in entity.relationships {
                #expect(relationship.deleteRule != .deny, "\(entity.name).\(relationship.name)")
            }
        }
    }

    @Test("DM-04 every relationship is optional and has an inverse")
    func relationshipsOptionalWithInverse() {
        let relationships = schema.entities.flatMap { entity in
            entity.relationships.map { (entity.name, $0) }
        }
        #expect(relationships.count == 4) // list.groups, group.list, group.items, item.group
        for (entity, relationship) in relationships {
            #expect(relationship.isOptional, "\(entity).\(relationship.name) must be optional")
            #expect(relationship.inverseName != nil || relationship.inverseKeyPath != nil,
                    "\(entity).\(relationship.name) has no inverse")
        }
    }

    @Test("DM-08 parent → child relationships cascade")
    func cascadeRules() throws {
        func rule(_ entity: String, _ name: String) throws -> Schema.Relationship.DeleteRule {
            let e = try #require(schema.entities.first { $0.name == entity })
            return try #require(e.relationships.first { $0.name == name }).deleteRule
        }
        #expect(try rule("ListModel", "groups") == .cascade)
        #expect(try rule("GroupModel", "items") == .cascade)
    }

    @Test("DM-03 every attribute is optional or has a default: models build with init()")
    @MainActor
    func defaultInit() {
        let list = ListModel()
        #expect(list.name == "")
        #expect(list.iconKind == .symbol)
        #expect(list.color == .blue)
        #expect(list.budget == nil)
        #expect(list.currencyCode == "USD")

        let group = GroupModel()
        #expect(group.sortIndex == 0)
        #expect(group.budget == nil)

        let item = ItemModel()
        #expect(item.quantity == 1)
        #expect(item.price == nil)
        #expect(item.isComplete == false)
        #expect(item.completedAt == nil)
        #expect(item.lineTotal == nil)
    }

    @Test("DM-05 an in-memory container opens without CloudKit; containers are isolated")
    @MainActor
    func inMemoryContainers() throws {
        #expect(SyncConfig.isCloudKitEnabled == false, "CloudKit stays off until M6")

        let first = try Persistence.makeContainer(inMemory: true)
        let second = try Persistence.makeContainer(inMemory: true)
        let inMemoryOnly = first.configurations.allSatisfy { $0.isStoredInMemoryOnly }
        #expect(inMemoryOnly)

        first.mainContext.insert(ListModel(name: "Only in first"))
        try first.mainContext.save()

        #expect(try first.mainContext.fetchCount(FetchDescriptor<ListModel>()) == 1)
        #expect(try second.mainContext.fetchCount(FetchDescriptor<ListModel>()) == 0)
    }

    @Test("DM-09 unknown raw values fall back to the defaults", arguments: ["", "neon", "SYMBOL"])
    @MainActor
    func unknownRawValues(raw: String) {
        let list = ListModel()
        list.iconKindRaw = raw
        list.colorRaw = raw
        #expect(list.iconKind == .symbol)
        #expect(list.color == .blue)
    }
}
