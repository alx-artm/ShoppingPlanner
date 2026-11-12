//
//  ListTemplate.swift
//  Project2
//
//  Quick-start templates (spec 03 LI-12, LI-13). A template only fills a
//  `ListDraft`: name, icon, color and a few empty groups. Names are localized
//  at creation time; after that they are ordinary user strings.
//

import Foundation

enum ListTemplate: String, CaseIterable, Identifiable, Sendable {
    case roomRenovation
    case moving
    case gifts
    case trip
    case backToSchool

    var id: String { rawValue }

    var name: String {
        switch self {
        case .roomRenovation: String(localized: "Room Renovation")
        case .moving: String(localized: "Moving")
        case .gifts: String(localized: "Gifts")
        case .trip: String(localized: "Trip")
        case .backToSchool: String(localized: "Back to School")
        }
    }

    var iconName: String {
        switch self {
        case .roomRenovation: "paintbrush"
        case .moving: "shippingbox"
        case .gifts: "gift"
        case .trip: "airplane"
        case .backToSchool: "backpack"
        }
    }

    var color: FavoriteColor {
        switch self {
        case .roomRenovation: .orange
        case .moving: .purple
        case .gifts: .red
        case .trip: .mint
        case .backToSchool: .green
        }
    }

    /// 3–5 empty groups, in display order.
    var groupNames: [String] {
        switch self {
        case .roomRenovation:
            [String(localized: "Furniture"), String(localized: "Materials"),
             String(localized: "Decor"), String(localized: "Lighting")]
        case .moving:
            [String(localized: "Packing"), String(localized: "Furniture"),
             String(localized: "Appliances"), String(localized: "Services")]
        case .gifts:
            [String(localized: "Family"), String(localized: "Friends"), String(localized: "Colleagues")]
        case .trip:
            [String(localized: "Tickets"), String(localized: "Accommodation"),
             String(localized: "Gear"), String(localized: "Food")]
        case .backToSchool:
            [String(localized: "Stationery"), String(localized: "Clothes"),
             String(localized: "Books"), String(localized: "Electronics")]
        }
    }
}
