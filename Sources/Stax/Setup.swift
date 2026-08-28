import AppKit
import ServiceManagement

/// Asistente de configuración: aparece la primera vez que arranca Stax y se puede volver a abrir desde el
/// menú ⫼. Recorre lo que hace falta para que la app sirva — permisos, columnas y cómo se comparte —
/// guardando cada cambio en el momento, así cerrarlo a la mitad nunca deja la config peor que antes.
final class SetupWizard: NSObject, NSWindowDelegate {
    static let shared = SetupWizard()

    // Fuerte a propósito: el Controller es global y vive toda la sesión; no hay ciclo porque no nos conoce.
    private var controller: Controller!
    private var window: NSWindow?
    private var contentBox: NSView?
    private var titleLabel: NSTextField?
    private var subtitleLabel: NSTextField?
    private var stepLabel: NSTextField?
    private var backButton: NSButton?
    private var nextButton: NSButton?
    private var permissionTimer: Timer?
    private var index = 0

    private struct Page {
        let title: String
        let subtitle: String
        let build: (SetupWizard) -> NSView
    }

    private let pages: [Page] = [
        Page(title: "Bienvenido a Stax",
             subtitle: "Tu ultrawide, dividido en tercios que funcionan como monitores aparte.",
             build: { $0.makeWelcomePage() }),
        Page(title: "Permisos",
             subtitle: "macOS pide dos permisos para que Stax pueda hacer su trabajo.",
             build: { $0.makePermissionsPage() }),
        Page(title: "Columnas",
             subtitle: "En cuántas partes se divide cada pantalla, y cuál es la columna activa.",
             build: { $0.makeColumnsPage() }),
        Page(title: "Compartir en videollamadas",
             subtitle: "⌃⌥S cambia la ventana que estás mostrando, sin tocar la llamada.",
             build: { $0.makeSharePage() }),
        Page(title: "Todo listo",
             subtitle: "Estos son los atajos que quedaron activos.",
             build: { $0.makeFinishPage() }),
    ]

    private override init() {}

    // MARK: - Presentación

