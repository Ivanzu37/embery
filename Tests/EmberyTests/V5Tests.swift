import Foundation
import Testing
@testable import Embery

private func temporal(_ nombre: String) throws -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("embery-\(nombre)-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@Test func datosAntiguosSeLeenConLosCamposNuevos() throws {
    let viejo = #"{"lado":"der","abrirAlIniciar":true,"espirituEscritorio":true,"seguirHora":true,"objetivoMin":180,"duracionMin":50,"descansoMin":10,"rondas":2,"tarea":"x","bloquear":true,"boveda":"","carpetaSesiones":"embery","lineaDiaria":true,"notaSesion":true}"#
    let a = try JSONDecoder().decode(Ajustes.self, from: Data(viejo.utf8))
    #expect(a.entrada == "inbox")
    #expect(a.patronDiaria == "daily-notes/{fecha}.md")
    let s = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","inicio":0,"fin":60,"modo":"temporizador","segundos":60,"pausas":0,"tarea":"x","bloqueos":0,"registrada":true}"#
    #expect(try JSONDecoder().decode(Sesion.self, from: Data(s.utf8)).proyecto == nil)
}

@Test func casillasDeLaNotaDiaria() {
    let nota = "# Hoy\n- [ ] Llamar\n  - [x] Hecha\n- [] mal\n- texto\n* [ ] Otra\n\n## Notas"
    let c = Boveda.casillas(nota)
    #expect(c.map(\.texto) == ["Llamar", "Hecha", "Otra"])
    #expect(c.map(\.hecha) == [false, true, false])
    let marcada = Boveda.marcar(c[0], true, en: nota)!
    #expect(marcada == nota.replacingOccurrences(of: "- [ ] Llamar", with: "- [x] Llamar"))
    // Si la línea se movió, la encuentra por su texto.
    let movida = "nueva línea\n" + nota
    #expect(Boveda.marcar(c[1], false, en: movida)!.contains("  - [ ] Hecha"))
    #expect(Boveda.marcar(Boveda.Casilla(linea: 0, texto: "No existe", hecha: false), true, en: nota) == nil)
    #expect(Boveda.anadir("Nueva", en: nota).components(separatedBy: "\n")[6] == "- [ ] Nueva")
    #expect(Boveda.anadir("Nueva", en: "# Vacía\n\n") == "# Vacía\n- [ ] Nueva\n")
}

@Test func notaDiariaConPatronYArchivo() throws {
    let raiz = try temporal("boveda")
    var a = Ajustes(); a.boveda = raiz.path; a.notaDiaria = "diario/{fecha}.md"
    let dia = Date(timeIntervalSince1970: 1_800_000_000)
    let u = Boveda.diaria(a, dia)!
    #expect(u.path.hasSuffix("diario/\(Registro.fecha(dia, "yyyy-MM-dd")).md"))
    try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "- [ ] Uno\n".write(to: u, atomically: true, encoding: .utf8)
    let c = Boveda.leerCasillas(a, dia)!
    #expect(Boveda.marcar(c[0], true, a, dia))
    #expect(Boveda.anadir("Dos", a, dia))
    #expect(try String(contentsOf: u, encoding: .utf8) == "- [x] Uno\n- [ ] Dos\n")
    try "x".write(to: raiz.appendingPathComponent("vieja.md"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: raiz.appendingPathComponent("templates"), withIntermediateDirectories: true)
    try "x".write(to: raiz.appendingPathComponent("templates/plantilla.md"), atomically: true, encoding: .utf8)
    let r = Boveda.recientes(raiz.path)
    #expect(Set(r.map { $0.url.lastPathComponent }) == ["vieja.md", u.lastPathComponent])
    #expect(r.first { $0.url.lastPathComponent == u.lastPathComponent }?.carpeta == "diario")
    #expect(Boveda.urlObsidian(u)!.absoluteString.hasPrefix("obsidian://open?path=/"))
}

@Test func proyectosDeWorkspaceStorage() throws {
    let storage = try temporal("ws"), a = try temporal("proyecto-a"), b = try temporal("proyecto-b")
    func ws(_ n: String, _ folder: String, _ hace: TimeInterval) throws {
        let d = storage.appendingPathComponent(n, isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try Data(#"{"folder":"\#(folder)"}"#.utf8).write(to: d.appendingPathComponent("workspace.json"))
        try Data().write(to: d.appendingPathComponent("state.vscdb"))
        for f in ["workspace.json", "state.vscdb"] {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-hace)], ofItemAtPath: d.appendingPathComponent(f).path)
        }
    }
    try ws("1", a.absoluteString, 300)
    try ws("2", b.absoluteString, 10)
    try ws("3", "vscode-remote://ssh-remote+host/srv", 1)
    try ws("4", "file:///no/existe", 1)
    let r = EditorRecientes.leer(storage)
    #expect(r.map(\.nombre) == [b.lastPathComponent, a.lastPathComponent])
}

