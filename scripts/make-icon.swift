// Genera Resources/AppIcon.icns dibujando el ícono con CoreGraphics.
// Uso: swift scripts/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    let s = size
    // Fondo: squircle con gradiente índigo → violeta.
    let inset = s * 0.02
    let bg = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = bg.width * 0.225
    let bgPath = CGPath(roundedRect: bg, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let colors = [
        NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.36, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.36, green: 0.22, blue: 0.72, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.62, green: 0.34, blue: 0.86, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: bg.minX, y: bg.minY), end: CGPoint(x: bg.maxX, y: bg.maxY), options: [])
    // Brillo superior sutil.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor.white.withAlphaComponent(0.18).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(glow, start: CGPoint(x: bg.midX, y: bg.maxY), end: CGPoint(x: bg.midX, y: bg.midY), options: [])
    ctx.restoreGState()

    // Tres columnas.
    let margin = s * 0.16
    let gap = s * 0.045
    let area = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let colWidth = (area.width - gap * 2) / 3
    let colRadius = colWidth * 0.16

    func panel(_ rect: CGRect, alpha: CGFloat, radius: CGFloat) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Columnas laterales: paneles simples y translúcidos.
    for i in [0, 2] {
        let x = area.minX + CGFloat(i) * (colWidth + gap)
        panel(CGRect(x: x, y: area.minY, width: colWidth, height: area.height), alpha: 0.28, radius: colRadius)
    }

    // Columna central: pila de tres ventanas con profundidad, la frontal en acento cálido.
    let cx = area.minX + colWidth + gap
    let stackCount = 3
    let step = s * 0.055
    let cardHeight = area.height - step * CGFloat(stackCount - 1)
    for i in 0..<stackCount {
        let depth = CGFloat(stackCount - 1 - i)   // 2, 1, 0 → la última es la frontal
        let shrink = depth * s * 0.02
        let rect = CGRect(x: cx + shrink, y: area.minY + depth * step, width: colWidth - shrink * 2, height: cardHeight)
        if i == stackCount - 1 {
            let path = CGPath(roundedRect: rect, cornerWidth: colRadius, cornerHeight: colRadius, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.04, color: NSColor.black.withAlphaComponent(0.45).cgColor)
            ctx.addPath(path)
            ctx.clip()
            let accent = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.40, alpha: 1).cgColor,
                                             NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.45, alpha: 1).cgColor] as CFArray,
                                    locations: [0, 1])!
            ctx.drawLinearGradient(accent, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
            ctx.restoreGState()
            // "Barra de título" de la ventana frontal.
            let bar = CGRect(x: rect.minX + rect.width * 0.18, y: rect.maxY - rect.height * 0.16, width: rect.width * 0.64, height: rect.height * 0.045)
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.addPath(CGPath(roundedRect: bar, cornerWidth: bar.height / 2, cornerHeight: bar.height / 2, transform: nil))
            ctx.fillPath()
        } else {
            panel(rect, alpha: 0.35 + CGFloat(i) * 0.2, radius: colRadius)
        }
    }

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, pixels) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                       ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let data = png(drawIcon(size: CGFloat(pixels)), pixels: pixels)
    try! data.write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try! png(drawIcon(size: 1024), pixels: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-preview.png"))
print("iconset generado")
