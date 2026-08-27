import AppKit
import Carbon.HIToolbox
import CoreGraphics

struct Hotkey: Codable, Equatable {
    var key: String              // un carácter ("`", "1") o un nombre: left, right, up, down, tab, space, escape, return, o "keycode:50"
    var modifiers: [Modifier]
    var action: Action

    static let namedKeys: [String: Int64] = [
        "left": Int64(kVK_LeftArrow), "right": Int64(kVK_RightArrow),
        "up": Int64(kVK_UpArrow), "down": Int64(kVK_DownArrow),
        "tab": Int64(kVK_Tab), "space": Int64(kVK_Space), "escape": Int64(kVK_Escape),
        "return": Int64(kVK_Return), "delete": Int64(kVK_Delete),
    ]

    var description: String {
        let mods = modifiers.map(\.symbol).joined()
        let keyName: String
        switch key.lowercased() {
        case "left": keyName = "←"
        case "right": keyName = "→"
        case "up": keyName = "↑"
        case "down": keyName = "↓"
        case "tab": keyName = "⇥"
        case "space": keyName = "␣"
        case "escape": keyName = "⎋"
        case "return": keyName = "↩"
        default: keyName = key
        }
        return mods + keyName
    }

    var requiredFlags: CGEventFlags {
        modifiers.reduce(CGEventFlags()) { $0.union($1.flag) }
    }

    func matches(keyCode: Int64, baseCharacter: String, flags: CGEventFlags) -> Bool {
        let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        guard flags.intersection(relevant) == requiredFlags else { return false }
        let lower = key.lowercased()
        if lower.hasPrefix("keycode:"), let code = Int64(lower.dropFirst("keycode:".count)) {
            return keyCode == code
        }
        if let code = Hotkey.namedKeys[lower] {
            return keyCode == code
        }
        return baseCharacter.lowercased() == lower
    }
}

/// Event tap global de teclado: ejecuta acciones ante los atajos configurados y se traga el evento.
final class HotkeyManager {
    static let shared = HotkeyManager()

    var hotkeys: [Hotkey] = []
    var onHotkey: ((Hotkey) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isInstalled: Bool { tap != nil }

    func install() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: nil
        ) else {
            Log.warn("no pude instalar el event tap de teclado (¿falta Accesibilidad?)")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.info("event tap de teclado instalado: \(hotkeys.map(\.description))")
        return true
    }

    fileprivate func reenableIfNeeded() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Devuelve true si el evento fue consumido por un atajo.
    fileprivate func handle(_ event: CGEvent) -> Bool {
        guard !hotkeys.isEmpty else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Carácter base de la tecla (sin modificadores), para que ⌘⇧` siga siendo "`" y no "~".
        var baseCharacter = ""
        if let copy = event.copy() {
            copy.flags = []
            var length = 0
            var buffer = [UniChar](repeating: 0, count: 4)
            copy.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
            baseCharacter = String(utf16CodeUnits: buffer, count: length)
        }

        guard let hotkey = hotkeys.first(where: { $0.matches(keyCode: keyCode, baseCharacter: baseCharacter, flags: flags) }) else {
            return false
        }
        Log.info("atajo \(hotkey.description) → \(hotkey.action.rawValue)")
        DispatchQueue.main.async { self.onHotkey?(hotkey) }
        return true
    }
}

private func hotkeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        HotkeyManager.shared.reenableIfNeeded()
        return Unmanaged.passUnretained(event)
    }
    if type == .keyDown, HotkeyManager.shared.handle(event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}
