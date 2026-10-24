import AppKit
import CoreGraphics
import Foundation

// Rebuild with: swift -module-cache-path /private/tmp/moodi-swift-modules ios/artwork/MoodiIcon.swift
// Preserve the supplied artwork exactly; adjust only its scale and placement.
let artwork = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let source = artwork.appendingPathComponent("logo_moodi-original.png")
let output = artwork.appendingPathComponent("../Moodi/Assets.xcassets/AppIcon.appiconset/AppIcon.png").standardizedFileURL
let iconSize = 1024
let sourceData = try Data(contentsOf: source)

guard let sourceBitmap = NSBitmapImageRep(data: sourceData),
      let sourceImage = sourceBitmap.cgImage,
      let background = sourceBitmap.colorAt(x: 0, y: 0)?.usingColorSpace(NSColorSpace.deviceRGB),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: iconSize, pixelsHigh: iconSize,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
    fatalError("Could not load or prepare Moodi artwork")
}

// Find the colored mark against the uniform navy background, ignoring edge antialiasing.
var minX = sourceBitmap.pixelsWide
var minY = sourceBitmap.pixelsHigh
var maxX = 0
var maxY = 0
for y in 0..<sourceBitmap.pixelsHigh {
    for x in 0..<sourceBitmap.pixelsWide {
        guard let pixel = sourceBitmap.colorAt(x: x, y: y)?.usingColorSpace(NSColorSpace.deviceRGB) else { continue }
        let difference = abs(pixel.redComponent - background.redComponent)
            + abs(pixel.greenComponent - background.greenComponent)
            + abs(pixel.blueComponent - background.blueComponent)
        if difference > 0.25 {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
}
guard minX <= maxX, minY <= maxY else { fatalError("No logo pixels found") }

let markWidth = CGFloat(maxX - minX + 1)
let markHeight = CGFloat(maxY - minY + 1)
let scale = min(CGFloat(iconSize) * 0.62 / markWidth,
                CGFloat(iconSize) * 0.54 / markHeight)
let centerX = CGFloat(minX + maxX) / 2
let centerY = CGFloat(sourceBitmap.pixelsHigh - 1) - CGFloat(minY + maxY) / 2

context.setFillColor(CGColor(red: background.redComponent, green: background.greenComponent,
                             blue: background.blueComponent, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: iconSize, height: iconSize))
context.interpolationQuality = .high
context.draw(sourceImage, in: CGRect(x: CGFloat(iconSize) / 2 - centerX * scale,
                                     y: CGFloat(iconSize) / 2 - centerY * scale,
                                     width: CGFloat(sourceBitmap.pixelsWide) * scale,
                                     height: CGFloat(sourceBitmap.pixelsHigh) * scale))

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode app icon")
}
try png.write(to: output)
print("Centered logo saved to \(output.path)")
