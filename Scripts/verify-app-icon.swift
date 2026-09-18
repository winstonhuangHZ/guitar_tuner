#!/usr/bin/env swift
//
// Renders nothing: it loads the generated icons and checks the geometry came out the way
// the generator intends. Useful because an icon is easy to get wrong silently — a wrong
// corner, an opaque macOS margin, a needle that never got drawn.
//
//   swift Scripts/verify-app-icon.swift

import CoreGraphics
import Foundation
import ImageIO

struct Pixel {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8
}

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
        return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

struct Bitmap {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(_ image: CGImage) {
        let pixelWidth = image.width
        let pixelHeight = image.height
        let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelWidth * pixelHeight * 4)
        defer { pointer.deallocate() }

        guard let context = CGContext(
            data: pointer,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        width = pixelWidth
        height = pixelHeight
        bytes = Array(UnsafeBufferPointer(start: pointer, count: pixelWidth * pixelHeight * 4))
    }

    /// `yUp` matches the coordinate system the icon was drawn in.
    func pixel(x: Int, yUp: Int) -> Pixel {
        let row = height - 1 - yUp
        let offset = (row * width + x) * 4
        return Pixel(
            red: bytes[offset],
            green: bytes[offset + 1],
            blue: bytes[offset + 2],
            alpha: bytes[offset + 3]
        )
    }

    var isTransparentAtEdges: Bool {
        pixel(x: 4, yUp: 4).alpha < 8 && pixel(x: width - 5, yUp: height - 5).alpha < 8
    }

    func count(where predicate: (Pixel) -> Bool) -> Int {
        var total = 0
        for row in stride(from: 0, to: height, by: 2) {
            for column in stride(from: 0, to: width, by: 2) {
                if predicate(pixel(x: column, yUp: row)) { total += 1 }
            }
        }
        return total
    }
}

func isBluish(_ pixel: Pixel) -> Bool {
    pixel.blue > 120 && pixel.blue > pixel.red && pixel.alpha > 200
}

func isWhiteish(_ pixel: Pixel) -> Bool {
    pixel.red > 225 && pixel.green > 225 && pixel.blue > 225 && pixel.alpha > 200
}

func isGreenish(_ pixel: Pixel) -> Bool {
    pixel.green > 150 && pixel.green > Int(pixel.red) + 40 && pixel.green > Int(pixel.blue) + 20
}

/// Ticks are white at 55% over the blue body, so they are deliberately lighter than the
/// dial track (white at 28%) without being pure white.
func isTickMark(_ pixel: Pixel) -> Bool {
    pixel.red > 110 && pixel.green > 140 && pixel.blue > 200 && pixel.alpha > 200
}

var failures: [String] = []

