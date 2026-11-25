//
//  TipJarConfig.swift
//  Project2
//
//  Spec 12 "Флаг": the Tip Jar ships hidden behind a build-time constant, like
//  `SyncConfig.isCloudKitEnabled`. No remote config: turning it on is a commit
//  that flips `isTipJarEnabled` plus a new build (and the IAPs go to App Review
//  together with that version, Owner checklist C).
//

import Foundation

enum TipJarConfig {
    /// Release switch. `false` until the owner checklist (spec 12, block A) is done.
    /// While it is off the app looks exactly as before: no Settings section, no StoreKit calls.
    static let isTipJarEnabled = false

    /// Together with `-UITests` (DEBUG builds only): turns the Tip Jar on for a UI test (TJ-03).
    static let uiTestsTipJarArgument = "-UITestsTipJar"

    /// Together with `-UITests -UITestsTipJar` (DEBUG only): `-UITestsTipJarScenario success`
    /// replaces StoreKit with `ScriptedTipJarStore`, so a UI test drives cancel / pending /
    /// failed purchases without the system purchase sheet. Without it the real StoreKit
    /// store runs against `TipJar.storekit` (the scheme's StoreKit configuration).
    static let uiTestsScenarioArgument = "-UITestsTipJarScenario"

    /// Whether this launch has a Tip Jar (TJ-01, TJ-03).
    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        if isTipJarEnabled { return true }
        #if DEBUG
        return arguments.contains(LaunchConfiguration.uiTestsArgument)
            && arguments.contains(uiTestsTipJarArgument)
        #else
        // Release: launch arguments never turn the Tip Jar on.
        return false
        #endif
    }

    /// The store for this launch: StoreKit, or the scripted fake that a DEBUG UI test asks for.
    @MainActor
    static func makeStore(arguments: [String] = ProcessInfo.processInfo.arguments) -> any TipJarStore {
        #if DEBUG
        if arguments.contains(LaunchConfiguration.uiTestsArgument),
           let index = arguments.firstIndex(of: uiTestsScenarioArgument),
           arguments.indices.contains(index + 1),
           let scenario = ScriptedTipJarStore.Scenario(rawValue: arguments[index + 1]) {
            return ScriptedTipJarStore(scenario: scenario)
        }
        #endif
        return StoreKitTipJarStore(productIDs: TipKind.allCases.map(\.productID))
    }
}

/// The three consumable tips (spec 12 "Продукты"), cheapest first.
enum TipKind: String, CaseIterable, Sendable {
    case coffee
    case lunch
    case bigThanks = "bigthanks"

    /// PLACEHOLDER: `<bundleID>.tip.<name>` with today's bundle id. The final bundle id is
    /// chosen with the app name (M8); change it here AND in `TipJar.storekit` before the IAPs
    /// are created in App Store Connect (a Product ID can't be changed there afterwards).
    static let productIDPrefix = "com.aliakseiartsimuk.Project2.tip."

    var productID: String { Self.productIDPrefix + rawValue }

    init?(productID: String) {
        guard productID.hasPrefix(Self.productIDPrefix) else { return nil }
        self.init(rawValue: String(productID.dropFirst(Self.productIDPrefix.count)))
    }

    /// Decorative symbol of the row (hidden from VoiceOver, TJ-20).
    var systemImage: String {
        switch self {
        case .coffee: "cup.and.saucer"
        case .lunch: "fork.knife"
        case .bigThanks: "gift"
        }
    }

    /// `tipJar.product.coffee` / `.lunch` / `.bigthanks` (TJ-24).
    var accessibilityIdentifier: String { "tipJar.product.\(rawValue)" }
}
