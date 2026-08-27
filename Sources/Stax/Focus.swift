import AppKit
import ApplicationServices

/// Sube y da foco a una ventana concreta.
///
/// Modo "solo esta ventana": usa `_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo` (SkyLight),
/// la misma técnica de AltTab/yabai, para activar la app trayendo al frente únicamente la ventana pedida.
/// Si falla, cae a Accessibility puro (`activate` + `AXRaise`), que trae todas las ventanas de la app.
final class WindowFocuser {
    static let shared = WindowFocuser()

    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias SetFrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError
    private typealias PostEventFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias GetPSNFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private let axGetWindow: GetWindowFn?
    private let setFrontProcess: SetFrontFn?
    private let postEventRecord: PostEventFn?
    private let getProcessForPID: GetPSNFn?

    var privateAPIAvailable: Bool { setFrontProcess != nil && postEventRecord != nil && getProcessForPID != nil }

    private init() {
        let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        func load<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
            guard let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: type)
        }
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        axGetWindow = load(defaultHandle, "_AXUIElementGetWindow", as: GetWindowFn.self)
        getProcessForPID = load(defaultHandle, "GetProcessForPID", as: GetPSNFn.self)
        setFrontProcess = load(skylight, "_SLPSSetFrontProcessWithOptions", as: SetFrontFn.self)
        postEventRecord = load(skylight, "SLPSPostEventRecordTo", as: PostEventFn.self)
    }

    func raise(_ window: WindowInfo, onlyThisWindow: Bool) {
        let axWindow = axElement(for: window)

        if onlyThisWindow, privateAPIAvailable, raiseWithSkyLight(window) {
            if let axWindow { AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString) }
            Log.info("raise(SkyLight) → \(window.ownerName) #\(window.id)")
            return
        }

        // Fallback: Accessibility puro. Trae todas las ventanas de la app.
        NSRunningApplication(processIdentifier: window.pid)?.activate()
        if let axWindow {
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
        Log.info("raise(AX) → \(window.ownerName) #\(window.id)")
    }

    /// Id de CoreGraphics de una ventana AX (API privada `_AXUIElementGetWindow`).
    func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let axGetWindow else { return nil }
        var id: CGWindowID = 0
        return axGetWindow(element, &id) == .success ? id : nil
    }

    // MARK: - Privado

    private func raiseWithSkyLight(_ window: WindowInfo) -> Bool {
        guard let getProcessForPID, let setFrontProcess, let postEventRecord else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(window.pid, &psn) == noErr else { return false }

        let kCPSUserGenerated: UInt32 = 0x200
        guard setFrontProcess(&psn, window.id, kCPSUserGenerated) == .success else { return false }

        // "makeKeyWindow": dos eventos sintéticos que hacen key a la ventana sin tocar el resto.
        var windowID = window.id
        var bytes1 = [UInt8](repeating: 0, count: 0xf8)
        var bytes2 = [UInt8](repeating: 0, count: 0xf8)
        bytes1[0x04] = 0xF8; bytes1[0x08] = 0x01; bytes1[0x3a] = 0x10
        bytes2[0x04] = 0xF8; bytes2[0x08] = 0x02; bytes2[0x3a] = 0x10
        withUnsafeBytes(of: &windowID) { raw in
            for i in 0..<4 {
                bytes1[0x3c + i] = raw[i]
                bytes2[0x3c + i] = raw[i]
            }
        }
        for i in 0..<0x10 {
            bytes1[0x20 + i] = 0xFF
            bytes2[0x20 + i] = 0xFF
        }
        _ = postEventRecord(&psn, &bytes1)
        _ = postEventRecord(&psn, &bytes2)
        return true
    }

    private func axElement(for window: WindowInfo) -> AXUIElement? {
        let candidates = AX.windows(ofApp: window.pid)
        if let axGetWindow {
            for candidate in candidates {
                var id: CGWindowID = 0
                if axGetWindow(candidate, &id) == .success, id == window.id { return candidate }
            }
        }
        // Fallback: comparar por frame.
        return candidates.first { candidate in
            guard let frame = AX.frame(of: candidate) else { return false }
            return abs(frame.minX - window.bounds.minX) < 2 && abs(frame.minY - window.bounds.minY) < 2
                && abs(frame.width - window.bounds.width) < 2 && abs(frame.height - window.bounds.height) < 2
        }
    }
}
