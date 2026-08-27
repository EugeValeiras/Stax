// Genera las animaciones de docs/ (dibujadas con CoreGraphics, sin grabar pantalla).
// Uso: swift scripts/make-demo.swift [cycle|focus|move ...]   (sin argumentos genera las tres)
//      STAX_DEMO_STILLS="1.4,3.0" swift scripts/make-demo.swift cycle   → exporta frames PNG a /tmp para revisar
import AppKit
import ImageIO
import UniformTypeIdentifiers

let W: CGFloat = 960, H: CGFloat = 400
let FPS = 20.0

// MARK: - Escena

struct Win {
    let title: String
    let tint: NSColor
    let lines: [CGFloat]   // anchos relativos de "líneas de contenido"
    let column: Int        // columna inicial
}

let windows: [Win] = [
    Win(title: "Browser", tint: NSColor(calibratedRed: 0.35, green: 0.62, blue: 0.98, alpha: 1), lines: [0.9, 0.7, 0.8, 0.5], column: 0),
    Win(title: "Notes", tint: NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.35, alpha: 1), lines: [0.6, 0.8, 0.4], column: 0),
    Win(title: "Editor", tint: NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.95, alpha: 1), lines: [0.5, 0.85, 0.7, 0.9, 0.6], column: 1),
    Win(title: "Terminal", tint: NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.60, alpha: 1), lines: [0.7, 0.4, 0.8, 0.3], column: 1),
    Win(title: "Docs", tint: NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.45, alpha: 1), lines: [0.8, 0.8, 0.6, 0.7], column: 1),
    Win(title: "Chat", tint: NSColor(calibratedRed: 0.40, green: 0.80, blue: 0.95, alpha: 1), lines: [0.5, 0.3, 0.6, 0.4, 0.5], column: 2),
]

enum Kind {
    case cycle          // ⌘`: la del fondo de la columna activa pasa al frente
    case focus(Int)     // ⌃⌘←/→: el foco salta a otra columna
    case move(Int)      // ⌃⌥D/F/G: la ventana frontal de la columna activa se muda a otra columna
}

struct Event {
    let time: Double
    let key: String
    let caption: String
    let kind: Kind
}

struct Demo {
    let name: String
    let subtitle: String
    let idleCaption: String
    let duration: Double
    let events: [Event]
}

let demos: [Demo] = [
    Demo(name: "cycle", subtitle: "cambiá de ventana dentro del tercio activo", idleCaption: "Tres ventanas apiladas en el tercio del medio", duration: 5.6, events: [
        Event(time: 1.0, key: "⌘ `", caption: "⌘`  trae al frente la ventana del fondo de la pila", kind: .cycle),
        Event(time: 2.5, key: "⌘ `", caption: "⌘`  otra vez: sigue ciclando", kind: .cycle),
        Event(time: 4.0, key: "⌘ `", caption: "⌘`  sólo se mueve el tercio activo; ⌘⇧` va al revés", kind: .cycle),
    ]),
    Demo(name: "focus", subtitle: "saltá de tercio como si fuera otro monitor", idleCaption: "El foco está en el tercio del medio", duration: 6.6, events: [
        Event(time: 1.0, key: "⌃ ⌘ ←", caption: "⌃⌘←  salta el foco al tercio de la izquierda", kind: .focus(0)),
        Event(time: 2.4, key: "⌘ `", caption: "⌘`  cicla la pila de ese tercio", kind: .cycle),
        Event(time: 3.8, key: "⌘ `", caption: "⌘`  el resto de la pantalla no se mueve", kind: .cycle),
        Event(time: 5.2, key: "⌃ ⌘ →", caption: "⌃⌘→  y vuelve al centro", kind: .focus(1)),
    ]),
    Demo(name: "move", subtitle: "acomodá la ventana en un tercio", idleCaption: "La ventana con foco es Editor, en el medio", duration: 6.6, events: [
        Event(time: 1.0, key: "⌃ ⌥ G", caption: "⌃⌥G  la lleva al tercer tercio", kind: .move(2)),
        Event(time: 2.8, key: "⌃ ⌥ D", caption: "⌃⌥D  al primero", kind: .move(0)),
        Event(time: 4.6, key: "⌃ ⌥ F", caption: "⌃⌥F  y al medio. Chau, Rectangle.", kind: .move(1)),
    ]),
]

var demo = demos[0]
var events: [Event] { demo.events }

let transition = 0.45
let moveTransition = 0.6

