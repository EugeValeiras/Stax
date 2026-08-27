import Foundation
import CoreGraphics

enum Action: String, Codable {
    case cycleNext          // trae al frente la ventana del fondo de la pila
    case cyclePrev          // trae al frente la que está justo detrás y manda la frontal al fondo
    case focusColumnLeft    // foco a la ventana frontal de la columna de la izquierda
    case focusColumnRight   // foco a la ventana frontal de la columna de la derecha
    case moveToColumn       // mueve y redimensiona la ventana con foco a la columna `column` del atajo
    case shareFocusedWindow // la ventana con foco pasa a ser la que refleja la ventana "Stax Share"
    case stopSharing        // cierra la ventana "Stax Share"
    case toggleFollowFocus  // activa/desactiva que "Stax Share" siga sola a la ventana con foco
}

enum ColumnSelection: String, Codable {
    case focused   // la columna donde está la ventana con foco
    case pointer   // la columna bajo el puntero del mouse
}

enum Modifier: String, Codable, CaseIterable {
    case command, option, control, shift

    var flag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }
}

struct Config: Codable {
    var columns: Int = 3
    var columnSelection: ColumnSelection = .focused
    var hotkeys: [Hotkey] = Config.defaultHotkeys
    var shareFollowsFocus: Bool = false       // con "Stax Share" abierta, sigue sola a la ventana con foco
    var raiseOnlyTargetWindow: Bool = true    // usa API privada para subir solo esa ventana
    var minimumWindowSize: Double = 120       // ignora ventanas más chicas (paneles, tooltips)
    var verbose: Bool = false                 // loguea atajos y acciones en ~/Library/Logs/Stax.log

    static let defaultHotkeys: [Hotkey] = [
        Hotkey(key: "`", modifiers: [.command], action: .cycleNext),
        Hotkey(key: "`", modifiers: [.command, .shift], action: .cyclePrev),
        Hotkey(key: "left", modifiers: [.control, .command], action: .focusColumnLeft),
        Hotkey(key: "right", modifiers: [.control, .command], action: .focusColumnRight),
        Hotkey(key: "d", modifiers: [.control, .option], action: .moveToColumn, column: 1),
        Hotkey(key: "f", modifiers: [.control, .option], action: .moveToColumn, column: 2),
        Hotkey(key: "g", modifiers: [.control, .option], action: .moveToColumn, column: 3),
        Hotkey(key: "s", modifiers: [.control, .option], action: .shareFocusedWindow),
        Hotkey(key: "s", modifiers: [.control, .option, .shift], action: .toggleFollowFocus),
    ]

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/stax", isDirectory: true)
    static let fileURL = directory.appendingPathComponent("config.json")

    static func load() -> Config {
        if let data = try? Data(contentsOf: fileURL) {
            do {
                return try JSONDecoder().decode(Config.self, from: data)
            } catch {
                Log.warn("config.json inválido (\(error.localizedDescription)); uso defaults")
                return Config()
            }
        }
        let config = Config()
        config.saveIfMissing()
        return config
    }

    func saveIfMissing() {
        guard !FileManager.default.fileExists(atPath: Config.fileURL.path) else { return }
        save()
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: Config.fileURL)
        } catch {
            Log.warn("no pude guardar config: \(error)")
        }
    }
}

// Decodificación tolerante: cualquier clave ausente toma el valor por defecto.
extension Config {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? d.columns
        columnSelection = try c.decodeIfPresent(ColumnSelection.self, forKey: .columnSelection) ?? d.columnSelection
        hotkeys = try c.decodeIfPresent([Hotkey].self, forKey: .hotkeys) ?? d.hotkeys
        shareFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .shareFollowsFocus) ?? d.shareFollowsFocus
        raiseOnlyTargetWindow = try c.decodeIfPresent(Bool.self, forKey: .raiseOnlyTargetWindow) ?? d.raiseOnlyTargetWindow
        minimumWindowSize = try c.decodeIfPresent(Double.self, forKey: .minimumWindowSize) ?? d.minimumWindowSize
        verbose = try c.decodeIfPresent(Bool.self, forKey: .verbose) ?? d.verbose
    }
}

enum Log {
    static var verbose = false
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Stax.log")
    private static let lock = NSLock()
    private static var fileHandle: FileHandle?
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func enableFileLogging() {
        lock.lock(); defer { lock.unlock() }
        guard fileHandle == nil else { return }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: fileURL)
        fileHandle?.seekToEndOfFile()
    }

    static func info(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        write("[stax] \(message())")
    }

    static func warn(_ message: String) {
        write("[stax] ⚠️ \(message)")
    }

    private static func write(_ line: String) {
        let stamped = "\(formatter.string(from: Date())) \(line)\n"
        FileHandle.standardError.write(Data(stamped.utf8))
        lock.lock(); defer { lock.unlock() }
        fileHandle?.write(Data(stamped.utf8))
    }
}
