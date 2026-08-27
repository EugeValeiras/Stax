// Genera docs/stax-demo.gif: animación ilustrativa de Stax (dibujada con CoreGraphics, sin grabar pantalla).
// Uso: swift scripts/make-demo.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let W: CGFloat = 960, H: CGFloat = 400
let FPS = 20.0
let DURATION = 12.0

// MARK: - Escena

struct Win {
    let title: String
    let tint: NSColor
    let lines: [CGFloat]   // anchos relativos de "líneas de contenido"
}

let columns: [[Win]] = [
    [Win(title: "Browser", tint: NSColor(calibratedRed: 0.35, green: 0.62, blue: 0.98, alpha: 1), lines: [0.9, 0.7, 0.8, 0.5]),
     Win(title: "Notes", tint: NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.35, alpha: 1), lines: [0.6, 0.8, 0.4])],
    [Win(title: "Editor", tint: NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.95, alpha: 1), lines: [0.5, 0.85, 0.7, 0.9, 0.6]),
     Win(title: "Terminal", tint: NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.60, alpha: 1), lines: [0.7, 0.4, 0.8, 0.3]),
     Win(title: "Docs", tint: NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.45, alpha: 1), lines: [0.8, 0.8, 0.6, 0.7])],
    [Win(title: "Chat", tint: NSColor(calibratedRed: 0.40, green: 0.80, blue: 0.95, alpha: 1), lines: [0.5, 0.3, 0.6, 0.4, 0.5])],
]

// Estado por columna: orden de la pila (índices en `columns[c]`, adelante → atrás).
struct Event {
    let time: Double
    let key: String
    let caption: String
    let column: Int?        // columna a la que salta el foco (focusColumn*)
    let cycle: Int?         // columna cuya pila cicla (cycleNext)
}

let events: [Event] = [
    Event(time: 1.2, key: "⌘ `", caption: "⌘`  trae al frente la ventana del fondo del tercio activo", column: nil, cycle: 1),
    Event(time: 2.7, key: "⌘ `", caption: "⌘`  otra vez: sigue ciclando la pila", column: nil, cycle: 1),
    Event(time: 4.3, key: "⌃ ⌘ ←", caption: "⌃⌘←  salta el foco al tercio de la izquierda", column: 0, cycle: nil),
    Event(time: 5.7, key: "⌘ `", caption: "⌘`  cada tercio tiene su propia pila", column: nil, cycle: 0),
    Event(time: 7.2, key: "⌘ `", caption: "⌘`  y vuelve: el resto de la pantalla no se mueve", column: nil, cycle: 0),
    Event(time: 8.8, key: "⌃ ⌘ →", caption: "⌃⌘→  de nuevo al centro", column: 1, cycle: nil),
    Event(time: 10.2, key: "⌘ `", caption: "⌘`  como tener tres monitores en uno", column: nil, cycle: 1),
]
let transition = 0.45

func easeInOut(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

/// Devuelve, para el instante t, el orden de pila de cada columna y la profundidad animada de cada ventana.
func state(at t: Double) -> (orders: [[Int]], depth: [[Double]], focus: Double, rising: [Int?], keyBadge: (String, Double)?, caption: String) {
    var orders = columns.map { Array(0..<$0.count) }
    var depth = columns.map { col in col.indices.map { Double($0) } }
    var focus = 1.0
    var rising: [Int?] = columns.map { _ in nil }
    var badge: (String, Double)? = nil
    var caption = "Tres tercios, tres pilas de ventanas"

    for e in events where t >= e.time {
        let p = easeInOut((t - e.time) / transition)
        if p < 1 { badge = (e.key, 1 - (t - e.time) / 1.1) } else if t - e.time < 1.1 { badge = (e.key, 1 - (t - e.time) / 1.1) }
        caption = e.caption
        if let c = e.column {
            let from = focus
            focus = from + (Double(c) - from) * p
        }
        if let c = e.cycle {
            var order = orders[c]
            let last = order.removeLast()
            let newOrder = [last] + order
            // profundidad interpolada: la del fondo sube a 0, el resto baja 1
            var d = [Double](repeating: 0, count: columns[c].count)
            for (newDepth, win) in newOrder.enumerated() {
                let oldDepth = Double(orders[c].firstIndex(of: win)!)
                d[win] = oldDepth + (Double(newDepth) - oldDepth) * p
            }
            depth[c] = d
            if p < 1 { rising[c] = last } else { rising[c] = nil }
            orders[c] = newOrder
        }
    }
    return (orders, depth, focus, rising, badge, caption)
}

// MARK: - Dibujo

func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawText(_ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, centered: Bool = false) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let sz = str.size()
    let origin = centered ? CGPoint(x: point.x - sz.width / 2, y: point.y) : point
    str.draw(at: origin)
}

