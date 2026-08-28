import CoreGraphics
import Foundation

/// Puente con el plugin *StaxBridge* de Vencord: un socket UNIX por el que Stax le pide a Discord que
/// cambie la ventana que está transmitiendo, sin pasar por el espejo ni por el selector de la app.
///
/// Stax es el servidor (siempre está corriendo); el plugin se conecta al arrancar Discord y reintenta solo.
/// El protocolo es JSON delimitado por saltos de línea (NDJSON), en las dos direcciones:
///
///   Stax → plugin   {"cmd":"share","windowId":1234,"pid":567,"app":"Safari","title":"…"}
///                   {"cmd":"stop"}
///   plugin → Stax   {"event":"hello","version":1}
///                   {"event":"state","inVoice":true,"streaming":true,"app":"Safari","title":"…"}
///                   {"event":"error","message":"…"}
///
/// Todo el I/O corre en el hilo principal: el tráfico son unos pocos mensajes por atajo, y así no hay
/// carreras con el resto de la app.
final class Bridge {
    static let shared = Bridge()

    /// Lo último que nos contó el plugin sobre el estado de Discord.
    struct State {
        var connected = false   // el plugin está enganchado al socket
        var inVoice = false     // hay un canal de voz activo (sin esto no se puede transmitir)
        var streaming = false   // Discord está transmitiendo ahora
        var app: String?        // qué ventana está transmitiendo
        var title: String?

        var sharingDescription: String? {
            guard streaming, let app else { return nil }
            if let title, !title.isEmpty { return "\(app): \(title)" }
            return app
        }
    }

    private(set) var state = State()

    /// La última ventana que le pedimos a Discord; evita repetir el pedido al seguir el foco.
    private(set) var requestedWindowID: CGWindowID?

    /// El plugin no pudo compartir lo que le pedimos (no encontró la ventana, se cayó el stream…).
    /// El llamador lo usa para caer al espejo en vez de dejar al usuario sin compartir nada.
    var onShareFailed: ((CGWindowID) -> Void)?

    static let socketURL = Config.directory.appendingPathComponent("bridge.sock")

    private var listenFD: Int32 = -1
    private var clientFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var readSource: DispatchSourceRead?
    private var inbox = Data()

    private init() {}

    // MARK: - Ciclo de vida

    /// Abre el socket y queda esperando al plugin. Si no se puede, lo loguea y sigue: el espejo funciona igual.
    func start() {
        guard listenFD < 0 else { return }

        do {
            try FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
        } catch {
            Log.warn("puente: no pude crear \(Config.directory.path): \(error.localizedDescription)")
            return
        }
        // Un socket de una corrida anterior deja el archivo; bind() falla si no lo sacamos.
        try? FileManager.default.removeItem(at: Bridge.socketURL)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Log.warn("puente: socket() falló (\(errno))")
            return
        }

