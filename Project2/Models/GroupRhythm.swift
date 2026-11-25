//
//  GroupRhythm.swift
//  Project2
//
//  The vertical rhythm of group headers on the list screen (spec 04 LD-30,
//  UX_REVIEW 14C). Collapsed groups read as a table of contents: 16 pt
//  between two header buttons (a 60 pt step with the 44 pt button); after an
//  expanded group there is more air, 24 pt from its last row to the next
//  header, so the blocks stay apart.
//
//  The gap is the list's section spacing plus the header cell's insets:
//  collapsed → collapsed: bottom inset + spacing + top inset = 4 + 8 + 4 = 16;
//  expanded → next header: spacing + top inset = 8 + 16 = 24.
//

import CoreGraphics

enum GroupRhythm {
    /// Between two sections, instead of the plain list's 22 pt.
    static let sectionSpacing: CGFloat = 8
    /// Above and below the header button inside its cell.
    static let headerBottomInset: CGFloat = 4
    private static let headerTopInset: CGFloat = 4
    /// Added above a header that follows an expanded group.
    private static let afterExpandedExtra: CGFloat = 12
    /// How far the header's opaque background reaches past its content on each side, so a
    /// pinned header covers the whole width of the row scrolling under it (M7.5).
    static let headerBackgroundBleed: CGFloat = 64

    static func headerTopInset(followsExpandedGroup: Bool) -> CGFloat {
        headerTopInset + (followsExpandedGroup ? afterExpandedExtra : 0)
    }

    /// The group right before `group` in `groups` (screen order) is expanded. Its last row
    /// ("＋ New Item" or the inline row) then ends right above this header.
    static func followsExpandedGroup<Group: AnyObject>(_ group: Group, in groups: [Group],
                                                      isExpanded: (Group) -> Bool) -> Bool {
        guard let index = groups.firstIndex(where: { $0 === group }), index > 0 else { return false }
        return isExpanded(groups[index - 1])
    }
}
