//
//  LinkPreviewCard.swift
//  Project2
//
//  The saved link of an item in its details (spec 06 A.2, LP-05, LP-07, LP-09):
//  - with a preview: a card — the page picture across the form (1.91:1, at most 180 pt high),
//    the title and the host; without a picture, a 64 pt tile with the link symbol instead;
//  - without one (still loading, or failed): a compact "🔗 host" row, a spinner while loading.
//  Errors are never shown (D5). A tap opens the link in the app, the context menu (and the
//  VoiceOver actions) has Open in Safari, Copy Link, Refresh Preview and Remove Link.
//  Our own view, not `LPLinkView` (STRATEGY §3); no glass on content (A.1 p.6).
//

import SwiftUI
import UIKit

struct LinkPreviewCard: View {
    let item: ItemModel
    /// "Remove Link" only changes the details' draft (✕ undoes it, ID-01), so the sheet owns it.
    let onRemove: () -> Void

    @Environment(LinkPreviewService.self) private var linkPreviews
    @Environment(\.linkOpener) private var linkOpener
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The picture, decoded once per preview and off the main thread, not in `body`.
    @State private var image: UIImage?

    private var url: URL? { ItemLink.url(from: item.urlString) }
    private var hasPreview: Bool { item.linkFetchedAt != nil }
    private var title: String? { item.linkTitle }
    private var host: String { item.linkHost ?? ItemLink.displayHost(of: item.urlString) ?? item.urlString }
    private var isFetching: Bool { linkPreviews.isFetching(item.uuid) }

    var body: some View {
        Button {
            if let url { linkOpener.open(url, .inApp, using: openURL) }
        } label: {
            Group {
                if !hasPreview {
                    compactRow
                } else if item.linkImageData != nil {
                    heroCard
                } else {
                    tileCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
        // One VoiceOver stop: "Link: <title>, <host>", a button (LP-09); the menu as actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isFetching ? Text("Loading preview") : Text(verbatim: ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Open in Safari")) { openExternally() }
        .accessibilityAction(named: Text("Copy Link")) { copy() }
        .accessibilityAction(named: Text("Refresh Preview")) { linkPreviews.refresh(item) }
        .accessibilityAction(named: Text("Remove Link")) { onRemove() }
        .accessibilityIdentifier(hasPreview ? "itemEdit.linkCard" : "itemEdit.linkCompact")
        .task(id: item.linkFetchedAt) { await loadImage() }
    }

    private var accessibilityLabel: Text {
        if let title {
            Text("Link: \(title), \(host)")
        } else {
            Text("Link: \(host)")
        }
    }

    // MARK: - Layouts

    /// No preview yet or the fetch failed: "🔗 host" (+ a spinner while fetching).
    private var compactRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.tint)
            Text(verbatim: host)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            Spacer(minLength: 0)
            if isFetching {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("itemEdit.linkLoading")
            }
        }
    }

    /// A picture across the row, then the title and the host.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeroImageLayout {
                // The shape takes the layout's size; the filled picture is cropped to it.
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .clipShape(.rect(cornerRadius: LinkCardMetrics.heroCornerRadius, style: .continuous))
                    .overlay {
                        // Product photos are usually on white: an outline keeps their edge (A.1 p.6).
                        RoundedRectangle(cornerRadius: LinkCardMetrics.heroCornerRadius, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    }
            }
            titleAndHost
        }
        .padding(.vertical, 4)
    }

    /// A page without a picture: the link tile, then the title and the host.
    /// At accessibility sizes the text goes under the tile and gets the whole width.
    private var tileCard: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            RoundedRectangle(cornerRadius: LinkCardMetrics.tileCornerRadius, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "link")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: LinkCardMetrics.tileCornerRadius, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                }
                .frame(width: LinkCardMetrics.tileSide, height: LinkCardMetrics.tileSide)
            titleAndHost
        }
        .padding(.vertical, 4)
    }

    private var titleAndHost: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(verbatim: title)
                    .font(.headline)
                    // Two lines as specified; at accessibility sizes the whole title (LP-14).
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            HStack(spacing: 6) {
                Text(verbatim: host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                if isFetching {
                    // Refresh Preview is running.
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityIdentifier("itemEdit.linkLoading")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Menu

    @ViewBuilder
    private var menu: some View {
        Button("Open in Safari", systemImage: "safari") { openExternally() }
            .accessibilityIdentifier("itemEdit.linkMenu.openInSafari")
        Button("Copy Link", systemImage: "doc.on.doc") { copy() }
            .accessibilityIdentifier("itemEdit.linkMenu.copy")
        Button("Refresh Preview", systemImage: "arrow.clockwise") { linkPreviews.refresh(item) }
            .accessibilityIdentifier("itemEdit.linkMenu.refresh")
        Divider()
        Button("Remove Link", systemImage: "trash", role: .destructive) { onRemove() }
            .accessibilityIdentifier("itemEdit.linkMenu.remove")
    }

    private func openExternally() {
        if let url { linkOpener.open(url, .external, using: openURL) }
    }

    private func copy() {
        if let url { UIPasteboard.general.url = url }
    }

    // MARK: - Picture

    private func loadImage() async {
        guard let data = item.linkImageData else {
            image = nil
            return
        }
        // `byPreparingForDisplay` decodes in the background; `body` only draws the result.
        image = await UIImage(data: data)?.byPreparingForDisplay()
    }
}

/// Places its content at the full proposed width and `LinkCardMetrics.heroHeight` high.
/// A plain `.aspectRatio` can't cap the height without leaving a wide iPad sheet's picture overflowing.
private struct HeroImageLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let fallbackWidth = LinkCardMetrics.heroMaxHeight * LinkCardMetrics.heroAspectRatio
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? fallbackWidth
        return CGSize(width: width, height: LinkCardMetrics.heroHeight(forWidth: width))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}
