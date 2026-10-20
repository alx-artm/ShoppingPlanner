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
