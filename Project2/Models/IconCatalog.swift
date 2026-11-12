//
//  IconCatalog.swift
//  Project2
//
//  The icons offered by List Info (spec 03 LI-05, LI-06): a curated grid of
//  SF Symbols and one of emoji, plus the rule for a custom emoji typed into the
//  "Other…" field. No private keyboard API is involved (LI-07, BUG-10): the
//  field is a normal TextField, and the user reaches emoji with the globe key.
//

import Foundation

enum IconCatalog {
    /// Symbols relevant to planning projects and purchases (LI-05: at least 36).
    static let symbols: [String] = [
        "cart", "bag", "basket", "creditcard", "tag", "gift",
        "birthday.cake", "party.popper", "balloon.2", "bed.double", "sofa", "chair.lounge",
        "lamp.desk", "lamp.floor", "paintbrush", "paintbrush.pointed", "hammer", "wrench.and.screwdriver",
        "house", "key", "shippingbox", "airplane", "car", "suitcase",
        "beach.umbrella", "tent", "tshirt", "shoe", "eyeglasses", "figure.child",
        "stroller", "backpack", "book", "graduationcap", "pencil.and.ruler", "fork.knife",
        "cup.and.saucer", "carrot", "leaf", "pawprint", "laptopcomputer", "iphone",
        "gamecontroller", "tv", "camera", "dumbbell", "bicycle", "heart",
    ]

    /// Emoji for the same kinds of projects (LI-06: at least 36).
    static let emojis: [String] = [
        "🛒", "🛍️", "🎁", "🎂", "🎉", "🎈",
        "🛏️", "🛋️", "🪑", "💡", "🖼️", "🎨",
        "🔨", "🧰", "🏠", "🔑", "📦", "✈️",
        "🚗", "🧳", "🏖️", "⛺️", "👕", "👟",
        "👓", "🧸", "👶", "🎒", "📚", "🎓",
        "✏️", "🍽️", "☕️", "🥕", "🌿", "🐾",
        "💻", "📱", "🎮", "📷", "🚲", "❤️",
    ]

    /// `true` when `text` is exactly one grapheme cluster and that cluster is an emoji (LI-06).
    ///
    /// "🧸", "👍🏽", "👨‍👩‍👧", "❤️" pass. "a", "1", "#", "🧸🧸", "" and " 🧸" don't.
    static func isSingleEmoji(_ text: String) -> Bool {
        guard text.count == 1, let character = text.first else { return false }
        return character.isEmoji
    }
}

extension Character {
    /// An emoji as it is displayed, not just a character with the Unicode `Emoji` property:
    /// digits, "#" and "*" have that property too, but render as text without U+FE0F.
    var isEmoji: Bool {
        let scalars = unicodeScalars
        guard let first = scalars.first, first.properties.isEmoji else { return false }
        if first.properties.isEmojiPresentation { return true }
        // Text-default characters become emoji with the variation selector ("❤" + FE0F = "❤️")
        // or in a sequence (a keycap "1️⃣" has FE0F and U+20E3).
        if scalars.contains("\u{FE0F}") { return true }
        return first.value > 0x238C
    }
}
