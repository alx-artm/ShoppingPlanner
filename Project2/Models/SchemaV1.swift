//
//  SchemaV1.swift
//  Project2
//
//  The first versioned SwiftData schema (spec 01, DM-01...DM-04).
//
//  Rules every model in this schema follows, so it can later be synced
//  with CloudKit (M6) without a breaking change:
//  - no `@Attribute(.unique)` / `#Unique`, no `.deny` delete rule;
//  - every stored attribute has a default value in its declaration or is optional;
//  - every relationship is optional and declares its inverse.
//
//  Future changes go into `SchemaV2` (copy of the models + changes) plus a
//  `MigrationStage` in `PlannerMigrationPlan`. Never edit a shipped schema
//  version in place.
//

import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ListModel.self, GroupModel.self, ItemModel.self]
    }
}

/// Ordered list of schema versions and how to migrate between them.
/// Only one version exists today, so there are no stages yet.
enum PlannerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

// The rest of the app always talks about "the current" models. When SchemaV2
// appears, only these aliases move to the new version.
typealias ListModel = SchemaV1.ListModel
typealias GroupModel = SchemaV1.GroupModel
typealias ItemModel = SchemaV1.ItemModel
