import AppKit
import AVFoundation
import ScreenCaptureKit

/// Ventana espejo "Stax Share": refleja en vivo, vía ScreenCaptureKit, el contenido de la ventana elegida.
///
/// Ninguna app de videollamada deja cambiar la ventana compartida desde afuera, así que en Meet/Zoom/Slack se
/// comparte *esta* ventana una sola vez y después se cambia la ventana de origen con `shareFocusedWindow`
/// sin tocar la llamada. La captura funciona aunque la ventana de origen quede tapada por otras.
/// Necesita el permiso de Grabación de pantalla.
final class ShareMirror: NSObject {
    static let shared = ShareMirror()

    /// Ventana que se está reflejando (nil si no hay captura activa).
    private(set) var source: WindowInfo?

    private var stream: SCStream?
    private var window: NSWindow?
    private var view: MirrorView?
    private var pollTimer: Timer?
    private var generation = 0   // invalida los resultados asincrónicos de un share() anterior
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let sampleQueue = DispatchQueue(label: "com.eugeniovaleiras.Stax.share")

    var isSharing: Bool { source != nil && stream != nil }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Pide el permiso de Grabación de pantalla si falta. Devuelve true si ya lo tenemos.
    @discardableResult
    static func requestPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        Log.warn("falta permiso de Grabación de pantalla: Ajustes → Privacidad y seguridad → Grabación de pantalla (y relanzar Stax)")
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    // MARK: - API

    /// Empieza a reflejar `target` (o cambia la ventana de origen si ya hay captura).
    func share(_ target: WindowInfo) {
        guard ShareMirror.requestPermission() else { return }
        generation += 1
        let gen = generation
        // onScreenWindowsOnly: false para poder compartir una ventana que está en otro escritorio.
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                if let error {
                    Log.warn("no pude listar las ventanas para compartir: \(error.localizedDescription)")
                    return
                }
                guard let scWindow = content?.windows.first(where: { $0.windowID == target.id }) else {
                    Log.warn("no encontré la ventana \(target.ownerName) #\(target.id) para compartir")
                    return
                }
                self.start(scWindow, from: target, generation: gen)
            }
        }
    }

    /// Detiene la captura y cierra la ventana espejo.
    func stop() {
        generation += 1
        stopCapture()
        source = nil
        if let window {
            self.window = nil
            self.view = nil
            window.close()
        }
        Log.info("dejo de compartir")
    }

    // MARK: - Captura

    private func start(_ scWindow: SCWindow, from target: WindowInfo, generation gen: Int) {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let scale = Screens.backingScale(atCG: target.center)
        let config = streamConfiguration(for: scWindow.frame.size, scale: scale)
        let source = WindowInfo(id: target.id, pid: target.pid,
                                ownerName: scWindow.owningApplication?.applicationName ?? target.ownerName,
                                bounds: scWindow.frame, title: scWindow.title)

        let finish: (Error?) -> Void = { [weak self] error in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                if let error {
                    Log.warn("no pude compartir \(source.ownerName) #\(source.id): \(error.localizedDescription)")
                    self.stopCapture()
                    return
                }
                self.source = source
                self.showWindow(for: source)
                self.startPolling()
                Log.info("compartiendo → \(source.ownerName) #\(source.id) \(source.title ?? "") \(config.width)×\(config.height)px")
            }
        }

        if let stream {
            // Cambio de origen sin cortar la captura: la videollamada ni se entera.
            stream.updateContentFilter(filter) { error in
                if let error { finish(error); return }
                stream.updateConfiguration(config, completionHandler: finish)
            }
            return
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        } catch {
            finish(error)
            return
        }
        self.stream = stream
        stream.startCapture(completionHandler: finish)
    }

    private func streamConfiguration(for size: CGSize, scale: CGFloat) -> SCStreamConfiguration {
        var pixels = CGSize(width: max(size.width, 1) * scale, height: max(size.height, 1) * scale)
        let maxSide: CGFloat = 8192
        if max(pixels.width, pixels.height) > maxSide {
            let factor = maxSide / max(pixels.width, pixels.height)
            pixels = CGSize(width: pixels.width * factor, height: pixels.height * factor)
        }
        let config = SCStreamConfiguration()
        config.width = Int(pixels.width.rounded())
        config.height = Int(pixels.height.rounded())
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 5
        config.captureResolution = .best
        config.scalesToFit = true
        config.shouldBeOpaque = true
        config.ignoreShadowsSingleWindow = true
        return config
    }

    private func stopCapture() {
        stopPolling()
        guard let stream else { return }
        self.stream = nil
        stream.stopCapture { error in
            if let error { Log.info("stopCapture: \(error.localizedDescription)") }
        }
        displayLayer.sampleBufferRenderer.flush()
    }

    /// La ventana de origen se cerró (o la captura murió): queda el espejo con un aviso, listo para otro origen.
    private func sourceVanished() {
        let name = source.map { "\($0.ownerName) #\($0.id)" } ?? "?"
        stopCapture()
        source = nil
        window?.title = "Stax Share"
        view?.message = "La ventana compartida se cerró.\nEnfocá otra y usá el atajo para seguir compartiendo."
        Log.info("la ventana compartida \(name) ya no existe")
    }

    // MARK: - Seguimiento de la ventana de origen

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Cada segundo: si la ventana de origen cambió de tamaño o de título, ajusta la captura y el espejo;
    /// si desapareció, avisa.
    private func poll() {
        guard let source, let stream else { return }
        guard let entry = (CGWindowListCopyWindowInfo([.optionIncludingWindow], source.id) as? [[String: Any]])?.first,
              let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
            sourceVanished()
            return
        }
        let title = entry[kCGWindowName as String] as? String
        guard bounds.size != source.bounds.size || title != source.title else { return }

        let updated = WindowInfo(id: source.id, pid: source.pid, ownerName: source.ownerName, bounds: bounds, title: title)
        self.source = updated
        if bounds.size != source.bounds.size {
            let config = streamConfiguration(for: bounds.size, scale: Screens.backingScale(atCG: updated.center))
            stream.updateConfiguration(config) { error in
                if let error { Log.warn("no pude ajustar la captura al nuevo tamaño: \(error.localizedDescription)") }
            }
            Log.info("la ventana compartida cambió a \(Int(bounds.width))×\(Int(bounds.height)); ajusto el espejo")
        }
        showWindow(for: updated)
    }

    // MARK: - Ventana espejo

    /// Muestra el espejo del tamaño de la ventana de origen (acotado a la pantalla), conservando su esquina
    /// superior izquierda, sin robarle el foco a la ventana que se está compartiendo.
    private func showWindow(for source: WindowInfo) {
        let window = self.window ?? makeWindow()
        window.title = ShareMirror.title(for: source)

        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var content = source.bounds.size
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
        if frame.width > visible.width || frame.height > visible.height {
            let factor = min(visible.width / frame.width, visible.height / frame.height)
            content = NSSize(width: (content.width * factor).rounded(.down), height: (content.height * factor).rounded(.down))
            frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
        }
        var origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)

        window.contentAspectRatio = content
        window.setFrame(NSRect(origin: origin, size: frame), display: true)
        view?.message = nil
        if !window.isVisible { window.orderFrontRegardless() }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = .black
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenNone]
        let view = MirrorView(displayLayer: displayLayer)
        window.contentView = view
        window.center()
        window.setFrameAutosaveName("StaxShare")   // recuerda dónde la dejó el usuario
        self.window = window
        self.view = view
        return window
    }

    static func title(for source: WindowInfo) -> String {
        if let title = source.title, !title.isEmpty { return "Stax Share — \(source.ownerName): \(title)" }
        return "Stax Share — \(source.ownerName)"
    }
}

