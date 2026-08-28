import AppKit
import StaxPrivate

/// Una pantalla que no existe: macOS la registra como un monitor más, pero no está enchufada a nada.
///
/// Sirve para que la ventana espejo no ocupe lugar en el ultrawide. Con esto activado, "Stax Share" vive
/// en esta pantalla y en la videollamada compartís *la pantalla* "Stax Share" una sola vez; el espejo
/// queda del tamaño exacto de la pantalla virtual, así que la llamada ve siempre 1080p limpios sin
/// importar cuán grande sea la ventana original.
///
/// Usa la API privada `CGVirtualDisplay` (la misma de DeskPad y BetterDisplay). Si algún macOS la saca,
/// `isAvailable` da false y todo sigue funcionando con el espejo en una ventana normal.
///
/// Ojo: la pantalla sólo se registra si Stax corre como app empaquetada (lanzada por LaunchServices).
/// Con `swift run` o ejecutando el binario a mano, `applySettings` dice que sí pero la pantalla nunca
/// se activa; por eso `start()` verifica que quedó online de verdad.
final class VirtualDisplay {
    static let shared = VirtualDisplay()

    /// Tamaño lógico de la pantalla, en puntos. El respaldo va al doble (hiDPI), o sea 3840×2160.
    static let defaultSize = CGSize(width: 1920, height: 1080)

    private var display: CGVirtualDisplay?

    private init() {}

    static var isAvailable: Bool { StaxVirtualDisplayAvailable() }

    var isActive: Bool { display != nil }

    var displayID: CGDirectDisplayID? { display?.displayID }

    /// El `NSScreen` de la pantalla virtual, o nil si no está creada (o si AppKit todavía no la vio).
    var screen: NSScreen? {
        guard let id = displayID else { return nil }
        return NSScreen.screens.first { $0.displayID == id }
    }

    /// Crea la pantalla si no existe. Devuelve false si no se pudo (API ausente o el sistema la rechazó).
    @discardableResult
    func start(size: CGSize = VirtualDisplay.defaultSize) -> Bool {
        if display != nil { return true }
        guard VirtualDisplay.isAvailable else {
            Log.warn("este macOS no tiene la API de pantallas virtuales; uso el espejo en una ventana")
            return false
        }

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "Stax Share"
        descriptor.maxPixelsWide = UInt32(size.width * 2)
        descriptor.maxPixelsHigh = UInt32(size.height * 2)
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 340)
        descriptor.vendorID = 0x0610
        descriptor.productID = 0xB1DE
        descriptor.serialNum = UInt32.random(in: 1...UInt32.max)
        // Un EDID con colorimetría sRGB: sin esto algunas versiones de macOS no terminan de aceptarla.
        descriptor.redPrimary = CGPoint(x: 0.640, y: 0.330)
        descriptor.greenPrimary = CGPoint(x: 0.300, y: 0.600)
        descriptor.bluePrimary = CGPoint(x: 0.150, y: 0.060)
        descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.3290)

        let display = CGVirtualDisplay(descriptor: descriptor)
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = [CGVirtualDisplayMode(width: UInt32(size.width), height: UInt32(size.height), refreshRate: 60)]

        guard display.apply(settings) else {
            Log.warn("no pude configurar la pantalla virtual")
            return false
        }
        // applySettings puede decir que sí y no activar nada (pasa si Stax no corre como app empaquetada).
        guard CGDisplayIsOnline(display.displayID) != 0 else {
            Log.warn("la pantalla virtual no se activó; ¿estás corriendo Stax.app o el binario suelto?")
            return false
        }

        self.display = display
        Log.info("pantalla virtual creada: #\(display.displayID) \(Int(size.width))×\(Int(size.height)) @2x")
        return true
    }

    /// Saca la pantalla. macOS reacomoda las ventanas que hubiera ahí, como al desenchufar un monitor.
    func stop() {
        guard let display else { return }
        self.display = nil
        Log.info("pantalla virtual #\(display.displayID) dada de baja")
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
