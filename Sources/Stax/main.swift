import AppKit
import ApplicationServices

// Uso:
//   Stax                 → app de barra de menú con los atajos globales
//   Stax --verbose       → ídem, logueando atajos y acciones a stderr
//   Stax list            → imprime las ventanas por columna y sale
//   Stax do <acción> [N] → ejecuta cycleNext | cyclePrev | focusColumnLeft | focusColumnRight | moveToColumn
//                                 (N = columna 1-based sobre la que actuar; por defecto, la de la ventana con foco)
//   Stax screenshot-menu <png> → abre el menú de la barra, lo captura en <png> y sale (para la documentación)

var arguments = Array(CommandLine.arguments.dropFirst())
if let i = arguments.firstIndex(of: "--verbose") {
    Log.verbose = true
    arguments.remove(at: i)
}

var config = Config.load()
if config.verbose {
    Log.verbose = true
    Log.enableFileLogging()
}
let controller = Controller(config: config)

func describe(_ layout: ColumnLayout, stacks: [[WindowInfo]], highlight: Int?) -> String {
    var lines = ["Pantalla \(Int(layout.screen.width))×\(Int(layout.screen.height)) @ (\(Int(layout.screen.minX)),\(Int(layout.screen.minY))) — \(layout.columns) columnas de \(Int(layout.columnWidth)) pt"]
    for (index, stack) in stacks.enumerated() {
        lines.append("\(index == highlight ? "▶" : " ") Columna \(index + 1):")
        if stack.isEmpty { lines.append("     (vacía)") }
        for (pos, w) in stack.enumerated() {
            lines.append(String(format: "     %@ %@ #%d  [%d,%d %dx%d]", pos == 0 ? "●" : "○", w.ownerName, w.id,
                                Int(w.bounds.minX), Int(w.bounds.minY), Int(w.bounds.width), Int(w.bounds.height)))
        }
    }
    return lines.joined(separator: "\n")
}

switch arguments.first {
case "list":
    guard let target = controller.target() else { print("No pude determinar la pantalla."); exit(1) }
    print(describe(target.layout, stacks: controller.stacks(in: target.layout), highlight: target.column))
    exit(0)

case "do":
    guard arguments.count >= 2, let action = Action(rawValue: arguments[1]) else {
        print("Uso: Stax do cycleNext|cyclePrev|focusColumnLeft|focusColumnRight|moveToColumn [columna]")
        exit(2)
    }
    Log.verbose = true
    if !AXIsProcessTrusted() {
        Log.warn("este binario no tiene permiso de Accesibilidad; pruebo igual con SkyLight")
    }
    let column = arguments.count >= 3 ? Int(arguments[2]).map { $0 - 1 } : nil
    controller.perform(action, column: column)
    // Dejamos correr el run loop un instante para que los eventos se entreguen.
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    exit(0)

default:
    break
}

// MARK: - App de barra de menú

let screenshotPath: String? = arguments.first == "screenshot-menu" && arguments.count >= 2 ? arguments[1] : nil

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenu?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) {
            Log.warn("falta permiso de Accesibilidad: Ajustes → Privacidad y seguridad → Accesibilidad")
        }
        if !WindowFocuser.shared.privateAPIAvailable {
            Log.warn("API privada de SkyLight no disponible; uso fallback de Accessibility")
        }

        statusMenu = StatusMenu(controller: controller) { [weak self] in self?.reloadConfig() }
        installHotkeys()

        if let screenshotPath {
            statusMenu?.captureMenu(to: screenshotPath)
            return
        }

        // Si todavía no hay permiso, reintentamos hasta que el usuario lo otorgue.
        if !HotkeyManager.shared.isInstalled {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                Log.info("permiso de Accesibilidad otorgado; instalo los atajos")
                self?.installHotkeys()
                if HotkeyManager.shared.isInstalled { timer.invalidate() }
            }
        }
    }

    private func installHotkeys() {
        let manager = HotkeyManager.shared
        manager.hotkeys = controller.config.hotkeys
        manager.onHotkey = { hotkey in controller.perform(hotkey) }
        if !manager.hotkeys.isEmpty { _ = manager.install() }
    }

    private func reloadConfig() {
        controller.config = Config.load()
        if controller.config.verbose {
            Log.verbose = true
            Log.enableFileLogging()
        }
        installHotkeys()
        Log.info("config recargada: \(controller.config)")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