func drawFrame(t: Double, ctx: CGContext) {
    let s = state(at: t)

    // Fondo
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.13, alpha: 1).cgColor,
                                 NSColor(calibratedRed: 0.14, green: 0.12, blue: 0.22, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

    // Título
    drawText("Stax", at: CGPoint(x: 40, y: H - 52), size: 26, weight: .bold, color: .white)
    drawText("cambiá de ventana por tercios en tu ultrawide", at: CGPoint(x: 112, y: H - 47), size: 15, weight: .regular, color: NSColor.white.withAlphaComponent(0.6))

    // Monitor
    let mon = CGRect(x: 40, y: 92, width: W - 80, height: 248)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    ctx.addPath(roundedPath(mon, 14))
    ctx.setFillColor(NSColor(calibratedWhite: 0.06, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    let screen = mon.insetBy(dx: 8, dy: 8)
    ctx.saveGState()
    ctx.addPath(roundedPath(screen, 8))
    ctx.clip()
    let wall = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(calibratedRed: 0.16, green: 0.14, blue: 0.40, alpha: 1).cgColor,
                                   NSColor(calibratedRed: 0.45, green: 0.22, blue: 0.62, alpha: 1).cgColor,
                                   NSColor(calibratedRed: 0.85, green: 0.40, blue: 0.45, alpha: 1).cgColor] as CFArray,
                          locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(wall, start: CGPoint(x: screen.minX, y: screen.minY), end: CGPoint(x: screen.maxX, y: screen.maxY), options: [])

    // Guías de tercios
    let colW = screen.width / 3
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    ctx.setLineWidth(1)
    ctx.setLineDash(phase: 0, lengths: [5, 5])
    for i in 1..<3 {
        let x = screen.minX + colW * CGFloat(i)
        ctx.move(to: CGPoint(x: x, y: screen.minY)); ctx.addLine(to: CGPoint(x: x, y: screen.maxY))
    }
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])

    // Foco: resplandor de la columna activa (interpolado)
    let fx = screen.minX + colW * CGFloat(s.focus)
    let focusRect = CGRect(x: fx + 4, y: screen.minY + 4, width: colW - 8, height: screen.height - 8)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18, color: NSColor(calibratedRed: 1, green: 0.85, blue: 0.4, alpha: 0.9).cgColor)
    ctx.addPath(roundedPath(focusRect, 8))
    ctx.setStrokeColor(NSColor(calibratedRed: 1, green: 0.85, blue: 0.4, alpha: 0.95).cgColor)
    ctx.setLineWidth(2.5)
    ctx.strokePath()
    ctx.restoreGState()

    // Ventanas por columna
    for c in 0..<3 {
        let colRect = CGRect(x: screen.minX + colW * CGFloat(c), y: screen.minY, width: colW, height: screen.height).insetBy(dx: 18, dy: 22)
        let wins = columns[c]
        // Dibujar de más profundo a más superficial; la que está subiendo se dibuja última.
        var order = wins.indices.sorted { s.depth[c][$0] > s.depth[c][$1] }
        if let r = s.rising[c] { order.removeAll { $0 == r }; order.append(r) }
        for w in order {
            let d = CGFloat(s.depth[c][w])
            let offset = d * 14
            let scale = 1 - d * 0.04
            let base = CGRect(x: colRect.minX + offset, y: colRect.minY + offset,
                              width: colRect.width * scale, height: colRect.height * scale)
            drawWindow(wins[w], in: base, depth: s.rising[c] == w ? 0 : d, ctx: ctx)
        }
    }
    ctx.restoreGState()

    // Badge de tecla
    if let (key, alpha) = s.keyBadge, alpha > 0 {
        let a = CGFloat(min(alpha * 2, 1))
        let pop = 1 + CGFloat(max(0, 0.12 - (1 - alpha) * 1.2))
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(a)]
        let str = NSAttributedString(string: key, attributes: attrs)
        let sz = str.size()
        let pill = CGRect(x: W / 2 - (sz.width + 36) * pop / 2, y: 30, width: (sz.width + 36) * pop, height: 44 * pop)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 12, color: NSColor.black.withAlphaComponent(0.5 * a).cgColor)
        ctx.addPath(roundedPath(pill, 12))
        ctx.setFillColor(NSColor(calibratedWhite: 0.12, alpha: a).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(roundedPath(pill, 12))
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25 * a).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        str.draw(at: CGPoint(x: pill.midX - sz.width / 2, y: pill.midY - sz.height / 2))
    }

    // Caption
    drawText(s.caption, at: CGPoint(x: W / 2, y: 6), size: 14, weight: .medium, color: NSColor.white.withAlphaComponent(0.75), centered: true)
}

