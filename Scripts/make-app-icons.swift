#!/usr/bin/env swift
//
// Generates the app icon for both platforms from the tuner's own design language:
// blue body, gauge arc, needle, green in-tune window.
//
//   swift Scripts/make-app-icons.swift
//
// Outputs:
//   Resources/AppIcon.iconset/*.png   (intermediates)
//   Resources/AppIcon.icns            (macOS, copied into the .app by make-macos-app.sh)
//   Platforms/iOS/Assets.xcassets/AppIcon.appiconset/*.png + Contents.json
//
// Drawing it in code (instead of shipping one static PNG) keeps the icon consistent with
// the gauge in the app and makes it trivial to change colours later.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry

/// Everything is drawn on a 1024 pt canvas and scaled down, so every size stays crisp.
let canvasSize: CGFloat = 1024

enum IconStyle {
    /// macOS: an 824 pt rounded "squircle" centred on a transparent canvas, with a shadow.
    case macOS
    /// iOS: full-bleed square; the system applies the mask, and icons must have no alpha.
    case iOS
}

let contentInset: CGFloat = 100
let contentRect = CGRect(
    x: contentInset,
    y: contentInset,
    width: canvasSize - contentInset * 2,
    height: canvasSize - contentInset * 2
)
let squircleRadius = contentRect.width * 0.2237

/// Gauge centre / radius inside the content square.
let gaugeCentre = CGPoint(x: canvasSize / 2, y: 470)
let gaugeRadius: CGFloat = 250

// MARK: - Palette

func rgba(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

let bodyTop = rgba(0.20, 0.49, 1.00)
let bodyBottom = rgba(0.03, 0.21, 0.72)
let bodyFlat = rgba(0.06, 0.28, 0.85)
let inTuneGreen = rgba(0.18, 0.84, 0.47)

// MARK: - Drawing

func radians(_ degrees: CGFloat) -> CGFloat {
    degrees * .pi / 180
}

/// Cents -> angle on the dial. 0 cents points straight up, ±50 cents is ±118°.
///
/// The result decreases as cents increase (208° → 90° → -28°), which is why every arc
/// below is stroked `clockwise: true`: in CoreGraphics user space (y up) that is the
/// decreasing-angle direction.
func angle(forCents cents: CGFloat) -> CGFloat {
    90 - cents / 50 * 118
}

func point(from centre: CGPoint, angle degrees: CGFloat, distance: CGFloat) -> CGPoint {
    let radians = radians(degrees)
    return CGPoint(
        x: centre.x + distance * cos(radians),
        y: centre.y + distance * sin(radians)
    )
}

func drawBody(in context: CGContext, style: IconStyle) {
    let path: CGPath
    switch style {
    case .macOS:
        path = CGPath(
            roundedRect: contentRect,
            cornerWidth: squircleRadius,
            cornerHeight: squircleRadius,
            transform: nil
        )
    case .iOS:
        path = CGPath(rect: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize), transform: nil)
    }

    // Drop shadow (macOS only — iOS masks the icon itself).
    if style == .macOS {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -14), blur: 38, color: rgba(0, 0, 0, 0.30))
        context.addPath(path)
        context.setFillColor(bodyFlat)
        context.fillPath()
        context.restoreGState()
    }

    context.saveGState()
    context.addPath(path)
    context.clip()

    let bounds = path.boundingBox
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [bodyTop, bodyBottom] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.midX, y: bounds.maxY),
            end: CGPoint(x: bounds.midX, y: bounds.minY),
            options: []
        )
    }

    // Soft highlight along the top edge, like light falling on the body.
    if let highlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [rgba(1, 1, 1, 0.22), rgba(1, 1, 1, 0)] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            highlight,
            start: CGPoint(x: bounds.midX, y: bounds.maxY),
            end: CGPoint(x: bounds.midX, y: bounds.midY),
            options: []
        )
    }
    context.restoreGState()
}

func drawGauge(in context: CGContext) {
    let centre = gaugeCentre
    let radius = gaugeRadius
    // Generous strokes: the icon is also rendered at 16 and 32 px, where anything thinner
    // than ~2% of the canvas disappears while downsampling.
    let lineWidth = radius * 0.21

    // Dial track.
    context.setLineCap(.round)
    context.setLineWidth(lineWidth)
    context.setStrokeColor(rgba(1, 1, 1, 0.28))
    context.addArc(
        center: centre,
        radius: radius,
        startAngle: radians(angle(forCents: -50)),
        endAngle: radians(angle(forCents: 50)),
        clockwise: true
    )
    context.strokePath()

    // In-tune window.
    context.setLineCap(.butt)
    context.setLineWidth(lineWidth)
    context.setStrokeColor(inTuneGreen)
    context.addArc(
        center: centre,
        radius: radius,
        startAngle: radians(angle(forCents: -10)),
        endAngle: radians(angle(forCents: 10)),
        clockwise: true
    )
    context.strokePath()

    // Tick marks every 10 cents, skipping the in-tune window.
    context.setLineWidth(radius * 0.042)
    context.setStrokeColor(rgba(1, 1, 1, 0.55))
    for cents in stride(from: CGFloat(-50), through: 50, by: 10) where abs(cents) >= 10 {
        let tickAngle = angle(forCents: cents)
        context.move(to: point(from: centre, angle: tickAngle, distance: radius - lineWidth * 1.05))
        context.addLine(to: point(from: centre, angle: tickAngle, distance: radius - lineWidth * 0.62))
    }
    context.strokePath()

    // Needle, dead centre: the instrument is in tune.
    let tip = point(from: centre, angle: 90, distance: radius * 1.14)
    let baseY = centre.y + radius * 0.44
    let halfWidth = radius * 0.115

    let needle = CGMutablePath()
    needle.move(to: tip)
    needle.addLine(to: CGPoint(x: centre.x + halfWidth, y: baseY))
    needle.addQuadCurve(
        to: CGPoint(x: centre.x - halfWidth, y: baseY),
        control: CGPoint(x: centre.x, y: baseY - halfWidth * 1.4)
    )
    needle.closeSubpath()

    context.setShadow(offset: .zero, blur: radius * 0.12, color: rgba(0, 0, 0, 0.25))
    context.addPath(needle)
    context.setFillColor(rgba(1, 1, 1))
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    // Hub.
    let hubRadius = radius * 0.17
    context.setFillColor(rgba(1, 1, 1))
    context.fillEllipse(
        in: CGRect(
            x: centre.x - hubRadius,
            y: centre.y - hubRadius,
            width: hubRadius * 2,
            height: hubRadius * 2
        )
    )
    let coreRadius = hubRadius * 0.44
    context.setFillColor(bodyFlat)
    context.fillEllipse(
        in: CGRect(
            x: centre.x - coreRadius,
            y: centre.y - coreRadius,
            width: coreRadius * 2,
            height: coreRadius * 2
        )
    )
}

