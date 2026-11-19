//
//  ArchivedBanner.swift
//  Project2
//
//  Shown on top of an archived list (spec 10, AR-16, AR-22): "Archived on
//  12 Mar 2026" and Restore. The list stays editable (owner decision
//  2026-11-13), the banner only says where it lives and how to bring it back.
//  At accessibility sizes the text and the button stack, so the date wraps
//  and Restore stays visible (AR-24).
//

import SwiftUI

struct ArchivedBanner: View {
    let archivedAt: Date
    let onRestore: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            Label {
                Text("Archived on \(Self.dateText(archivedAt, locale: locale))")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "archivebox")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Restore", action: onRestore)
                .buttonStyle(.bordered)
                .fixedSize()
                .accessibilityIdentifier("list.archivedBanner.restoreButton")
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("list.archivedBanner")
    }

    /// "12 Mar 2026" in the user's locale ("12 мар. 2026 г.").
    static func dateText(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle().day().month(.abbreviated).year().locale(locale))
    }
}

extension View {
    /// The banner on top of the screen while `list` is archived; it slides away on Restore.
    func archivedBanner(for list: ListModel, onRestore: @escaping () -> Void) -> some View {
        modifier(ArchivedBannerInset(list: list, onRestore: onRestore))
    }
}

private struct ArchivedBannerInset: ViewModifier {
    let list: ListModel
    let onRestore: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top) {
                if let archivedAt = list.archivedAt {
                    ArchivedBanner(archivedAt: archivedAt, onRestore: onRestore)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .default, value: list.isArchived)
    }
}

#Preview {
    VStack {
        ArchivedBanner(archivedAt: .now) {}
        Spacer()
    }
}
