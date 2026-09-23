#!/usr/bin/swift

import AppKit
import Foundation

enum BackgroundRendererError: LocalizedError {
    case invalidArguments
    case symbolUnavailable
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: RenderDMGBackground.swift OUTPUT_PATH WIDTH HEIGHT VERTICAL_OFFSET"
        case .symbolUnavailable:
            return "The chevron.right SF Symbol is unavailable on this macOS version."
        case .pngEncodingFailed:
            return "Could not encode the DMG background as a PNG."
        }
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 5,
      let width = Double(arguments[2]),
      let height = Double(arguments[3]),
      let verticalOffset = Double(arguments[4]),
      width > 0,
      height > 0 else {
    throw BackgroundRendererError.invalidArguments
}

let canvasSize = NSSize(width: width, height: height)
let renderScale: CGFloat = 2
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width * Double(renderScale)),
    pixelsHigh: Int(height * Double(renderScale)),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    throw BackgroundRendererError.pngEncodingFailed
}
bitmap.size = canvasSize

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
graphicsContext.cgContext.scaleBy(x: renderScale, y: renderScale)

NSColor(calibratedWhite: 0.975, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

let chevronColor = NSColor(calibratedRed: 0.56, green: 0.56, blue: 0.58, alpha: 1)
let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 60, weight: .medium)
    .applying(NSImage.SymbolConfiguration(hierarchicalColor: chevronColor))
guard let chevron = NSImage(
    systemSymbolName: "chevron.right",
    accessibilityDescription: "Drag to Applications"
)?.withSymbolConfiguration(symbolConfiguration) else {
    NSGraphicsContext.restoreGraphicsState()
    throw BackgroundRendererError.symbolUnavailable
}

chevron.isTemplate = false
let chevronSize = chevron.size
let chevronRect = NSRect(
    x: (canvasSize.width - chevronSize.width) / 2,
    y: (canvasSize.height - chevronSize.height) / 2 + verticalOffset,
    width: chevronSize.width,
    height: chevronSize.height
)
chevron.draw(in: chevronRect)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw BackgroundRendererError.pngEncodingFailed
}

try png.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