func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("✓ \(message)")
    } else {
        print("✗ \(message)")
        failures.append(message)
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// MARK: - macOS icon

let macPath = root.appendingPathComponent("Resources/AppIcon.iconset/icon_512x512@2x.png").path
guard let macImage = loadImage(macPath), let mac = Bitmap(macImage), mac.width == 1024 else {
    print("✗ could not load \(macPath)")
    exit(1)
}

print("macOS icon (\(mac.width)×\(mac.height))")
expect(mac.isTransparentAtEdges, "corners are transparent (rounded icon, not a full square)")
expect(isBluish(mac.pixel(x: 200, yUp: 220)), "body is blue inside the squircle")

// The needle runs up the centre line, so the dial is sampled beside it: the hub ring
// rather than its blue core, and the in-tune window a few cents off centre.
expect(isWhiteish(mac.pixel(x: 512, yUp: 620)), "needle is drawn above the hub")
expect(isBluish(mac.pixel(x: 512 + 45, yUp: 600)), "dial is open to the right of the needle")
expect(isBluish(mac.pixel(x: 512 - 45, yUp: 600)), "dial is open to the left of the needle")
expect(isTickMark(mac.pixel(x: 596, yUp: 663)), "tick mark is drawn at +10 cents")
expect(isTickMark(mac.pixel(x: 428, yUp: 663)), "tick mark is drawn at -10 cents")
expect(
    isGreenish(mac.pixel(x: 563, yUp: 715)),
    "in-tune window is green just right of the needle"
)
expect(
    isGreenish(mac.pixel(x: 461, yUp: 715)),
    "in-tune window is green just left of the needle"
)
expect(isBluish(mac.pixel(x: 512, yUp: 470)), "hub core is blue")
expect(isWhiteish(mac.pixel(x: 512 + 30, yUp: 470)), "hub ring is white around the core")

let macWhiteShare = Double(mac.count(where: isWhiteish)) / Double(mac.width * mac.height / 4)
let macGreenShare = Double(mac.count(where: isGreenish)) / Double(mac.width * mac.height / 4)
// Only the needle, hub and ticks are near-white; the dial track is white at 28% over
// blue, so it reads as light blue and is not counted here.
expect(
    macWhiteShare > 0.004 && macWhiteShare < 0.25,
    "dial chrome has a sensible weight (white share \(String(format: "%.4f", macWhiteShare)))"
)
expect(macGreenShare > 0.0004, "green in-tune window is visible (share \(String(format: "%.4f", macGreenShare)))")

// MARK: - Small size legibility

let smallPath = root.appendingPathComponent("Resources/AppIcon.iconset/icon_32x32.png").path
guard let smallImage = loadImage(smallPath), let small = Bitmap(smallImage), small.width == 32 else {
    print("✗ could not load \(smallPath)")
    exit(1)
}
print("\n32 pt icon (dock list size)")
expect(small.count(where: isBluish) > 32 * 32 / 8, "blue body still dominates at 32 px")
expect(small.count(where: isGreenish) > 0, "in-tune window survives the downscale to 32 px")

// At 32 px the needle is ~2 px wide and antialiased against the blue body, so exact white
// is the wrong measure: compare the needle column against plain body pixels instead.
func brightestGreen(_ bitmap: Bitmap, x: Int, yFrom: Int, yTo: Int) -> Int {
    var best = 0
    for yUp in yFrom...yTo {
        best = max(best, Int(bitmap.pixel(x: x, yUp: yUp).green))
    }
    return best
}

let needleBrightness = brightestGreen(small, x: 16, yFrom: 18, yTo: 24)
let bodyBrightness = Int(small.pixel(x: 6, yUp: 20).green)
expect(
    needleBrightness > bodyBrightness + 40,
    "needle reads brighter than the body at 32 px (\(needleBrightness) vs \(bodyBrightness))"
)

// MARK: - iOS icon

let iOSPath = root.appendingPathComponent(
    "Platforms/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
).path
guard let iOSImage = loadImage(iOSPath), let iOS = Bitmap(iOSImage), iOS.width == 1024 else {
    print("✗ could not load \(iOSPath)")
    exit(1)
}

print("\niOS icon (\(iOS.width)×\(iOS.height))")
expect(!iOS.isTransparentAtEdges, "icon is fully opaque (iOS rejects alpha)")
expect(iOS.pixel(x: 4, yUp: 4).alpha == 255, "corner alpha is 255, not blended")
expect(isBluish(iOS.pixel(x: 120, yUp: 120)), "body reaches the edges (system applies the mask)")
expect(isGreenish(iOS.pixel(x: 563, yUp: 715)), "in-tune window is green beside the needle")

// MARK: - ICNS container

let icnsURL = root.appendingPathComponent("Resources/AppIcon.icns")
guard let data = try? Data(contentsOf: icnsURL), data.count > 1024 else {
    print("✗ could not read AppIcon.icns")
    exit(1)
}
print("\nICNS container")
expect(Array(data.prefix(4)) == Array("icns".utf8), "file starts with the 'icns' magic")
let declared = data.prefix(8).suffix(4).reduce(0) { ($0 << 8) | Int($1) }
expect(declared == data.count, "declared length \(declared) matches file length \(data.count)")

var offset = 8
var chunkTypes: [String] = []
while offset + 8 <= data.count {
    let type = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
    let length = data[(offset + 4)..<(offset + 8)].reduce(0) { ($0 << 8) | Int($1) }
    guard length >= 8, offset + length <= data.count else { break }
    chunkTypes.append(type)
    offset += length
}
expect(chunkTypes.contains("ic10"), "contains the 1024 px chunk (ic10)")
expect(chunkTypes.contains("icp4"), "contains the 16 px chunk (icp4)")
expect(chunkTypes.count >= 10, "contains \(chunkTypes.count) chunks")

print("")
if failures.isEmpty {
    print("All icon checks passed.")
    exit(0)
}
print("\(failures.count) icon checks failed.")
exit(1)