        var address = sockaddr_un()
        guard Bridge.fill(&address, with: Bridge.socketURL.path) else {
            Log.warn("puente: la ruta del socket es demasiado larga: \(Bridge.socketURL.path)")
            close(fd)
            return
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else {
            Log.warn("puente: bind() falló en \(Bridge.socketURL.path) (\(errno))")
            close(fd)
            return
        }
        guard listen(fd, 1) == 0 else {
            Log.warn("puente: listen() falló (\(errno))")
            close(fd)
            return
        }

        // Sólo el usuario puede hablar con el puente.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Bridge.socketURL.path)

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptClient() }
        source.resume()
        acceptSource = source
        Log.info("puente escuchando en \(Bridge.socketURL.path)")
    }

    func stop() {
        disconnectClient(reason: nil)
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        try? FileManager.default.removeItem(at: Bridge.socketURL)
    }

    // MARK: - Conexión

    private func acceptClient() {
        let fd = accept(listenFD, nil, nil)
        guard fd >= 0 else { return }

        // El plugin anterior puede haber quedado colgado (Discord reiniciado): se queda el último.
        if clientFD >= 0 { disconnectClient(reason: "llegó otra conexión") }

        var on: Int32 = 1
        // Sin esto, escribir en un socket que el plugin ya cerró mata a Stax con SIGPIPE.
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)

        clientFD = fd
        inbox.removeAll()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.readFromClient() }
        source.resume()
        readSource = source

        state.connected = true
        Log.info("puente: plugin conectado")
    }

    private func disconnectClient(reason: String?) {
        readSource?.cancel()
        readSource = nil
        if clientFD >= 0 { close(clientFD) }
        clientFD = -1
        inbox.removeAll()

        let wasConnected = state.connected
        state = State()
        requestedWindowID = nil
        if wasConnected {
            Log.info("puente: plugin desconectado\(reason.map { " (\($0))" } ?? "")")
        }
    }

    private func readFromClient() {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = read(clientFD, &chunk, chunk.count)
        if count == 0 {
            disconnectClient(reason: "cerró la conexión")
            return
        }
        if count < 0 {
            if errno == EAGAIN || errno == EINTR { return }
            disconnectClient(reason: "read() falló (\(errno))")
            return
        }

        inbox.append(contentsOf: chunk[0..<count])
        // Un mensaje por línea; lo que quede sin \n espera al próximo read.
        while let newline = inbox.firstIndex(of: 0x0A) {
            let line = inbox[inbox.startIndex..<newline]
            inbox.removeSubrange(inbox.startIndex...newline)
            guard !line.isEmpty else { continue }
            handle(line: Data(line))
        }
        // Un mensaje descomunal sólo puede ser basura: cortamos antes de comernos la memoria.
        if inbox.count > 64 * 1024 {
            disconnectClient(reason: "mensaje sin fin")
        }
    }

    private func handle(line: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let event = message["event"] as? String else {
            Log.info("puente: mensaje ininteligible")
            return
        }

        switch event {
        case "hello":
            let version = message["version"] as? Int ?? 0
            Log.info("puente: plugin v\(version) listo")

        case "state":
            state.inVoice = message["inVoice"] as? Bool ?? false
            state.streaming = message["streaming"] as? Bool ?? false
            state.app = message["app"] as? String
            state.title = message["title"] as? String
            Log.info("puente: voz=\(state.inVoice) transmitiendo=\(state.streaming) \(state.sharingDescription ?? "—")")

        case "error":
            Log.warn("puente: \(message["message"] as? String ?? "error sin detalle")")
            if message["cmd"] as? String == "share" {
                let failed = (message["windowId"] as? Int).map { CGWindowID($0) } ?? requestedWindowID
                requestedWindowID = nil
                if let failed { onShareFailed?(failed) }
            }

        default:
            Log.info("puente: evento desconocido \(event)")
        }
    }

    // MARK: - Comandos

    /// Le pide a Discord que transmita `window`. Devuelve false si el puente no está en condiciones
    /// (sin plugin conectado o sin canal de voz), para que el llamador caiga al espejo.
    @discardableResult
    func share(_ window: WindowInfo) -> Bool {
        guard state.connected, state.inVoice else { return false }
        var message: [String: Any] = [
            "cmd": "share",
            "windowId": Int(window.id),
            "pid": Int(window.pid),
            "app": window.ownerName,
        ]
        if let title = window.title { message["title"] = title }
        guard send(message) else { return false }
        requestedWindowID = window.id
        Log.info("puente → Discord: \(window.ownerName) #\(window.id)")
        return true
    }

    /// Corta la transmisión de Discord. Devuelve false si no había nada que cortar.
    @discardableResult
    func stopSharing() -> Bool {
        requestedWindowID = nil
        guard state.connected, state.streaming else { return false }
        return send(["cmd": "stop"])
    }

    private func send(_ message: [String: Any]) -> Bool {
        guard clientFD >= 0, var data = try? JSONSerialization.data(withJSONObject: message) else { return false }
        data.append(0x0A)

        return data.withUnsafeBytes { raw -> Bool in
            guard var pointer = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            var remaining = data.count
            while remaining > 0 {
                let written = write(clientFD, pointer, remaining)
                if written > 0 {
                    pointer += written
                    remaining -= written
                    continue
                }
                if written < 0 && (errno == EAGAIN || errno == EINTR) { continue }
                Log.warn("puente: no pude escribirle al plugin (\(errno))")
                DispatchQueue.main.async { [weak self] in self?.disconnectClient(reason: "write() falló") }
                return false
            }
            return true
        }
    }

    /// Copia `path` dentro de `sun_path`, que es un buffer de C de tamaño fijo (104 bytes en macOS).
    private static func fill(_ address: inout sockaddr_un, with path: String) -> Bool {
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { return false }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { tuple in
            tuple.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                for (index, byte) in bytes.enumerated() { destination[index] = CChar(bitPattern: byte) }
                destination[bytes.count] = 0
            }
        }
        return true
    }
}