func renderIcon(pixels: Int, style: IconStyle) -> CGImage? {
    let alphaInfo: CGImageAlphaInfo = style == .iOS ? .noneSkipLast : .premultipliedLast
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: alphaInfo.rawValue
    ) else { return nil }

    let scale = CGFloat(pixels) / canvasSize
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    if style == .iOS {
        // Opaque base: iOS rejects alpha in app icons.
        context.setFillColor(bodyFlat)
        context.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    }

    drawBody(in: context, style: style)
    drawGauge(in: context)

    return context.makeImage()
}

func pngData(for image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoder failed"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "IconGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    return data as Data
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try pngData(for: image).write(to: url, options: .atomic)
}

/// Writes an `.icns` directly: the container is a list of typed chunks — 4-byte type,
/// 4-byte big-endian length (header included), then the payload, and a PNG is a valid
/// payload. Doing it here keeps the generator free of `iconutil`, which rejects even a
/// minimal valid iconset in some environments.
func writeICNS(entries: [(type: String, image: CGImage)], to url: URL) throws {
    var chunks = Data()
    for entry in entries {
        let payload = try pngData(for: entry.image)
        var header = Data(entry.type.utf8)
        var length = UInt32(payload.count + 8).bigEndian
        withUnsafeBytes(of: &length) { header.append(contentsOf: $0) }
        chunks.append(header)
        chunks.append(payload)
    }

    var file = Data("icns".utf8)
    var total = UInt32(chunks.count + 8).bigEndian
    withUnsafeBytes(of: &total) { file.append(contentsOf: $0) }
    file.append(chunks)
    try file.write(to: url, options: .atomic)
}

// MARK: - Run

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let iconsetURL = root.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
let icnsURL = root.appendingPathComponent("Resources/AppIcon.icns")
let iosIconSetURL = root.appendingPathComponent(
    "Platforms/iOS/Assets.xcassets/AppIcon.appiconset",
    isDirectory: true
)

for directory in [iconsetURL, iosIconSetURL] {
    try? fileManager.removeItem(at: directory)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
}

// Render every pixel size once and reuse it for both platforms' outputs.
let renderedSizes = [16, 32, 64, 128, 256, 512, 1024]
var rendered: [Int: CGImage] = [:]
for pixels in renderedSizes {
    guard let image = renderIcon(pixels: pixels, style: .macOS) else {
        throw NSError(
            domain: "IconGen",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "render failed at \(pixels) px"]
        )
    }
    rendered[pixels] = image
}

/// `.iconset` is the standard interchange format (and what designers expect); it is also
/// the easiest thing to inspect at a glance.
let iconsetEntries: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for entry in iconsetEntries {
    guard let image = rendered[entry.points * entry.scale] else { continue }
    let suffix = entry.scale == 2 ? "@2x" : ""
    try writePNG(image, to: iconsetURL.appendingPathComponent("icon_\(entry.points)x\(entry.points)\(suffix).png"))
}

// Type codes are the modern PNG-based ones: icp4/5/6 are the small sizes, ic07…ic10 the
// large ones, and ic11…ic14 the @2x variants macOS also looks for.
let icnsEntries: [(type: String, pixels: Int)] = [
    ("icp4", 16), ("icp5", 32), ("icp6", 64),
    ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
    ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512),
]
let icnsImages: [(type: String, image: CGImage)] = icnsEntries.compactMap { entry in
    guard let image = rendered[entry.pixels] else { return nil }
    return (entry.type, image)
}
try writeICNS(entries: icnsImages, to: icnsURL)

guard let iOSImage = renderIcon(pixels: 1024, style: .iOS) else {
    throw NSError(domain: "IconGen", code: 4, userInfo: [NSLocalizedDescriptionKey: "iOS render failed"])
}
try writePNG(iOSImage, to: iosIconSetURL.appendingPathComponent("AppIcon-1024.png"))

let contents = """
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try contents.write(
    to: iosIconSetURL.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)

print("Wrote \(icnsURL.path)")
print("Wrote \(iosIconSetURL.path)")
