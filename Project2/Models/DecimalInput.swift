//
//  DecimalInput.swift
//  Project2
//
//  Parsing of amounts typed by the user (BUG-28, later BUG-26).
//
//  `Decimal.FormatStyle` parses strictly in the locale: in ru_RU "." is not a
//  separator at all, so "250.5" silently became 250. People get "." from a
//  hardware keyboard, a paste or habit, so both "," and "." are accepted as the
//  decimal separator, and a text that can't be read unambiguously is rejected
//  instead of losing digits.
//
//  Rules, for the digits left after removing spaces and the currency symbol:
//  - both "," and "." present: the last one is the decimal separator, the other
//    one groups digits ("1,500.25", "1.500,25");
//  - one separator, several times: digit grouping, every group after the first
//    must have 3 digits ("1,234,567"), otherwise the text is rejected;
//  - one separator, once: decimal, unless it is the locale's grouping separator
//    followed by exactly 3 digits ("1,500" in en_US is 1500, "250,5" is 250.5).
//

import Foundation

enum DecimalInput {
    struct InvalidInput: Error, Equatable {}

    /// The amount in `text`, or `InvalidInput` when it isn't one.
    ///
    /// - Parameters:
    ///   - locale: decides which separator wins when the text is ambiguous ("1,500").
    ///   - symbols: texts allowed around the number and ignored (currency symbol, ISO code).
    static func parse(_ text: String, locale: Locale, ignoring symbols: [String] = []) throws(InvalidInput) -> Decimal {
        var rest = text
        // Longest first, so "US$" is removed before "$".
        for symbol in symbols.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            rest = rest.replacingOccurrences(of: symbol, with: "")
        }

        var isNegative = false
        var body = ""
        for scalar in rest.unicodeScalars {
            if scalar.properties.isWhitespace { continue }          // spaces, U+00A0, U+202F
            switch scalar {
            case "-", "\u{2212}":                                   // hyphen-minus, minus sign
                guard body.isEmpty, !isNegative else { throw InvalidInput() }
                isNegative = true
            case "0"..."9", ",", ".":
                body.unicodeScalars.append(scalar)
            case "'", "\u{2019}":
                continue                                            // Swiss grouping: 1'234 or 1’234
            case _ where String(scalar) == locale.groupingSeparator:
                continue
            default:
                throw InvalidInput()
            }
        }

        let normalized = try normalize(body, locale: locale)
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            throw InvalidInput()
        }
        return isNegative ? -value : value
    }

    /// Digits with "," and "." → digits with at most one "." as the decimal separator.
    private static func normalize(_ body: String, locale: Locale) throws(InvalidInput) -> String {
        guard body.contains(where: \.isNumber) else { throw InvalidInput() }

        let separators = Set(body.filter { $0 == "," || $0 == "." })
        switch separators.count {
        case 0:
            return body
        case 2:
            // The separator that comes last is the decimal one, and it must appear once.
            guard let last = body.last(where: { $0 == "," || $0 == "." }) else { throw InvalidInput() }
            let grouping: Character = last == "," ? "." : ","
            let parts = body.split(separator: last, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw InvalidInput() }
            try checkGroups(String(parts[0]), separator: grouping)
            return parts[0].filter { $0 != grouping } + "." + String(parts[1])
        default:
            guard let separator = separators.first else { throw InvalidInput() }
            let parts = body.split(separator: separator, omittingEmptySubsequences: false)
            if parts.count > 2 {
                try checkGroups(body, separator: separator)
                return body.filter { $0 != separator }
            }
            let isLocaleGrouping = String(separator) == locale.groupingSeparator
                && String(separator) != locale.decimalSeparator
            if isLocaleGrouping, !parts[0].isEmpty, parts[1].count == 3 {
                return String(parts[0]) + String(parts[1])
            }
            return String(parts[0]) + "." + String(parts[1])
        }
    }

    /// "1,234,567": 1–3 digits, then groups of exactly 3.
    private static func checkGroups(_ integer: String, separator: Character) throws(InvalidInput) {
        let groups = integer.split(separator: separator, omittingEmptySubsequences: false)
        guard groups.count > 1 else { return }
        guard let first = groups.first, (1...3).contains(first.count),
              groups.dropFirst().allSatisfy({ $0.count == 3 }) else {
            throw InvalidInput()
        }
    }
}

/// The format of an amount field (List Info budget; item price in M4):
/// shows the amount like `MoneyFormat`, parses with `DecimalInput`, so both
/// "," and "." work as the decimal separator in any locale (BUG-28).
struct MoneyInputFormat: ParseableFormatStyle {
    var currencyCode: String
    var locale: Locale

    init(currencyCode: String, locale: Locale = .autoupdatingCurrent) {
        self.currencyCode = currencyCode
        self.locale = locale
    }

    func format(_ value: Decimal) -> String {
        MoneyFormat.string(value, currencyCode: currencyCode, locale: locale)
    }

    var parseStrategy: Strategy {
        Strategy(currencyCode: currencyCode, locale: locale)
    }

    struct Strategy: ParseStrategy {
        var currencyCode: String
        var locale: Locale

        func parse(_ value: String) throws -> Decimal {
            try DecimalInput.parse(value, locale: locale, ignoring: symbols)
        }

        /// The list currency's symbol in this locale ("€", "$", "US$") and its ISO code.
        /// Another currency's symbol stays in the text, so it is rejected.
        private var symbols: [String] {
            let sample = MoneyFormat.string(0, currencyCode: currencyCode, locale: locale)
            let symbol = String(sample.unicodeScalars.filter {
                !$0.properties.isWhitespace && !("0"..."9").contains($0)
                    && $0 != "," && $0 != "." && $0 != "-" && $0 != "\u{2212}"
            }.map(Character.init))
            return [symbol, currencyCode.uppercased()]
        }
    }
}
