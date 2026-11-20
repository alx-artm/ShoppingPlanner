//
//  LinkThumbnail.swift
//  Project2
//
//  Shrinks a page image before it is stored in `linkImageData` (spec 06 A.1 p.2, LP-04).
//  ImageIO makes the thumbnail straight from the encoded data, without decoding the
//  full picture first (WWDC18 219), so a 10 MB product photo doesn't blow up memory.
//  Synchronous and CPU-heavy: call it off the main actor (the fetcher does).
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum LinkThumbnail {
    /// Longest side of the stored image, in pixels.
    static let maxPixelSize = 800
    /// Longest side used when the 800 px image is still too heavy.
    static let fallbackPixelSize = 400
    /// The stored JPEG never exceeds this (CloudKit asset budget, DM-30).
    static let maxByteCount = 200 * 1024
    /// A source bigger than this is not even opened.
    static let maxSourceByteCount = 20 * 1024 * 1024

    /// A JPEG of at most `maxByteCount` bytes and `maxPixelSize` px on the long side,
    /// or `nil` for data that isn't an image or is too big to shrink.
    static func jpegData(from data: Data) -> Data? {
        guard !data.isEmpty, data.count <= maxSourceByteCount else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else { return nil }

        // Lighter steps until the result fits: 800 px at 0.7, 800 px at 0.5, 400 px at 0.5.
        let steps: [(pixelSize: Int, quality: Double)] = [
            (maxPixelSize, 0.7),
            (maxPixelSize, 0.5),
            (fallbackPixelSize, 0.5),
        ]
        for step in steps {
            guard let image = thumbnail(of: source, maxPixelSize: step.pixelSize) else { return nil }
            if let jpeg = encodeJPEG(image, quality: step.quality), jpeg.count <= maxByteCount {
                return jpeg
            }
        }
        return nil
    }

    /// The image scaled down to `maxPixelSize` on its long side (never up), EXIF rotation applied,
    /// on a white background: JPEG has no transparency, and a see-through favicon would turn black.
    private static func thumbnail(of source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return flattened(image)
    }

    private static func flattened(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
