#!/usr/bin/env swift
import AppKit
import Foundation

// Package the approved brand artwork at all native macOS icon resolutions.
// Keep the source separate so regeneration never restores the old glyph icon.
let manager = FileManager.default
let resources = URL(fileURLWithPath: manager.currentDirectoryPath).appendingPathComponent("Resources")
let sourceURL = resources.appendingPathComponent("Brand/MirrorIcon-master.png")
let source = NSImage(contentsOf: sourceURL)!
let iconset = resources.appendingPathComponent("AppIcon.iconset")
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

func png(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "MirrorIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot allocate icon bitmap"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    context.cgContext.clear(rect)
    source.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: iconset) }
for (filename, size) in sizes { try png(size: size).write(to: iconset.appendingPathComponent(filename), options: .atomic) }
try png(size: 1024).write(to: resources.appendingPathComponent("AppIcon.png"), options: .atomic)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", resources.appendingPathComponent("AppIcon.icns").path, iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { throw NSError(domain: "MirrorIcon", code: 2) }
print("Generated AppIcon.png and AppIcon.icns from Brand/MirrorIcon-master.png")
