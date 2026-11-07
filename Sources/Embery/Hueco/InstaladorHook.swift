// Embery · el botón de Ajustes que conecta Claude Code: añade o quita embery-hook (y embery-status, la statusline
// que trae los límites del plan) en un settings.json dado. Solo toca lo suyo; lo demás se queda como estaba.
// Una statusline ajena no se pisa: sin ella Embery funciona igual, solo sin los límites.
import Foundation

enum InstaladorHook {
    static let eventos = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                          "PermissionRequest", "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop"]
    // El del permiso espera a que decidas en el Hueco (60 s en el hook); el resto solo avisa.
    static func plazo(_ evento: String) -> Int { evento == "PermissionRequest" ? Int(HookServer.espera) + 30 : 5 }

    static var ajustesClaude: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json") }
    static var rutaHook: String? { Bundle.main.url(forResource: "embery-hook", withExtension: nil)?.path }
    static var rutaEstado: String? { Bundle.main.url(forResource: "embery-status", withExtension: nil)?.path }

    static func comando(hook: String, socket: String = SOCKET_PATH) -> String { "\(citar(hook)) \(citar(socket))" }
    private static func citar(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    enum Fallo: Error { case ilegible, sinMover }
    // Abierta desde el DMG o desde Descargas sin mover, macOS la ejecuta desde una copia temporal (translocada):
    // un hook que apunte ahí deja de existir y Claude Code daría error en cada evento.
    static var sinMover: Bool {
        let p = Bundle.main.bundlePath
        return p.contains("/AppTranslocation/") || p.hasPrefix("/Volumes/") || !p.hasSuffix(".app")
    }
    static func texto(_ e: Error) -> String {
        (e as? Fallo) == .sinMover ? String(localized: "Mueve Embery a Aplicaciones y ábrela desde allí para conectar")
            : String(localized: "No se pudo leer settings.json: no se ha tocado")
    }

    private static func leer(_ url: URL) throws -> [String: Any] {
        guard let d = try? Data(contentsOf: url), !d.isEmpty else { return [:] }
        // Un archivo que no se entiende no se pisa.
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw Fallo.ilegible }
        return o
    }

    private static func escribir(_ o: [String: Any], _ url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let respaldo = url.appendingPathExtension("before-embery")
        if fm.fileExists(atPath: url.path), !fm.fileExists(atPath: respaldo.path) { try fm.copyItem(at: url, to: respaldo) }
        try JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .withoutEscapingSlashes]).write(to: url, options: .atomic)
    }

    private static func usa(_ grupo: Any, _ cmd: String) -> Bool {
        ((grupo as? [String: Any])?["hooks"] as? [[String: Any]])?.contains { $0["command"] as? String == cmd } ?? false
    }
    // Cualquier embery-hook, venga de esta copia de la app o de otra (otra ruta, otro socket).
    private static func esHook(_ e: [String: Any]) -> Bool { (e["command"] as? String)?.contains("embery-hook") ?? false }
    private static func lineaNuestra(_ o: [String: Any]) -> Bool {
        ((o["statusLine"] as? [String: Any])?["command"] as? String)?.contains("embery-status") ?? false
    }
    // ¿Hay otra statusline que no es la nuestra? Entonces no llegan los límites del plan.
    static func lineaAjena(en url: URL) -> Bool {
        guard let o = try? leer(url) else { return false }
        return o["statusLine"] != nil && !lineaNuestra(o)
    }

    static func instalado(en url: URL, comando cmd: String) -> Bool {
        guard let h = (try? leer(url))?["hooks"] as? [String: Any] else { return false }
        return eventos.allSatisfy { ((h[$0] as? [Any]) ?? []).contains { usa($0, cmd) } }
    }

    // Lo que hacen los botones: instalar, pero nunca desde una copia que va a desaparecer.
    static func conectar(en url: URL, comando cmd: String, linea: String?) throws {
        if sinMover { throw Fallo.sinMover }
        try instalar(en: url, comando: cmd, linea: linea)
    }

    static func instalar(en url: URL, comando cmd: String, linea: String? = nil) throws {
        var o = try leer(url)
        var h = sinHooks(o["hooks"] as? [String: Any] ?? [:]) { esHook($0) && $0["command"] as? String != cmd }
        for e in eventos {
            var grupos = h[e] as? [Any] ?? []
            guard !grupos.contains(where: { usa($0, cmd) }) else { continue }
            grupos.append(["hooks": [["type": "command", "command": cmd, "timeout": plazo(e)]]])
            h[e] = grupos
        }
        o["hooks"] = h
        if let linea, o["statusLine"] == nil || lineaNuestra(o) { o["statusLine"] = ["type": "command", "command": linea, "padding": 0] }
        try escribir(o, url)
    }

    static func quitar(en url: URL) throws {
        var o = try leer(url)
        if lineaNuestra(o) { o["statusLine"] = nil }
        let h = sinHooks(o["hooks"] as? [String: Any] ?? [:], esHook)
        o["hooks"] = h.isEmpty ? nil : h
        try escribir(o, url)
    }

    private static func sinHooks(_ entrada: [String: Any], _ fuera: ([String: Any]) -> Bool) -> [String: Any] {
        var h = entrada
        for (e, v) in h {
            guard let grupos = v as? [Any] else { continue }
            let quedan: [Any] = grupos.compactMap { g in
                guard var g = g as? [String: Any], let lista = g["hooks"] as? [[String: Any]] else { return g }
                let resto = lista.filter { !fuera($0) }
                if resto.isEmpty { return nil }
                g["hooks"] = resto
                return g
            }
            h[e] = quedan.isEmpty ? nil : quedan
        }
        return h
    }
}
