import AppKit

final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let controller: Controller
    private let onReload: () -> Void

    init(controller: Controller, onReload: @escaping () -> Void) {
        self.controller = controller
        self.onReload = onReload
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Stax")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let config = controller.config

        menu.addItem(disabled(AXIsProcessTrusted() ? "Accesibilidad: OK" : "Accesibilidad: falta permiso ⚠️"))
        menu.addItem(disabled(HotkeyManager.shared.isInstalled ? "Atajos: activos" : "Atajos: no instalados ⚠️"))
        for hotkey in config.hotkeys {
            menu.addItem(disabled("   \(hotkey.description)  →  \(hotkey.action.rawValue)"))
        }
        menu.addItem(.separator())

        if let target = controller.target() {
            let stacks = controller.stacks(in: target.layout)
            for (index, stack) in stacks.enumerated() {
                let marker = index == target.column ? "▶ " : "   "
                let item = NSMenuItem(title: "\(marker)Columna \(index + 1)", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                if stack.isEmpty {
                    submenu.addItem(disabled("(vacía)"))
                } else {
                    for (pos, window) in stack.enumerated() {
                        let entry = NSMenuItem(title: "\(pos == 0 ? "● " : "○ ")\(window.ownerName)", action: #selector(raiseWindow(_:)), keyEquivalent: "")
                        entry.target = self
                        entry.representedObject = WindowBox(window)
                        submenu.addItem(entry)
                    }
                }
                item.submenu = submenu
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let columnsItem = NSMenuItem(title: "Columnas", action: nil, keyEquivalent: "")
        let columnsMenu = NSMenu()
        for n in 2...4 {
            let entry = NSMenuItem(title: "\(n)", action: #selector(setColumns(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = n
            entry.state = n == config.columns ? .on : .off
            columnsMenu.addItem(entry)
        }
        columnsItem.submenu = columnsMenu
        menu.addItem(columnsItem)

        let modeItem = NSMenuItem(title: "Columna objetivo", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for (title, mode) in [("Ventana con foco", ColumnSelection.focused), ("Bajo el puntero", ColumnSelection.pointer)] {
            let entry = NSMenuItem(title: title, action: #selector(setMode(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = mode.rawValue
            entry.state = mode == config.columnSelection ? .on : .off
            modeMenu.addItem(entry)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(withTitle: "Abrir config.json", action: #selector(openConfig), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Recargar config", action: #selector(reload), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de Stax", action: #selector(quit), keyEquivalent: "q").target = self
    }

    /// Abre el menú, captura su ventana (propia, no requiere permiso de grabación) y termina la app.
    func captureMenu(to path: String) {
        // El menú se abre de forma modal; el timer en .common corre igual durante el tracking.
        let timer = Timer(timeInterval: 0.8, repeats: false) { [weak self] _ in
            defer { exit(0) }
            let own = getpid()
            guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
                Log.warn("captura: no pude listar ventanas"); return
            }
            let menuWindows = list.filter {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == own && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0
            }
            guard let window = menuWindows.first, let id = window[kCGWindowNumber as String] as? UInt32 else {
                Log.warn("captura: no encontré la ventana del menú"); return
            }
            guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.bestResolution, .boundsIgnoreFraming]) else {
                Log.warn("captura: CGWindowListCreateImage falló"); return
            }
            let rep = NSBitmapImageRep(cgImage: image)
            do {
                try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
                Log.info("captura guardada en \(path) (\(image.width)×\(image.height))")
            } catch {
                Log.warn("captura: \(error)")
            }
            self?.statusItem.menu?.cancelTracking()
        }
        RunLoop.main.add(timer, forMode: .common)
        statusItem.button?.performClick(nil)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func raiseWindow(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? WindowBox else { return }
        WindowFocuser.shared.raise(box.window, onlyThisWindow: controller.config.raiseOnlyTargetWindow)
    }

    @objc private func setColumns(_ sender: NSMenuItem) {
        controller.config.columns = sender.tag
        controller.config.save()
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ColumnSelection(rawValue: raw) else { return }
        controller.config.columnSelection = mode
        controller.config.save()
    }

    @objc private func openConfig() {
        controller.config.saveIfMissing()
        NSWorkspace.shared.open(Config.fileURL)
    }

    @objc private func reload() { onReload() }

    @objc private func quit() { NSApp.terminate(nil) }
}

private final class WindowBox: NSObject {
    let window: WindowInfo
    init(_ window: WindowInfo) { self.window = window }
}
