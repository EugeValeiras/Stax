import AppKit

/// Une atajo → columna objetivo → pila de ventanas → acción.
final class Controller {
    var config: Config

    init(config: Config) {
        self.config = config
    }

    // MARK: - Columna objetivo

    struct Target {
        let layout: ColumnLayout
        let column: Int
    }

    func target() -> Target? {
        if config.columnSelection == .focused, let frame = FocusedWindow.frame() {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            guard let screen = Screens.screen(containing: center) else { return nil }
            let layout = ColumnLayout(screen: screen, columns: config.columns)
            return Target(layout: layout, column: layout.column(containing: center.x))
        }
        if config.columnSelection == .focused {
            Log.info("no hay ventana con foco; uso el puntero")
        }
        let pointer = Screens.pointerCG
        guard let screen = Screens.screen(containing: pointer) else { return nil }
        let layout = ColumnLayout(screen: screen, columns: config.columns)
        return Target(layout: layout, column: layout.column(containing: pointer.x))
    }

    /// Pila de ventanas (adelante → atrás) de una columna de una pantalla.
    func stack(in layout: ColumnLayout, column: Int) -> [WindowInfo] {
        WindowLister.onScreenWindows(minimumSize: config.minimumWindowSize)
            .filter { layout.screen.contains($0.center) && layout.column(of: $0) == column }
    }

    func stacks(in layout: ColumnLayout) -> [[WindowInfo]] {
        let windows = WindowLister.onScreenWindows(minimumSize: config.minimumWindowSize)
            .filter { layout.screen.contains($0.center) }
        return (0..<layout.columns).map { col in windows.filter { layout.column(of: $0) == col } }
    }

    // MARK: - Acciones

    func perform(_ hotkey: Hotkey) {
        perform(hotkey.action, column: hotkey.column.map { $0 - 1 })
    }

    func perform(_ action: Action, column override: Int? = nil) {
        guard let target = target() else {
            Log.warn("no pude determinar la pantalla/columna objetivo")
            return
        }
        var column = override ?? target.column

        if action == .moveToColumn {
            moveFocusedWindow(to: column, in: target.layout)
            return
        }

        switch action {
        case .focusColumnLeft:
            guard column > 0 else { Log.info("ya estoy en la primera columna"); return }
            column -= 1
        case .focusColumnRight:
            guard column < target.layout.columns - 1 else { Log.info("ya estoy en la última columna"); return }
            column += 1
        default:
            break
        }

        let stack = stack(in: target.layout, column: column)
        Log.info("columna \(column + 1)/\(target.layout.columns): \(stack.map { "\($0.ownerName)#\($0.id)" })")
        guard !stack.isEmpty else { return }

        let focuser = WindowFocuser.shared
        let only = config.raiseOnlyTargetWindow

        switch action {
        case .focusColumnLeft, .focusColumnRight:
            focuser.raise(stack[0], onlyThisWindow: only)

        case .cycleNext:
            // La del fondo pasa al frente: [A,B,C] → [C,A,B]
            focuser.raise(stack[stack.count - 1], onlyThisWindow: only)

        case .cyclePrev:
            // La frontal se va al fondo: [A,B,C] → [B,C,A]. Se logra subiendo C y luego B.
            if stack.count <= 2 {
                focuser.raise(stack[stack.count - 1], onlyThisWindow: only)
            } else {
                for window in stack[1...].reversed() {
                    focuser.raise(window, onlyThisWindow: only)
                }
            }

        case .moveToColumn:
            break // manejado arriba
        }
    }

    /// Mueve la ventana con foco a una columna (0-based) de la pantalla donde está.
    func moveFocusedWindow(to column: Int, in layout: ColumnLayout) {
        let column = min(max(column, 0), layout.columns - 1)
        guard let window = FocusedWindow.element() else {
            Log.warn("no hay ventana con foco para mover")
            return
        }
        let frame = layout.frame(ofColumn: column)
        let ok = AX.setFrame(frame, of: window)
        Log.info("mover ventana con foco → columna \(column + 1): \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height)) \(ok ? "OK" : "falló")")
    }
}
