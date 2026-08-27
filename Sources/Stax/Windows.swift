import AppKit
import ApplicationServices

/// Una ventana visible en el escritorio actual. Coordenadas en el sistema de CoreGraphics
/// (origen arriba a la izquierda de la pantalla principal), igual que Accessibility.
struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let ownerName: String
    let bounds: CGRect

    var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }
}

enum Screens {
    /// Alto de la pantalla principal en puntos; sirve para convertir entre coordenadas Cocoa y CG.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func toCG(_ cocoaRect: CGRect) -> CGRect {
        CGRect(x: cocoaRect.minX, y: primaryHeight - cocoaRect.maxY, width: cocoaRect.width, height: cocoaRect.height)
    }

    static func toCG(_ cocoaPoint: CGPoint) -> CGPoint {
        CGPoint(x: cocoaPoint.x, y: primaryHeight - cocoaPoint.y)
    }

    /// Frames de todas las pantallas en coordenadas CG.
    static var framesCG: [CGRect] {
        NSScreen.screens.map { toCG($0.frame) }
    }

    static func screen(containing point: CGPoint) -> CGRect? {
        framesCG.first { $0.contains(point) } ?? framesCG.first
    }

    static var pointerCG: CGPoint { toCG(NSEvent.mouseLocation) }
}

enum WindowLister {
    /// Ventanas normales visibles en el escritorio actual, ordenadas de adelante hacia atrás.
    static func onScreenWindows(minimumSize: Double) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPID = getpid()
        var policyCache: [pid_t: Bool] = [:]
        func isRegularApp(_ pid: pid_t) -> Bool {
            if let cached = policyCache[pid] { return cached }
            let regular = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
            policyCache[pid] = regular
            return regular
        }

        var result: [WindowInfo] = []
        for entry in raw {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }

            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.05 else { continue }
            guard bounds.width >= minimumSize, bounds.height >= minimumSize else { continue }
            guard isRegularApp(pid) else { continue }

            let owner = entry[kCGWindowOwnerName as String] as? String ?? "pid \(pid)"
            result.append(WindowInfo(id: id, pid: pid, ownerName: owner, bounds: bounds))
        }
        return result
    }
}

struct ColumnLayout {
    let screen: CGRect
    let columns: Int

    var columnWidth: CGFloat { screen.width / CGFloat(max(columns, 1)) }

    func column(containing x: CGFloat) -> Int {
        let index = Int((x - screen.minX) / columnWidth)
        return min(max(index, 0), columns - 1)
    }

    func column(of window: WindowInfo) -> Int {
        column(containing: window.center.x)
    }

    func frame(ofColumn index: Int) -> CGRect {
        CGRect(x: screen.minX + CGFloat(index) * columnWidth, y: screen.minY, width: columnWidth, height: screen.height)
    }
}

enum FocusedWindow {
    /// Frame (en CG) de la ventana que tiene el foco del teclado, vía Accessibility.
    static func frame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value else { return nil }
        let window = value as! AXUIElement
        return AX.frame(of: window)
    }
}

enum AX {
    static func frame(of element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posValue, let sizeValue else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    static func windows(ofApp pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list
    }
}
