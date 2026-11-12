//
//  TestSupport.swift
//  Project2Tests
//
//  Shared helpers: tags, a controllable clock, a seeded random generator
//  and a decimal parser that avoids binary floating-point literals.
//

import Foundation
import Testing
@testable import Project2

extension Tag {
    /// Money math (spec 01, DM-20...DM-25).
    @Tag static var money: Self
    /// Ordering rules (DM-06, DM-07, DM-15).
    @Tag static var ordering: Self
    /// Validation in the service layer (DM-12...DM-14).
    @Tag static var validation: Self
    /// Delete / cascade behaviour (DM-08, BUG-01).
    @Tag static var deletion: Self
    /// Schema rules required for CloudKit (DM-01...DM-05).
    @Tag static var schema: Self
    /// Regression test for an entry of 00-known-bugs.md.
    @Tag static var regression: Self
    /// Main currency, currency picker and Settings (spec 07, SC-01...SC-13).
    @Tag static var settings: Self
    /// Home screen: sections, ordering, search, status texts (spec 02, HM-01...HM-17).
    @Tag static var home: Self
    /// List Info, icons and templates (spec 03, LI-01...LI-14).
    @Tag static var listInfo: Self
    /// Split-view navigation and deleting an open list (spec 08 AD-xx, DM-18).
    @Tag static var navigation: Self
}

/// The app's own strings (`String(localized:)`) are resolved in the language the
/// test host runs in. Exact English texts are checked only when that language is
/// English; amounts inside them always use an explicit `Locale`, so they don't
/// depend on the machine's region.
enum UILanguage {
    static var isEnglish: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("en") ?? false
    }
}

extension Trait where Self == ConditionTrait {
    /// Skips a test that compares whole English sentences when the host runs in another language.
    static var englishUI: Self {
        .enabled(if: UILanguage.isEnglish, "compares English UI texts")
    }
}

extension String {
    /// The same string with every Unicode space (U+00A0 no-break space,
    /// U+202F narrow no-break space, ...) replaced by a plain space.
    ///
    /// ICU puts no-break spaces between digit groups and before "€" in ru_RU/de_DE.
    /// They are correct, but invisible in test source, so expectations are written
    /// with plain spaces and the actual text is normalised before comparing.
    var plainSpaces: String {
        String(String.UnicodeScalarView(unicodeScalars.map { $0.properties.isWhitespace ? " " : $0 }))
    }
}

/// Exact decimal from a string. `let x: Decimal = 0.1` goes through `Double`
/// and is NOT exactly 0.1, so money tests always build values from strings.
func dec(_ string: String) -> Decimal {
    guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
        preconditionFailure("Not a decimal: \(string)")
    }
    return value
}

/// A clock the test moves by hand, injected into `PlannerStore(now:)`.
@MainActor
final class TestClock {
    private(set) var now: Date

    init(_ start: Date = SeedData.baseDate) {
        now = start
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// Deterministic pseudo-random generator (SplitMix64), so "random" tests
/// produce the same data on every run and every machine.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
