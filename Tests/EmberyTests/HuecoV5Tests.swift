import Foundation
import Testing
@testable import Embery

@Test func teEsperanCuentaPorSesion() {
    var e = Espera()
    e.anotar(hecho: "a", permisos: [])
    e.anotar(hecho: "a", permisos: ["b"])
    e.anotar(hecho: "", permisos: ["b", "c"])
    // «c» se contestó en la terminal antes de acabar el foco.
    let fin = e.alTerminar(enPermiso: ["b"])
    #expect(fin.conversaciones == 2)
    #expect(fin.texto == "2 conversaciones · 1 permiso")
    #expect(Espera(hechas: ["a"]).texto == "1 conversación")
    #expect(Espera().alTerminar(enPermiso: ["x"]).vacia)
}

@Test func claudeCodeEnUnaCarpetaConComillas() {
    let g = Focus.guion("/tmp/Mi \"raro\" 'dir'", terminal: nil)!
    #expect(g.contains("tell application \"Terminal\""))
    #expect(g.contains(#"do script "cd '/tmp/Mi \"raro\" '\\''dir'\\''' && claude""#))
    #expect(Focus.guion("/x", terminal: "iterm")!.contains("write text \"cd '/x' && claude\""))
    #expect(Focus.guion("/x", terminal: "app") == nil)
}

@Test func ramaDesdeHead() throws {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("embery-rama-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: d.appendingPathComponent(".git"), withIntermediateDirectories: true)
    #expect(GitEstado.rama(d) == nil)
    try "ref: refs/heads/semana-3\n".write(to: d.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
    #expect(GitEstado.rama(d) == "semana-3")
    try "4f21472a\n".write(to: d.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
    #expect(GitEstado.rama(d) == nil)
}

@Test func fechasRelativas() {
    let ahora = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
    #expect(relativo(ahora.addingTimeInterval(-20), ahora) == "ahora")
    #expect(relativo(ahora.addingTimeInterval(-12 * 60), ahora) == "hace 12 min")
    #expect(relativo(ahora.addingTimeInterval(-3 * 3600), ahora) == "hace 3 h")
    #expect(relativo(ahora.addingTimeInterval(-24 * 3600), ahora) == "ayer")
    #expect(hace(ahora.addingTimeInterval(-42), ahora) == "hace 42 s")
}

@Test func pendientesSegunLaBoveda() throws {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("embery-pend-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
    var a = Ajustes()
    #expect(Pendientes.leer(a) == .app)
    a.boveda = raiz.path; a.notaDiaria = "{fecha}.md"
    // Sin nota de hoy, la lista de la app.
    #expect(Pendientes.leer(a) == .app)
    try "# Hoy\n- [ ] Uno\n- [x] Dos\n".write(to: Boveda.diaria(a)!, atomically: true, encoding: .utf8)
    #expect(Pendientes.leer(a).casillas?.map(\.texto) == ["Uno", "Dos"])
    a.obsidian = false
    #expect(Pendientes.leer(a) == .app)
}