@Test func cambiosSinCommit() throws {
    let repo = try temporal("git")
    #expect(GitEstado.cambios(en: repo) == nil)
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = ["-C", repo.path, "init", "-q"]
    try p.run(); p.waitUntilExit()
    #expect(GitEstado.cambios(en: repo) == 0)
    try "a".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "b".write(to: repo.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    #expect(GitEstado.cambios(en: repo) == 2)
}

@Test func jornadaDescuentaHuecosYCuentaHerramientas() throws {
    let root = try temporal("claude"), dir = root.appendingPathComponent("proyecto", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func ts(_ s: Double) -> String { TokenLedger.iso.string(from: t0.addingTimeInterval(s)) }
    let lineas = [
        #"{"type":"user","timestamp":"\#(ts(0))"}"#,
        #"{"type":"assistant","timestamp":"\#(ts(600))","message":{"content":[{"type":"tool_use","id":"a","name":"Read"}]}}"#,
        #"{"type":"assistant","timestamp":"\#(ts(600))","message":{"content":[{"type":"tool_use","id":"a","name":"Read"},{"type":"tool_use","id":"b","name":"Bash"}]}}"#,
        #"{"type":"assistant","timestamp":"\#(ts(700))","isSidechain":true,"message":{"content":[{"type":"tool_use","id":"c","name":"Grep"}]}}"#,
        #"{"type":"user","timestamp":"\#(ts(600 + 3600))"}"#,
        #"{"type":"assistant","timestamp":"\#(ts(600 + 3600 + 120))","message":{"content":[{"type":"tool_use","id":"d","name":"Read"}]}}"#,
    ]
    try lineas.joined(separator: "\n").write(to: dir.appendingPathComponent("uno.jsonl"), atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: t0.addingTimeInterval(4000)], ofItemAtPath: dir.appendingPathComponent("uno.jsonl").path)
    try #"{"type":"user","timestamp":"\#(ts(-86400 * 3))"}"#.write(to: dir.appendingPathComponent("vieja.jsonl"), atomically: true, encoding: .utf8)
    let dia = TokenLedger.dayFormat.string(from: t0)
    let j = Jornada.calcular(desde: t0.addingTimeInterval(-60), hasta: t0.addingTimeInterval(86400 / 2), root: root.path, tokensPorDia: [dia: 1200])
    #expect(j.conversaciones == 1)
    #expect(j.segundos == 720)
    #expect(j.herramientas.map(\.nombre) == ["Read", "Bash"])
    #expect(j.herramientas.map(\.veces) == [2, 1])
    #expect(j.tokens == 1200)
}

@Test func instaladorAnadeYQuitaSinTocarLoDemas() throws {
    let url = try temporal("settings").appendingPathComponent("settings.json")
    try Data(#"{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"otro"}]}]}}"#.utf8).write(to: url)
    let cmd = InstaladorHook.comando(hook: "/Apps/Embery.app/Contents/Resources/embery-hook", socket: "/tmp/e.sock")
    #expect(!InstaladorHook.instalado(en: url, comando: cmd))
    try InstaladorHook.instalar(en: url, comando: cmd)
    try InstaladorHook.instalar(en: url, comando: cmd)
    #expect(InstaladorHook.instalado(en: url, comando: cmd))
    var o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var h = o["hooks"] as! [String: Any]
    #expect((h["Stop"] as! [Any]).count == 2)
    let permiso = ((h["PermissionRequest"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
    #expect(permiso["timeout"] as? Int == 90)
    #expect(o["model"] as? String == "x")
    try InstaladorHook.quitar(en: url)
    o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    h = o["hooks"] as! [String: Any]
    #expect(Array(h.keys) == ["Stop"])

    // Un embery-hook viejo (otra ruta, sin socket) se sustituye; la statusline va si no hay otra.
    try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"'/viejo/embery-hook'"}]}]}}"#.utf8).write(to: url)
    let linea = InstaladorHook.comando(hook: "/Apps/Embery.app/Contents/Resources/embery-status", socket: "/tmp/e.sock")
    try InstaladorHook.instalar(en: url, comando: cmd, linea: linea)
    o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    #expect(((o["hooks"] as! [String: Any])["Stop"] as! [Any]).count == 1)
    #expect((o["statusLine"] as? [String: Any])?["command"] as? String == linea)
    try InstaladorHook.quitar(en: url)
    o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    #expect(o["statusLine"] == nil && o["hooks"] == nil)
    // Una statusline ajena no se pisa ni se quita.
    try Data(#"{"statusLine":{"type":"command","command":"mia"}}"#.utf8).write(to: url)
    try InstaladorHook.instalar(en: url, comando: cmd, linea: linea)
    #expect(InstaladorHook.lineaAjena(en: url))
    try InstaladorHook.quitar(en: url)
    o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    #expect((o["statusLine"] as? [String: Any])?["command"] as? String == "mia")
    #expect(FileManager.default.fileExists(atPath: url.path + ".antes-de-embery"))
    try Data("no es json".utf8).write(to: url)
    #expect(throws: InstaladorHook.Fallo.self) { try InstaladorHook.instalar(en: url, comando: cmd) }
}