func easeInOut(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

struct Moving {
    let window: Int
    let from: Int
    let to: Int
    let progress: Double
}

struct Scene {
    var column: [Int]          // columna actual de cada ventana
    var depth: [Double]        // profundidad animada (0 = frontal)
    var focus: Double          // columna con foco (interpolada)
    var rising: Int?           // ventana que está subiendo en un ⌘` (se dibuja última)
    var moving: Moving?        // ventana en tránsito entre columnas
    var keyBadge: (String, Double)?
    var caption: String
}

func scene(at t: Double) -> Scene {
    var orders: [[Int]] = (0..<3).map { c in windows.indices.filter { windows[$0].column == c } }
    var column = windows.map(\.column)
    var depth = windows.indices.map { Double(orders[windows[$0].column].firstIndex(of: $0)!) }
    var focus = 1.0
    var rising: Int? = nil
    var moving: Moving? = nil
    var badge: (String, Double)? = nil
    var caption = demo.idleCaption

    for e in events where t >= e.time {
        let elapsed = t - e.time
        if elapsed < 1.1 { badge = (e.key, 1 - elapsed / 1.1) }
        caption = e.caption
        let activeColumn = Int(focus.rounded())

        switch e.kind {
        case .focus(let c):
            let p = easeInOut(elapsed / transition)
            focus += (Double(c) - focus) * p

        case .cycle:
            let p = easeInOut(elapsed / transition)
            let c = activeColumn
            var order = orders[c]
            let last = order.removeLast()
            let newOrder = [last] + order
            for (newDepth, w) in newOrder.enumerated() {
                let oldDepth = Double(orders[c].firstIndex(of: w)!)
                depth[w] = oldDepth + (Double(newDepth) - oldDepth) * p
            }
            rising = p < 1 ? last : nil
            orders[c] = newOrder

        case .move(let to):
            let p = easeInOut(elapsed / moveTransition)
            let from = activeColumn
            let w = orders[from].removeFirst()
            for (i, other) in orders[from].enumerated() {           // los de atrás suben un lugar
                depth[other] = Double(i + 1) + (Double(i) - Double(i + 1)) * p
            }
            for (i, other) in orders[to].enumerated() {             // los del destino bajan un lugar
                depth[other] = Double(i) + (Double(i + 1) - Double(i)) * p
            }
            orders[to].insert(w, at: 0)
            depth[w] = 0
            column[w] = p < 1 ? from : to
            moving = p < 1 ? Moving(window: w, from: from, to: to, progress: p) : nil
            focus += (Double(to) - focus) * p
        }
    }
    return Scene(column: column, depth: depth, focus: focus, rising: rising, moving: moving, keyBadge: badge, caption: caption)
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
    let s = scene(at: t)

    // Fondo
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.13, alpha: 1).cgColor,
                                 NSColor(calibratedRed: 0.14, green: 0.12, blue: 0.22, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

    // Título
    drawText("Stax", at: CGPoint(x: 40, y: H - 52), size: 26, weight: .bold, color: .white)
    drawText(demo.subtitle, at: CGPoint(x: 112, y: H - 47), size: 15, weight: .regular, color: NSColor.white.withAlphaComponent(0.6))

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
    func columnRect(_ c: Int) -> CGRect {
        CGRect(x: screen.minX + colW * CGFloat(c), y: screen.minY, width: colW, height: screen.height).insetBy(dx: 18, dy: 22)
    }
    func windowRect(column c: Int, depth d: CGFloat) -> CGRect {
        let colRect = columnRect(c)
        let offset = d * 14
        let scale = 1 - d * 0.04
        return CGRect(x: colRect.minX + offset, y: colRect.minY + offset, width: colRect.width * scale, height: colRect.height * scale)
    }
    for c in 0..<3 {
        var members = windows.indices.filter { s.column[$0] == c && s.moving?.window != $0 }
        members.sort { s.depth[$0] > s.depth[$1] }
        if let r = s.rising, let i = members.firstIndex(of: r) { members.remove(at: i); members.append(r) }
        for w in members {
            let d = CGFloat(s.depth[w])
            drawWindow(windows[w], in: windowRect(column: c, depth: d), depth: s.rising == w ? 0 : d, ctx: ctx)
        }
    }
    // Ventana en tránsito: se dibuja encima de todo, interpolando entre columnas con un pequeño "salto".
    if let m = s.moving {
        let a = windowRect(column: m.from, depth: 0)
        let b = windowRect(column: m.to, depth: 0)
        let p = CGFloat(m.progress)
        let lift = 1 + 0.05 * sin(Double(p) * .pi)
        var r = CGRect(x: a.minX + (b.minX - a.minX) * p, y: a.minY + (b.minY - a.minY) * p,
                       width: a.width + (b.width - a.width) * p, height: a.height + (b.height - a.height) * p)
        r = r.insetBy(dx: -r.width * (lift - 1) / 2, dy: -r.height * (lift - 1) / 2)
        drawWindow(windows[m.window], in: r, depth: 0, ctx: ctx)
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

let requested = Array(CommandLine.arguments.dropFirst())
let selected = requested.isEmpty ? demos : demos.filter { requested.contains($0.name) }
let stills = (ProcessInfo.processInfo.environment["STAX_DEMO_STILLS"] ?? "").split(separator: ",").compactMap { Double($0) }

for d in selected {
    demo = d
    let frameCount = Int(d.duration * FPS)
    let url = URL(fileURLWithPath: "docs/demo-\(d.name).gif")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for i in 0..<frameCount {
        let t = Double(i) / FPS
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / FPS]] as CFDictionary
        CGImageDestinationAddImage(dest, renderFrame(t: t), frameProps)
    }
    CGImageDestinationFinalize(dest)
    for (i, t) in stills.enumerated() {
        let rep = NSBitmapImageRep(cgImage: renderFrame(t: t))
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/stax-\(d.name)-\(i).png"))
    }
    print("docs/demo-\(d.name).gif: \(frameCount) frames")
}