    func present(controller: Controller) {
        self.controller = controller
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Configuración de Stax"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentView = makeChrome()
        self.window = window

        index = 0
        showPage()          // deja la ventana con el alto del primer paso
        window.center()
        NSApp.activate(ignoringOtherApps: true)

        let destination = window.frame
        window.setFrame(destination.insetBy(dx: 14, dy: 10), display: false)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(destination, display: true)
        }
    }

    /// Cierra con un fundido corto, para no cortar de golpe cuando terminás el asistente.
    private func closeWithAnimation() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            window.animator().alphaValue = 0
        }, completionHandler: { window.close() })
    }

    func windowWillClose(_ notification: Notification) {
        stopPermissionTimer()
        window = nil
        contentBox = nil
        // Cerrarlo cuenta como haberlo visto: si no, volvería a aparecer en cada arranque.
        markCompleted()
    }

    private func markCompleted() {
        guard !controller.config.setupCompleted else { return }
        controller.config.setupCompleted = true
        controller.config.save()
    }

    // MARK: - Estructura de la ventana

    /// Encabezado (título + paso), el área que cambia por página, y los botones de abajo.
    private func makeChrome() -> NSView {
        let root = NSView()

        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        let step = NSTextField(labelWithString: "")
        step.font = .systemFont(ofSize: 11, weight: .medium)
        step.textColor = .tertiaryLabelColor

        let box = NSView()
        let separator = NSBox()
        separator.boxType = .separator

        let back = NSButton(title: "Atrás", target: self, action: #selector(goBack))
        back.bezelStyle = .rounded
        let next = NSButton(title: "Siguiente", target: self, action: #selector(goNext))
        next.bezelStyle = .rounded
        next.keyEquivalent = "\r"

        for view in [title, subtitle, step, box, separator, back, next] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            step.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            step.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: step.trailingAnchor),

            box.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 20),
            box.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: step.trailingAnchor),
            box.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -16),

            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: next.topAnchor, constant: -14),

            next.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            next.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            next.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            back.trailingAnchor.constraint(equalTo: next.leadingAnchor, constant: -10),
            back.centerYAnchor.constraint(equalTo: next.centerYAnchor),
            back.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])

        titleLabel = title
        subtitleLabel = subtitle
        stepLabel = step
        contentBox = box
        backButton = back
        nextButton = next
        return root
    }

    /// Cambia de página. `direction` es +1 al avanzar, -1 al volver y 0 al abrir: las filas entran
    /// desde ese lado, escalonadas, mientras la página anterior se va para el opuesto.
    private func showPage(direction: CGFloat = 0) {
        guard let contentBox else { return }
        stopPermissionTimer()

        // La saliente se va sola; la sacamos de la jerarquía recién cuando terminó de irse. Antes la
        // desenganchamos de Auto Layout conservando su frame, para que no siga fijando el alto.
        NSLayoutConstraint.deactivate(pageConstraints)
        pageConstraints = []
        for old in contentBox.subviews {
            let frame = old.frame
            old.translatesAutoresizingMaskIntoConstraints = true
            old.frame = frame
            Animate.exit(old, dx: -direction * 26) { [weak old] in old?.removeFromSuperview() }
        }

        let page = pages[index]
        Animate.crossfade(titleLabel, to: page.title)
        Animate.crossfade(subtitleLabel, to: page.subtitle)
        Animate.crossfade(stepLabel, to: "Paso \(index + 1) de \(pages.count)")
        backButton?.isHidden = index == 0
        nextButton?.title = index == pages.count - 1 ? "Empezar a usar Stax" : "Siguiente"

        let view = page.build(self)
        view.translatesAutoresizingMaskIntoConstraints = false
        contentBox.addSubview(view)
        pageConstraints = [
            view.topAnchor.constraint(equalTo: contentBox.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentBox.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentBox.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentBox.bottomAnchor),
        ]
        NSLayoutConstraint.activate(pageConstraints)
        // Hace falta el layout resuelto antes de animar: si no, las filas entran desde el origen.
        contentBox.layoutSubtreeIfNeeded()
        fitWindow(animated: direction != 0)
        let rows = (view as? NSStackView)?.arrangedSubviews ?? [view]
        Animate.staggeredEntrance(rows, dx: direction == 0 ? 0 : direction * 30)
    }

    /// Lleva la ventana al alto que pide el paso actual, anclada por su borde superior.
    private func fitWindow(animated: Bool) {
        guard let window, let root = window.contentView else { return }
        let wanted = root.fittingSize.height
        guard wanted > 0 else { return }
        let current = window.contentRect(forFrameRect: window.frame).height
        let delta = wanted - current
        guard abs(delta) > 0.5 else { return }

        var frame = window.frame
        frame.size.height += delta
        frame.origin.y -= delta   // el borde de arriba se queda donde está

        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame, frame.height > visible.height {
            frame.size.height = visible.height
        }
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }

    @objc private func goBack() {
        guard index > 0 else { return }
        index -= 1
        showPage(direction: -1)
    }

    @objc private func goNext() {
        guard index < pages.count - 1 else {
            markCompleted()
            closeWithAnimation()
            return
        }
        index += 1
        showPage(direction: 1)
    }

    // MARK: - Página: bienvenida

    private func makeWelcomePage() -> NSView {
        let stack = verticalStack()
        if let demo = demo("demo-cycle") { stack.addArrangedSubview(demo) }
        stack.addArrangedSubview(paragraph("""
        Cada ventana del escritorio se asigna a la columna donde cae su centro, y dentro de cada columna \
        las ventanas forman su propia pila. Ciclar una columna no toca las otras: es la experiencia de \
        tener varios monitores, en uno solo.
        """))
        stack.addArrangedSubview(paragraph("""
        Arriba, ⌘` cicla las ventanas apiladas en el tercio activo. Los atajos completos están en el último \
        paso, y se pueden cambiar desde el menú ⫼ o a mano en config.json.
        """, secondary: true))
        return stack
    }

    // MARK: - Página: permisos

    private func makePermissionsPage() -> NSView {
        let stack = verticalStack()
        stack.addArrangedSubview(permissionRow(
            title: "Accesibilidad",
            detail: "Necesario para interceptar los atajos y para mover y reordenar ventanas. Sin esto, Stax no hace nada.",
            granted: { AXIsProcessTrusted() },
            action: #selector(grantAccessibility)))
        stack.addArrangedSubview(permissionRow(
            title: "Grabación de pantalla",
            detail: "Sólo para compartir ventanas con ⌃⌥S. Podés otorgarlo más adelante.",
            granted: { ShareMirror.hasPermission },
            action: #selector(grantScreenRecording)))
        stack.addArrangedSubview(paragraph("""
        Después de otorgar un permiso, macOS puede pedir que relances Stax. El estado de acá arriba se \
        actualiza solo.
        """, secondary: true))
        startPermissionTimer()
        return stack
    }

    /// Fila con el estado en vivo de un permiso y un botón para otorgarlo.
    private func permissionRow(title: String, detail: String, granted: @escaping () -> Bool, action: Selector) -> NSView {
        let container = NSView()

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 15, weight: .medium)
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        let text = NSTextField(wrappingLabelWithString: detail)
        text.font = .systemFont(ofSize: 12)
        text.textColor = .secondaryLabelColor
        let button = NSButton(title: "Abrir Ajustes", target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small

        // Un refresco que el timer vuelve a llamar mientras la página esté abierta.
        var wasGranted: Bool? = nil
        let refresh: () -> Void = { [weak status, weak button] in
            let ok = granted()
            defer { wasGranted = ok }
            status?.stringValue = ok ? "✓" : "⚠︎"
            status?.textColor = ok ? .systemGreen : .systemOrange
            button?.isHidden = ok
            // Sólo cuando acaba de cambiar a otorgado; no en cada tic del timer.
            if ok, wasGranted == false, let status { Animate.pop(status) }
        }
        refresh()
        permissionRefreshers.append(refresh)

        for view in [status, name, text, button] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            status.topAnchor.constraint(equalTo: container.topAnchor),
            status.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            status.widthAnchor.constraint(equalToConstant: 20),

            name.topAnchor.constraint(equalTo: container.topAnchor),
            name.leadingAnchor.constraint(equalTo: status.trailingAnchor, constant: 6),

            button.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            text.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 3),
            text.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            text.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private var permissionRefreshers: [() -> Void] = []

    private func startPermissionTimer() {
        permissionRefreshers.removeAll()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.permissionRefreshers.forEach { $0() }
        }
    }

    private func stopPermissionTimer() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        permissionRefreshers.removeAll()
    }

    @objc private func grantAccessibility() {
        // El prompt del sistema sólo aparece una vez por app; después hay que ir a Ajustes.
        if !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func grantScreenRecording() {
        ShareMirror.requestPermission()
    }

    // MARK: - Página: columnas

    private func makeColumnsPage() -> NSView {
        let stack = verticalStack()
        if let view = demo("demo-columns-\(controller.config.columns)") {
            columnsDemo = view
            stack.addArrangedSubview(view)
        }

        let segmented = NSSegmentedControl(labels: ["2 columnas", "3 columnas", "4 columnas"],
                                           trackingMode: .selectOne, target: self, action: #selector(setColumns(_:)))
        segmented.selectedSegment = max(0, min(2, controller.config.columns - 2))
        stack.addArrangedSubview(segmented)

        stack.addArrangedSubview(paragraph("""
        ⌃⌥D, ⌃⌥F y ⌃⌥G mandan la ventana con foco a la primera, la segunda y la tercera columna.
        """, secondary: true))

        stack.addArrangedSubview(header("¿Cuál es la columna activa?"))
        let focused = radio("La de la ventana con foco", action: #selector(setSelectionFocused))
        let pointer = radio("La que está bajo el puntero del mouse", action: #selector(setSelectionPointer))
        focused.state = controller.config.columnSelection == .focused ? .on : .off
        pointer.state = controller.config.columnSelection == .pointer ? .on : .off
        selectionRadios = [focused, pointer]
        stack.addArrangedSubview(focused)
        stack.addArrangedSubview(pointer)
        return stack
    }

    private var pageConstraints: [NSLayoutConstraint] = []
    private var demoImages: [String: NSImage] = [:]
    private weak var columnsDemo: NSImageView?
    private var selectionRadios: [NSButton] = []
    private var backendRadios: [NSButton] = []

    @objc private func setColumns(_ sender: NSSegmentedControl) {
        controller.config.columns = sender.selectedSegment + 2
        controller.config.save()
        if let view = columnsDemo, let image = demoImage("demo-columns-\(controller.config.columns)") {
            Animate.crossfadeImage(view, to: image)
        }
    }

    @objc private func setSelectionFocused() { setSelection(.focused) }
    @objc private func setSelectionPointer() { setSelection(.pointer) }

    private func setSelection(_ mode: ColumnSelection) {
        controller.config.columnSelection = mode
        controller.config.save()
        // Los radios de AppKit no se excluyen entre sí si no comparten superview lógico: los sincronizamos.
        selectionRadios.first?.state = mode == .focused ? .on : .off
        selectionRadios.last?.state = mode == .pointer ? .on : .off
    }

    // MARK: - Página: compartir

    private func makeSharePage() -> NSView {
        let stack = verticalStack()
        if let demo = demo("demo-share") { stack.addArrangedSubview(demo) }
        stack.addArrangedSubview(paragraph("""
        Ninguna app de videollamada deja cambiar desde afuera la ventana que compartís. Stax lo resuelve de \
        dos maneras, y elige sola la mejor disponible.
        """))

        stack.addArrangedSubview(header("¿Por dónde sale lo que compartís?"))
        backendRadios = ShareBackend.allCases.enumerated().map { position, backend in
            let button = radio(backend.label, action: #selector(setBackend(_:)))
            button.tag = position
            button.state = controller.config.shareBackend == backend ? .on : .off
            stack.addArrangedSubview(button)
            return button
        }

        let bridge = Bridge.shared.state
        let bridgeText: String
        if bridge.connected {
            bridgeText = bridge.inVoice
                ? "✓ El plugin StaxBridge está conectado y hay un canal de voz: ⌃⌥S cambia la ventana directo en Discord."
                : "✓ El plugin StaxBridge está conectado. Entrá a un canal de voz para transmitir desde Discord."
        } else {
            bridgeText = "○ El plugin StaxBridge no está conectado. Sin él, Stax comparte con su ventana espejo, que sirve para Meet, Zoom y Slack. La instalación está en VencordPlugin/README.md del repo."
        }
        stack.addArrangedSubview(paragraph(bridgeText, secondary: true))

        stack.addArrangedSubview(header("Opciones del espejo"))
        let virtual = checkbox("Ponerlo en una pantalla virtual (no ocupa lugar en el monitor)",
                               action: #selector(toggleVirtualDisplay(_:)))
        virtual.state = controller.config.shareUsesVirtualDisplay ? .on : .off
        virtual.isEnabled = VirtualDisplay.isAvailable
        if !VirtualDisplay.isAvailable { virtual.title += " — no disponible en este macOS" }
        stack.addArrangedSubview(virtual)

        let follow = checkbox("Seguir sola a la ventana con foco, sin tocar ⌃⌥S (⌃⌥⇧S)",
                              action: #selector(toggleFollowFocus(_:)))
        follow.state = controller.config.shareFollowsFocus ? .on : .off
        stack.addArrangedSubview(follow)
        return stack
    }

    @objc private func setBackend(_ sender: NSButton) {
        guard sender.tag < ShareBackend.allCases.count else { return }
        controller.config.shareBackend = ShareBackend.allCases[sender.tag]
        controller.config.save()
        for (position, button) in backendRadios.enumerated() {
            button.state = position == sender.tag ? .on : .off
        }
    }

    @objc private func toggleVirtualDisplay(_ sender: NSButton) {
        controller.config.shareUsesVirtualDisplay = sender.state == .on
        controller.config.save()
    }

    @objc private func toggleFollowFocus(_ sender: NSButton) {
        controller.config.shareFollowsFocus = sender.state == .on
        controller.config.save()
        controller.applyFollowFocus()
    }

    // MARK: - Página: final

    private func makeFinishPage() -> NSView {
        let stack = verticalStack()
        stack.addArrangedSubview(shortcutTable(controller.config.hotkeys.map { hotkey in
            var text = hotkey.action.humanDescription
            if hotkey.action == .moveToColumn, let column = hotkey.column {
                text = "Mover la ventana con foco al tercio \(column)"
            }
            return (hotkey.description, text)
        }))

        let login = checkbox("Abrir Stax al iniciar sesión", action: #selector(toggleLoginItem(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        stack.addArrangedSubview(login)

        stack.addArrangedSubview(paragraph("""
        Stax vive en el ícono ⫼ de la barra de menú: desde ahí ves las pilas de cada columna, cambiás estas \
        opciones y volvés a abrir este asistente cuando quieras.
        """, secondary: true))

        let openConfig = NSButton(title: "Abrir config.json", target: self, action: #selector(openConfig))
        openConfig.bezelStyle = .rounded
        openConfig.controlSize = .small
        let row = NSStackView(views: [openConfig])
        row.orientation = .horizontal
        stack.addArrangedSubview(row)
        return stack
    }

    @objc private func toggleLoginItem(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.info("abrir al iniciar sesión: \(sender.state == .on)")
        } catch {
            Log.warn("no pude cambiar el ítem de inicio: \(error.localizedDescription)")
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func openConfig() {
        controller.config.saveIfMissing()
        NSWorkspace.shared.open(Config.fileURL)
    }

    // MARK: - Piezas sueltas

    private func verticalStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        return stack
    }

    /// Los GIFs se cargan una sola vez: son de 200 KB para arriba y las páginas se rearman seguido.
    private func demoImage(_ name: String) -> NSImage? {
        if let cached = demoImages[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
              let image = NSImage(contentsOf: url) else { return nil }
        demoImages[name] = image
        return image
    }

    /// Uno de los GIFs del README, para mostrar el atajo en acción en vez de sólo describirlo.
    /// Con `swift build` no hay bundle y devuelve nil: las páginas se arman igual, sin la demo.
    private func demo(_ name: String) -> NSImageView? {
        guard let image = demoImage(name), image.size.width > 0 else { return nil }
        let view = NSImageView()
        view.image = image
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor

        let width: CGFloat = 460
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: (image.size.height / image.size.width * width).rounded()),
        ])
        return view
    }

    private func paragraph(_ text: String, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.preferredMaxLayoutWidth = 510
        return label
    }

    private func header(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func radio(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: self, action: action)
        button.font = .systemFont(ofSize: 12)
        return button
    }

    private func checkbox(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.font = .systemFont(ofSize: 12)
        return button
    }

    /// Dos columnas: atajo y qué hace.
    private func shortcutTable(_ rows: [(String, String)]) -> NSView {
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 5
        grid.columnSpacing = 14
        for (shortcut, description) in rows {
            let key = NSTextField(labelWithString: shortcut)
            key.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            let text = NSTextField(labelWithString: description)
            text.font = .systemFont(ofSize: 12)
            text.textColor = .secondaryLabelColor
            grid.addRow(with: [key, text])
        }
        grid.column(at: 0).xPlacement = .trailing
        return grid
    }
}

/// Las animaciones del asistente. Todo con Core Animation sobre la capa, para no pelear con Auto Layout:
/// la posición la sigue decidiendo el layout y nosotros sólo dibujamos encima.
private enum Animate {
    /// Entrada escalonada: cada fila aparece corrida y se acomoda con un resorte, un toque después que la anterior.
    static func staggeredEntrance(_ views: [NSView], dx: CGFloat) {
        for (position, view) in views.enumerated() {
            view.wantsLayer = true
            guard let layer = view.layer else { continue }
            let delay = CFTimeInterval(position) * 0.035
            let from = CATransform3DMakeTranslation(dx, -8, 0)

            let move = CASpringAnimation(keyPath: "transform")
            move.fromValue = NSValue(caTransform3D: from)
            move.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            move.mass = 0.9
            move.stiffness = 210
            move.damping = 20
            move.duration = move.settlingDuration

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.24
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

            // `backwards` sostiene el estado inicial durante el retardo; si no, la fila parpadea antes de entrar.
            for animation in [move, fade] as [CAAnimation] {
                animation.beginTime = CACurrentMediaTime() + delay
                animation.fillMode = .backwards
            }
            layer.add(move, forKey: "entrada.mover")
            layer.add(fade, forKey: "entrada.aparecer")
        }
    }

    /// Salida de la página que se va: se corre y se desvanece, y recién ahí avisa para sacarla.
    static func exit(_ view: NSView, dx: CGFloat, completion: @escaping () -> Void) {
        view.wantsLayer = true
        guard let layer = view.layer else { completion(); return }
        let duration = 0.18

        let move = CABasicAnimation(keyPath: "transform")
        move.toValue = NSValue(caTransform3D: CATransform3DMakeTranslation(dx, 0, 0))
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.toValue = 0
        for animation in [move, fade] as [CAAnimation] {
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        }
        layer.add(move, forKey: "salida.mover")
        layer.add(fade, forKey: "salida.desaparecer")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: completion)
    }

    /// Cambia el texto de una etiqueta con un fundido corto, para que no salte.
    static func crossfade(_ label: NSTextField?, to text: String) {
        guard let label else { return }
        guard label.stringValue != text else { return }
        label.wantsLayer = true
        label.stringValue = text
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.28
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        label.layer?.add(fade, forKey: "texto.fundido")
    }

    /// Cambia el GIF de una demo por otro con un fundido, en vez de un corte seco.
    static func crossfadeImage(_ view: NSImageView, to image: NSImage) {
        view.wantsLayer = true
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.3
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(transition, forKey: "demo.fundido")
        view.image = image
    }

    /// Golpecito de celebración: lo usamos cuando un permiso pasa a estar otorgado.
    static func pop(_ view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.4
        scale.toValue = 1
        scale.mass = 0.7
        scale.stiffness = 260
        scale.damping = 12
        scale.duration = scale.settlingDuration
        layer.add(scale, forKey: "permiso.golpe")
    }
}
