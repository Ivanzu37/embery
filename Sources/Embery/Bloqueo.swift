import AppKit

// Bloqueo durante el foco: las apps de la lista se ocultan al activarse; las webs se cierran en Chrome y Safari.

enum Navegador: String, CaseIterable {
    case chrome = "com.google.Chrome", safari = "com.apple.Safari"
    var leer: String {
        switch self {
        case .chrome: "tell application \"Google Chrome\" to if (count of windows) > 0 then get URL of active tab of front window"
        case .safari: "tell application \"Safari\" to if (count of windows) > 0 then get URL of current tab of front window"
        }
    }
    var cerrar: String {
        switch self {
        case .chrome: "tell application \"Google Chrome\" to close active tab of front window"
        case .safari: "tell application \"Safari\" to close current tab of front window"
        }
    }
}

// «www.instagram.com» y «m.instagram.com» cuentan como «instagram.com»; «notinstagram.com» no.
func webBloqueada(_ url: String, _ lista: [Bloqueado]) -> Bloqueado? {
    guard let host = URL(string: url)?.host?.lowercased() else { return nil }
    return lista.first { b in
        guard let w = b.web?.lowercased() else { return false }
        return host == w || host.hasSuffix("." + w)
    }
}

final class Bloqueo {
    var activo: () -> Bool = { false }
    var lista: () -> [Bloqueado] = { [] }
    var alBloquear: (Bloqueado) -> Void = { _ in }
    private var temporizador: Timer?

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.revisar(app)
        }
        temporizador = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.revisarWeb() }
    }

    func revisarAhora() { if let app = NSWorkspace.shared.frontmostApplication { revisar(app); revisarWeb() } }

    private func revisar(_ app: NSRunningApplication) {
        guard activo(), let id = app.bundleIdentifier, let b = lista().first(where: { $0.app == id }) else { return }
        app.hide()
        alBloquear(b)
    }

    // Fuera del hilo principal: la primera vez macOS pide permiso para controlar el navegador y,
    // mientras no contestas, el script espera; en el hilo principal congelaba la app.
    private let cola = DispatchQueue(label: "embery.bloqueo")
    private var ocupado = false

    private func revisarWeb() {
        guard !ocupado, activo(), let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, let nav = Navegador(rawValue: id) else { return }
        ocupado = true
        let lista = lista()
        cola.async {
            var b: Bloqueado?
            if let url = osascript(nav.leer), let x = webBloqueada(url, lista) { _ = osascript(nav.cerrar); b = x }
            DispatchQueue.main.async { self.ocupado = false; if let b { self.alBloquear(b) } }
        }
    }
}

// osascript en vez de NSAppleScript: NSAppleScript no es seguro fuera del hilo principal.
private func osascript(_ s: String) -> String? {
    let p = Process(), salida = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", s]; p.standardOutput = salida; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    return String(data: salida.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}
