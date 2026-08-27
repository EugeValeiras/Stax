import AppKit
import ApplicationServices

/// Modo automático de Stax Share: avisa cada vez que cambia la ventana con foco (otra app, u otra ventana
/// de la misma app) para que el espejo pase a reflejarla sin tocar el atajo.
///
/// Combina la notificación de activación de apps de NSWorkspace con un `AXObserver` sobre la app frontal
/// (`kAXFocusedWindowChangedNotification`), que se vuelve a crear cada vez que cambia la app frontal.
/// Los avisos se agrupan con un pequeño debounce para no pisarse mientras se cicla con ⌘`.
final class FocusFollower {
    static let shared = FocusFollower()

    var onFocusChange: (() -> Void)?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var activationToken: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    private let debounce = 0.25

    private init() {}

    private func start() {
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.observe(app.processIdentifier)
            self.focusChanged()
        }
        if let app = NSWorkspace.shared.frontmostApplication { observe(app.processIdentifier) }
        Log.info("seguir el foco: activado")
    }

    private func stop() {
        if let activationToken { NSWorkspace.shared.notificationCenter.removeObserver(activationToken) }
        activationToken = nil
        removeObserver()
        pending?.cancel()
        pending = nil
        Log.info("seguir el foco: desactivado")
    }

    /// Observa los cambios de ventana con foco dentro de la app `pid`.
    private func observe(_ pid: pid_t) {
        guard pid != observedPID else { return }
        removeObserver()
        guard pid != getpid() else { return }   // la propia ventana Stax Share no cuenta
        var observer: AXObserver?
        guard AXObserverCreate(pid, focusCallback, &observer) == .success, let observer else {
            Log.info("no pude observar la app pid \(pid) (AXObserverCreate falló)")
            return
        }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, app, kAXMainWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = observer
        observedPID = pid
    }

    private func removeObserver() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        let app = AXUIElementCreateApplication(observedPID)
        AXObserverRemoveNotification(observer, app, kAXFocusedWindowChangedNotification as CFString)
        AXObserverRemoveNotification(observer, app, kAXMainWindowChangedNotification as CFString)
        self.observer = nil
        observedPID = 0
    }

    fileprivate func focusChanged() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.pending = nil
            self?.onFocusChange?()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}

private let focusCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    Unmanaged<FocusFollower>.fromOpaque(refcon).takeUnretainedValue().focusChanged()
}
