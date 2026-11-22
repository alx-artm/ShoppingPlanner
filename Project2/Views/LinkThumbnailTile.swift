//
//  LinkThumbnailTile.swift
//  Project2
//
//  The link tile of an item row (spec 06 A.2, D1 variant A, LP-15...LP-19): a square with
//  the page picture, or the `link` symbol while there is none (loading, failed, a page
//  without a picture). Always the same size, so the row doesn't jump when the picture comes.
//  A tap opens the page in the app. VoiceOver skips it: the row has an "Open Link" action
//  instead, so a row still has two VoiceOver stops (LP-18).
//  The picture comes from `LinkTileImageCache`, decoded off the main actor; `body` only
//  looks it up (A.1 p.7).
//

import SwiftUI
import UIKit

struct LinkThumbnailTile: View {
    let item: ItemModel
    /// Side in points: `ListRowGrid.linkTileSide` scaled, or the accessibility size.
    let side: CGFloat
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// The picture this tile decoded; a picture decoded earlier comes straight from the cache.
    @State private var loaded: Loaded?

    private struct Loaded {
        let key: LinkTileImageCache.Key
        let image: UIImage
    }

    /// `nil` until the preview is fetched: nothing to decode yet.
    private var key: LinkTileImageCache.Key? {
        guard let fetchedAt = item.linkFetchedAt else { return nil }
        return LinkTileImageCache.Key(itemID: item.uuid, fetchedAt: fetchedAt,
                                      pixelSize: Int((side * displayScale).rounded(.up)))
    }

    var body: some View {
        let key = key
        let image = key.flatMap { key in
            loaded?.key == key ? loaded?.image : LinkTileImageCache.shared.image(for: key)
        }
        Button(action: action) {
            tile(image)
        }
        .buttonStyle(.borderless)
        .hoverEffect(.highlight)
        // Not a VoiceOver stop (the row's "Open Link" action does this); still an element
        // for Voice Control, Full Keyboard Access and UI tests.
        .accessibilityHidden(voiceOverEnabled)
        .accessibilityLabel(Text("Open Link"))
        .accessibilityValue(image == nil ? Text(verbatim: "") : Text("Picture"))
        .accessibilityIdentifier("item.linkThumb.\(item.name)")
        .task(id: key) { await load(key) }
    }

    private func tile(_ image: UIImage?) -> some View {
        let shape = RoundedRectangle(cornerRadius: ListRowGrid.linkTileCornerRadius, style: .continuous)
        return shape
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "link")
                        .font(.system(size: side * 0.4, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(shape)
            // Product photos are usually on white: the outline keeps their edge (A.1 p.6).
            .overlay { shape.strokeBorder(Color(.separator), lineWidth: 0.5) }
            .frame(width: side, height: side)
            .contentShape(shape)
    }

    private func load(_ key: LinkTileImageCache.Key?) async {
        guard let key, loaded?.key != key, LinkTileImageCache.shared.image(for: key) == nil,
              let data = item.linkImageData else { return }
        let image = await LinkTileImageCache.shared.image(for: key, decoding: data)
        guard !Task.isCancelled, let image else { return }
        loaded = Loaded(key: key, image: image)
    }
}