// El hook de verdad (Resources/embery-hook) contra el HookServer: Permitir, Denegar y sin respuesta.
@Test func permisoIdaYVuelta() throws {
    let hook = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/embery-hook").standardizedFileURL
    let sock = FileManager.default.temporaryDirectory.appendingPathComponent("eh-\(UUID().uuidString.prefix(6)).sock").path
    let server = HookServer(path: sock) { _ in }
    server.start()

    func pedir(_ decide: (String) -> Void) throws -> String {
        let id = UUID().uuidString
        let p = Process(), entrada = Pipe(), salida = Pipe()
        p.executableURL = hook; p.arguments = [sock]
        // el hook reenvía también a Hesia: sin esto, cada pasada deja permisos falsos en la cripta
        p.environment = ProcessInfo.processInfo.environment.merging(["HESIA_SOCKET": sock + ".sin-hesia"]) { _, n in n }
        p.standardInput = entrada; p.standardOutput = salida
        try p.run()
        let todo = ["Bash", "TodoWrite"][Int.random(in: 0...1)]
        entrada.fileHandleForWriting.write(Data(#"{"hook_event_name":"PermissionRequest","session_id":"\#(id)","tool_name":"\#(todo)","tool_input":{"command":"ls"}}"#.utf8))
        try entrada.fileHandleForWriting.close()
        let limite = Date().addingTimeInterval(5)
        while !server.esperando.contains(id), Date() < limite { usleep(20_000) }
        decide(id)
        p.waitUntilExit()
        return String(decoding: salida.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    let si = try pedir { #expect(server.responder($0, permitir: true)) }
    #expect(si == #"{"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}"#)
    let no = try pedir { #expect(server.responder($0, permitir: false)) }
    #expect(no.contains(#""behavior": "deny""#) && no.contains("message"))
    let nada = try pedir { server.soltar($0) }
    #expect(nada.isEmpty)
    #expect(!server.responder("ya-no-espera", permitir: true))
}

// Quien venía de ~/.vigil conserva sus cuentas; lo que ya hay en la carpeta nueva no se pisa y lo viejo se queda.
@Test func traeLasCuentasDeVigil() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("vigil-\(UUID().uuidString.prefix(6))")
    let viejo = base.appendingPathComponent("viejo"), nuevo = base.appendingPathComponent("nuevo")
    try FileManager.default.createDirectory(at: viejo, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: nuevo, withIntermediateDirectories: true)
    try Data("t".utf8).write(to: viejo.appendingPathComponent("tokens.json"))
    try Data("viejo".utf8).write(to: viejo.appendingPathComponent("limits.json"))
    try Data("nuevo".utf8).write(to: nuevo.appendingPathComponent("limits.json"))
    traerDeVigil(desde: viejo.path, a: nuevo.path)
    #expect(try String(contentsOf: nuevo.appendingPathComponent("tokens.json"), encoding: .utf8) == "t")
    #expect(try String(contentsOf: nuevo.appendingPathComponent("limits.json"), encoding: .utf8) == "nuevo")
    #expect(FileManager.default.fileExists(atPath: viejo.appendingPathComponent("tokens.json").path))
}
