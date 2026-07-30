#!/usr/bin/swift
// Renders AppIcon iconset from AppIcon-source.png (1024×1024).
// The artwork is drawn OVERSCANNED past a macOS-standard squircle mask
// (824×824 grid on a 1024 canvas, r≈185) so any baked border/rim on the
// source gets cropped away, with a soft shadow like Apple's own icons.
import AppKit

let sourceURL = URL(fileURLWithPath: "AppIcon-source.png")
guard let source = NSImage(contentsOf: sourceURL) else {
    fatalError("AppIcon-source.png missing")
}

let canvas: CGFloat = 1024
let grid: CGFloat = 824                 // Apple icon grid content size
let radius: CGFloat = 185.4             // macOS squircle-ish corner radius
/// How far the source is drawn past the mask on each side — crops baked
/// rims/rounded corners in the artwork. Raise if any rim still shows.
let overscan: CGFloat = 70

func drawIcon(size: CGFloat) -> NSImage {
    let scale = size / canvas
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    NSGraphicsContext.current?.imageInterpolation = .high

    let inset = (canvas - grid) / 2 * scale
    let contentRect = NSRect(
        x: inset, y: inset, width: grid * scale, height: grid * scale)
    let mask = NSBezierPath(
        roundedRect: contentRect, xRadius: radius * scale, yRadius: radius * scale)

    // Soft drop shadow behind the tile (skip at menu-bar sizes).
    if size >= 128, let ctx = NSGraphicsContext.current?.cgContext {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -5 * scale),
                      blur: 18 * scale,
                      color: NSColor.black.withAlphaComponent(0.32).cgColor)
        NSColor.white.setFill()
        mask.fill()
        ctx.restoreGState()
    }

    NSGraphicsContext.current?.saveGraphicsState()
    mask.addClip()
    let over = overscan * scale
    source.draw(
        in: contentRect.insetBy(dx: -over, dy: -over),
        from: .zero, operation: .sourceOver, fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.current?.restoreGraphicsState()
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