func drawWindow(_ win: Win, in r: CGRect, depth: CGFloat, ctx: CGContext) {
    let dim = 1 - min(depth, 2) * 0.22
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(roundedPath(r, 8))
    ctx.setFillColor(NSColor(calibratedWhite: 0.97 * dim + 0.03, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Barra de título
    let bar = CGRect(x: r.minX, y: r.maxY - 22, width: r.width, height: 22)
    ctx.saveGState()
    ctx.addPath(roundedPath(r, 8)); ctx.clip()
    ctx.setFillColor(win.tint.withAlphaComponent(dim).cgColor)
    ctx.fill(bar)
    ctx.restoreGState()
    for (i, color) in [NSColor(calibratedRed: 1, green: 0.37, blue: 0.34, alpha: 1), NSColor(calibratedRed: 1, green: 0.74, blue: 0.18, alpha: 1), NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)].enumerated() {
        ctx.setFillColor(color.withAlphaComponent(dim).cgColor)
        ctx.fillEllipse(in: CGRect(x: bar.minX + 8 + CGFloat(i) * 12, y: bar.midY - 3.5, width: 7, height: 7))
    }
    drawText(win.title, at: CGPoint(x: bar.minX + 48, y: bar.minY + 4), size: 11, weight: .semibold, color: NSColor.black.withAlphaComponent(0.65 * dim))

    // Líneas de contenido
    var y = bar.minY - 16
    for width in win.lines {
        guard y > r.minY + 8 else { break }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.12 * dim).cgColor)
        ctx.addPath(roundedPath(CGRect(x: r.minX + 12, y: y, width: (r.width - 24) * width, height: 6), 3))
        ctx.fillPath()
        y -= 14
    }
    // Sombra de profundidad
    if depth > 0.01 {
        ctx.addPath(roundedPath(r, 8))
        ctx.setFillColor(NSColor.black.withAlphaComponent(min(depth, 2) * 0.12).cgColor)
        ctx.fillPath()
    }
}

// MARK: - Render a GIF

func renderFrame(t: Double) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    drawFrame(t: t, ctx: gc.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

let frameCount = Int(DURATION * FPS)
let url = URL(fileURLWithPath: "docs/stax-demo.gif")
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for i in 0..<frameCount {
    let t = Double(i) / FPS
    let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / FPS]] as CFDictionary
    CGImageDestinationAddImage(dest, renderFrame(t: t), frameProps)
}
CGImageDestinationFinalize(dest)

if CommandLine.arguments.count > 1 {
    for (i, arg) in CommandLine.arguments.dropFirst().enumerated() {
        let rep = NSBitmapImageRep(cgImage: renderFrame(t: Double(arg)!))
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-eugeniovaleiras-workspace-macos/37e6ab6f-e3e1-45a3-8070-c63044cf10a3/scratchpad/frame-\(i).png"))
    }
}
print("docs/stax-demo.gif: \(frameCount) frames")
