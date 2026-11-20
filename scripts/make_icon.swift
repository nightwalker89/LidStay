import AppKit
import CoreGraphics
import Foundation

func renderIcon(size: CGFloat, outURL: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        throw NSError(domain: "IconGen", code: 1)
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let radius = cardRect.width * 0.225
    let path = CGPath(roundedRect: cardRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.025), blur: size * 0.05, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.20, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1.0).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    }

    // Warm amber glow in top-right
    let glowColors = [
        NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.14, alpha: 0.48).cgColor,
        NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.10, alpha: 0.0).cgColor
    ] as CFArray
    if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        let center = CGPoint(x: cardRect.maxX - cardRect.width * 0.22, y: cardRect.maxY - cardRect.height * 0.22)
        ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: cardRect.width * 0.72, options: [])
    }
    ctx.restoreGState()

    // Inner subtle border
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    ctx.setLineWidth(max(1.0, size * 0.012))
    ctx.strokePath()
    ctx.restoreGState()

    // SF Symbol laptopcomputer in center with amber-gold gradient feel
    let symConfig = NSImage.SymbolConfiguration(pointSize: size * 0.40, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil)?.withSymbolConfiguration(symConfig) {
        let tinted = NSImage(size: sym.size, flipped: false) { drawRect in
            sym.draw(in: drawRect)
            NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.30, alpha: 1.0).set()
            drawRect.fill(using: .sourceAtop)
            return true
        }
        let targetW = sym.size.width
        let targetH = sym.size.height
        let symRect = CGRect(
            x: (size - targetW) / 2.0,
            y: (size - targetH) / 2.0 - size * 0.02,
            width: targetW,
            height: targetH
        )
        tinted.draw(in: symRect)
    }

    // Small glowing dot indicator top-right inside icon
    let dotSize = size * 0.09
    let dotRect = CGRect(
        x: cardRect.maxX - cardRect.width * 0.22,
        y: cardRect.maxY - cardRect.height * 0.22,
        width: dotSize,
        height: dotSize
    )
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: size * 0.04, color: NSColor.orange.withAlphaComponent(0.9).cgColor)
    ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.24, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: dotRect)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 2)
    }
    try png.write(to: outURL)
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: make_icon.swift <iconset_dir>\n", stderr)
    exit(1)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let specs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    try renderIcon(size: px, outURL: outDir.appendingPathComponent(name))
}
