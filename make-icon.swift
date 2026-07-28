#!/usr/bin/swift
// Renders AppIcon.icns for SkillHub: indigo→violet gradient rounded-rect
// (macOS HIG: ~824pt content on 1024 canvas with baked corner radius),
// white wand.and.stars SF Symbol centered.
import AppKit

let canvas: CGFloat = 1024
let content: CGFloat = 824             // HIG margin for macOS icons
let corner: CGFloat = content * 0.225  // macOS squircle-ish radius

func drawIcon(size: CGFloat) -> NSImage {
    let scale = size / canvas
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let inset = (canvas - content) / 2 * scale
    let rect = NSRect(x: inset, y: inset, width: content * scale, height: content * scale)
    let path = NSBezierPath(roundedRect: rect, xRadius: corner * scale, yRadius: corner * scale)

    // Subtle drop shadow so the icon sits on light docks.
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6 * scale),
                      blur: 24 * scale,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
        NSColor.black.withAlphaComponent(0.001).setFill()
        path.fill()
        ctx.restoreGState()
    }

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.42, green: 0.36, blue: 0.95, alpha: 1),  // indigo
        NSColor(calibratedRed: 0.62, green: 0.32, blue: 0.92, alpha: 1),  // violet
    ])!
    gradient.draw(in: path, angle: -60)

    // Faint inner highlight along the top edge for depth.
    path.addClip()
    let highlight = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.28),
        NSColor.white.withAlphaComponent(0.0),
    ])!
    highlight.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)

    // Symbol
    let config = NSImage.SymbolConfiguration(pointSize: 380 * scale, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let symbolRect = NSRect(
            x: (size - tinted.size.width) / 2,
            y: (size - tinted.size.height) / 2,
            width: tinted.size.width,
            height: tinted.size.height
        )
        tinted.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    }
    return image
}

func writePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    try! png.write(to: url)
}

let iconset = URL(fileURLWithPath: "dist/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    writePNG(drawIcon(size: CGFloat(base)), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(drawIcon(size: CGFloat(base * 2)), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("iconset written — run iconutil to produce .icns")
