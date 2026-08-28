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
        menu.addItem(disabled(ShareMirror.hasPermission ? "Grabación de pantalla: OK" : "Grabación de pantalla: falta permiso (para compartir) ⚠️"))
        for hotkey in config.hotkeys {
            menu.addItem(disabled("   \(hotkey.description)  →  \(hotkey.actionDescription)"))
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
                        // Con ⌥ apretada, la misma entrada comparte esa ventana en vez de traerla al frente.
                        let share = NSMenuItem(title: "Compartir \(window.ownerName)", action: #selector(shareWindow(_:)), keyEquivalent: "")
                        share.target = self
                        share.representedObject = WindowBox(window)
                        share.keyEquivalentModifierMask = [.option]
                        share.isAlternate = true
                        submenu.addItem(share)
                    }
                }
                submenu.addItem(.separator())
                let move = NSMenuItem(title: "Mover la ventana con foco acá", action: #selector(moveHere(_:)), keyEquivalent: "")
                move.target = self
                move.tag = index
                submenu.addItem(move)
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

        menu.addItem(.separator())
        let shareItem = NSMenuItem(title: "Compartir la ventana con foco", action: #selector(shareFocused), keyEquivalent: "")
        shareItem.target = self
        menu.addItem(shareItem)

        if let source = ShareMirror.shared.source {
            let title = source.title.map { ": \($0)" } ?? ""
            menu.addItem(disabled("   Compartiendo por el espejo — \(source.ownerName)\(title)"))
        } else if let sharing = Bridge.shared.state.sharingDescription {
            menu.addItem(disabled("   Transmitiendo en Discord — \(sharing)"))
        }
        if controller.isSharing {
            menu.addItem(withTitle: "Dejar de compartir", action: #selector(stopSharing), keyEquivalent: "").target = self
        }

        let follow = NSMenuItem(title: "Seguir la ventana con foco", action: #selector(toggleFollow), keyEquivalent: "")
        follow.target = self
        follow.state = config.shareFollowsFocus ? .on : .off
        menu.addItem(follow)

        let backendItem = NSMenuItem(title: "Compartir por", action: nil, keyEquivalent: "")
        let backendMenu = NSMenu()
        for backend in ShareBackend.allCases {
            let entry = NSMenuItem(title: backend.label, action: #selector(setBackend(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = backend.rawValue
            entry.state = backend == config.shareBackend ? .on : .off
            backendMenu.addItem(entry)
        }
        backendMenu.addItem(.separator())
        backendMenu.addItem(disabled(bridgeStatus()))
        backendItem.submenu = backendMenu
        menu.addItem(backendItem)

        let virtual = NSMenuItem(title: "Espejo en una pantalla virtual", action: #selector(toggleVirtualDisplay), keyEquivalent: "")
        virtual.target = self
        virtual.state = config.shareUsesVirtualDisplay ? .on : .off
        virtual.isEnabled = VirtualDisplay.isAvailable
        if !VirtualDisplay.isAvailable {
            virtual.title = "Espejo en una pantalla virtual (no disponible en este macOS)"
        }
        menu.addItem(virtual)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Asistente de configuración…", action: #selector(openSetup), keyEquivalent: "").target = self
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

    /// Una línea que explica en qué anda el puente con Discord, para no tener que ir al log.
    private func bridgeStatus() -> String {
        let state = Bridge.shared.state
        guard state.connected else { return "Plugin StaxBridge: no conectado" }
        return state.inVoice ? "Plugin StaxBridge: listo (en un canal de voz)"
                             : "Plugin StaxBridge: conectado, sin canal de voz"
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

    @objc private func moveHere(_ sender: NSMenuItem) {
        controller.perform(.moveToColumn, column: sender.tag)
    }

    @objc private func shareWindow(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? WindowBox else { return }
        controller.share(box.window)
    }

    @objc private func shareFocused() {
        // El menú ya se cerró y el foco volvió a la app de antes cuando corre esta acción.
        controller.perform(.shareFocusedWindow)
    }

    @objc private func stopSharing() { controller.perform(.stopSharing) }

    @objc private func toggleFollow() { controller.perform(.toggleFollowFocus) }

    @objc private func setColumns(_ sender: NSMenuItem) {
        controller.config.columns = sender.tag
        controller.config.save()
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ColumnSelection(rawValue: raw) else { return }
        controller.config.columnSelection = mode
        controller.config.save()
    }

    @objc private func toggleVirtualDisplay() {
        controller.config.shareUsesVirtualDisplay.toggle()
        controller.config.save()
        // El cambio se aplica al próximo ⌃⌥S; si hay algo compartiéndose ahora, lo movemos ya.
        if let source = ShareMirror.shared.source {
            ShareMirror.shared.stop()
            controller.share(source)
        }
        Log.info("espejo en pantalla virtual: \(controller.config.shareUsesVirtualDisplay)")
    }

    @objc private func setBackend(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let backend = ShareBackend(rawValue: raw) else { return }
        controller.config.shareBackend = backend
        controller.config.save()
        Log.info("compartir por: \(backend.rawValue)")
    }

    @objc private func openSetup() {
        SetupWizard.shared.present(controller: controller)
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
