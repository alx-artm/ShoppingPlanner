//
//  MoneyInput.swift
//  Project2
//
//  The rules of a typed price (BUG-26, spec 05 ID-03/ID-03a, 04 LD-15a, 07 SC-09).
//
//  A price field keeps the text the user types and never reformats it while
//  they type: reformatting between keystrokes turned "12." into "12", so the
//  next "5" made 125 (BUG-26). The text is parsed on every change, for a live
//  total, with `DecimalInput` ("," and "." both work as the decimal separator).
//  The currency symbol is drawn next to the field, never inside the text, so
//  deleting every digit means "no price" and not a parse error.
//

import Foundation

/// Where the currency symbol goes for a currency in a locale, and how many
/// fraction digits the currency has: "$12.50" in en_US, "12,50 €" in ru_RU, "¥1,235" (0 digits).
struct CurrencyAffix: Equatable, Sendable {
    enum Position: Equatable, Sendable {
        case prefix
        case suffix
    }

    /// "$", "€", "US$", "₽", "¥"...
    let symbol: String
    let position: Position
    /// 2 for EUR and USD, 0 for JPY (SC-09).
    let fractionDigits: Int

    init(currencyCode: String, locale: Locale) {
        // The formatted 1 shows everything: "$1.00", "1,00 €", "¥1", "€ 1,00".
        let sample = MoneyFormat.string(1, currencyCode: currencyCode, locale: locale)
        let decimalSeparator = locale.decimalSeparator ?? "."
        var symbol = ""
        var digitsSeen = false
        var symbolBeforeDigits = false
        var fractionDigits = 0
        var afterSeparator = false

        for character in sample {
            if character.isNumber {
                digitsSeen = true
                if afterSeparator { fractionDigits += 1 }
            } else if digitsSeen && String(character) == decimalSeparator {
                afterSeparator = true
            } else if character.isWhitespace || character == "-" || character == "\u{2212}"
                        || character == "\u{200E}" || character == "\u{200F}" {
                continue // spaces and direction marks are not part of the symbol
            } else {
                if !digitsSeen { symbolBeforeDigits = true }
                symbol.append(character)
            }
        }
        self.symbol = symbol.isEmpty ? currencyCode : symbol
        position = symbolBeforeDigits ? .prefix : .suffix
        self.fractionDigits = fractionDigits
    }
}

enum MoneyInput {
    /// What a price field's text means.
    enum Parsed: Equatable, Sendable {
        /// Nothing typed: "no price" (`nil`), not 0 (ID-03).
        case empty
        /// A valid amount ≥ 0, rounded to the currency's fraction digits (SC-09).
        case amount(Decimal)
        /// Not an amount, or a negative one (DM-14). The field keeps the last valid value.
        case invalid
    }

    static func parse(_ text: String, currencyCode: String, locale: Locale) -> Parsed {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        let affix = CurrencyAffix(currencyCode: currencyCode, locale: locale)
        guard let value = try? DecimalInput.parse(text, locale: locale,
                                                  ignoring: [affix.symbol, currencyCode.uppercased()]),
              value >= 0 else {
            return .invalid
        }
        return .amount(rounded(value, fractionDigits: affix.fractionDigits))
    }

    /// The text a field shows for `value` when the user is not typing:
    /// "12.50" in en_US, "12,50" in ru_RU, "1235" for JPY, "" for no price.
    /// No grouping and no symbol, so it can be edited and parsed back as is.
    static func editingText(for value: Decimal?, currencyCode: String, locale: Locale) -> String {
        guard let value else { return "" }
        let digits = CurrencyAffix(currencyCode: currencyCode, locale: locale).fractionDigits
        return value.formatted(
            .number
                .precision(.fractionLength(digits))
                .grouping(.never)
                .rounded(rule: .toNearestOrAwayFromZero)
                .locale(locale)
        )
    }

    /// Half away from zero, like `MoneyFormat` ("¥12.5" → 13).
    static func rounded(_ value: Decimal, fractionDigits: Int) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, fractionDigits, .plain)
        return result
    }
}
