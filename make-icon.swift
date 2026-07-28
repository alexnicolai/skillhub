#!/usr/bin/swift
// Renders AppIcon iconset from AppIcon-source.png (1024×1024).
// The source has opaque corners; we clip to the macOS-style rounded rect the
// artwork already draws, making everything outside it transparent.
import AppKit

let sourceURL = URL(fileURLWithPath: "AppIcon-source.png")
guard let source = NSImage(contentsOf: sourceURL) else {
    fatalError("AppIcon-source.png missing")
}

let canvas: CGFloat = 1024
// Clip just inside the artwork's own drawn squircle so its anti-aliased white
// edge doesn't leave a halo.
let clipInset: CGFloat = 30
let clipRadius: CGFloat = 185

func drawIcon(size: CGFloat) -> NSImage {
    let scale = size / canvas
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let clipRect = NSRect(
        x: clipInset * scale, y: clipInset * scale,
        width: (canvas - clipInset * 2) * scale,
        height: (canvas - clipInset * 2) * scale
    )
    NSBezierPath(roundedRect: clipRect, xRadius: clipRadius * scale, yRadius: clipRadius * scale)
        .addClip()
    source.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero, operation: .sourceOver, fraction: 1
    )
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
print("iconset written")
