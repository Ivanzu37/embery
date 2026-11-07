// Los límites del plan solo llegan cuando Claude responde: la statusline solo corre en la terminal, y el
// historial de Claude desktop deja de escribirse con la app cerrada. Una pregunta mínima a Haiku los trae
// en su rate_limit_event (~4k tokens del plan; probado con Claude Code 2.1.319 el 2026-11-07).
import Foundation

final class ConsultaUso {
    static let cada: TimeInterval = 15 * 60
    var alLimite: ([String: Any]) -> Void = { _ in }
    private var proc: Process?
    private var ultima = Date.distantPast

    func lanza() {
        // una a la vez, y nunca más de una cada 15 min aunque falle
        guard proc == nil, Date().timeIntervalSince(ultima) >= Self.cada else { return }
        ultima = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // sin ajustes ni MCP ni herramientas: no salta ningún hook (no sale como sesión) y no se guarda
        p.arguments = ["-lc", "exec claude -p --model haiku --output-format stream-json --verbose --no-session-persistence --setting-sources '' --strict-mcp-config --tools ''"]
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        env["ANTHROPIC_API_KEY"] = nil   // con la clave iría a la API, que no tiene estos límites
        p.environment = env
        let ent = Pipe(), sal = Pipe()
        p.standardInput = ent; p.standardOutput = sal; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return }
        proc = p
        try? ent.fileHandleForWriting.write(contentsOf: Data("Reply only: ok".utf8))
        try? ent.fileHandleForWriting.close()
        // se lee hasta el final fuera del hilo principal: así la tubería nunca se llena y el proceso no se atasca
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let d = sal.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            DispatchQueue.main.async {
                self?.proc = nil
                for l in d.split(separator: 0x0A) {
                    if let o = try? JSONSerialization.jsonObject(with: l) as? [String: Any], o["type"] as? String == "rate_limit_event" { self?.alLimite(o) }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { if p.isRunning { p.terminate() } }
    }
}