// MARK: - Frames de ScreenCaptureKit → AVSampleBufferDisplayLayer

extension ShareMirror: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, CMSampleBufferGetImageBuffer(sampleBuffer) != nil,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { return }
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)

        // Sólo los frames completos traen imagen; los idle/blank/suspended no.
        let statusKey = Unmanaged.passUnretained(SCStreamFrameInfo.status.rawValue as CFString).toOpaque()
        guard let statusRef = CFDictionaryGetValue(dictionary, statusKey),
              let status = (Unmanaged<CFNumber>.fromOpaque(statusRef).takeUnretainedValue() as NSNumber?).map({ $0.intValue }),
              SCFrameStatus(rawValue: status) == .complete else { return }

        // Mostrar ya, sin esperar al timestamp del frame.
        CFDictionarySetValue(dictionary,
                             Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())

        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding { renderer.flush() }
        renderer.enqueue(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            Log.warn("la captura se detuvo: \(error.localizedDescription)")
            self.sourceVanished()
        }
    }
}

extension ShareMirror: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Si `window` ya es nil, el cierre vino de stop(); si no, lo cerró el usuario con el botón rojo.
        guard window != nil else { return }
        window = nil
        view = nil
        generation += 1
        stopCapture()
        source = nil
        Log.info("espejo cerrado por el usuario; dejo de compartir")
    }
}

/// Vista negra con la capa de video ocupando todo y un aviso centrado cuando no hay captura.
private final class MirrorView: NSView {
    private let displayLayer: AVSampleBufferDisplayLayer
    private let label = NSTextField(wrappingLabelWithString: "")

    var message: String? {
        didSet {
            label.stringValue = message ?? ""
            label.isHidden = message == nil
        }
    }

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)

        label.textColor = .white
        label.alignment = .center
        label.font = .systemFont(ofSize: 16)
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no implementado") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}
