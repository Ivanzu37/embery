import Testing
import Foundation
@testable import Embery

@Test func ocupaElGuionVacioDeLaPlantilla() {
    let diaria = "# Hoy\n\n## 📓 Registro\n- \n\n## 🔗 Relacionado\n- [[inicio]]"
    let r = Registro.insertar("- 10:30–11:20 · foco 50 min", en: diaria)
    #expect(r == "# Hoy\n\n## 📓 Registro\n- 10:30–11:20 · foco 50 min\n\n## 🔗 Relacionado\n- [[inicio]]")
}

@Test func vaDetrasDeLaUltimaLinea() {
    let diaria = "## 📓 Registro\n- a\n\n## Otra"
    #expect(Registro.insertar("- b", en: diaria) == "## 📓 Registro\n- a\n- b\n\n## Otra")
}

@Test func creaLaSeccionAntesDeRelacionado() {
    #expect(Registro.insertar("- b", en: "# Hoy\n## 🔗 Relacionado") == "# Hoy\n## 📓 Registro\n- b\n\n## 🔗 Relacionado")
}

@Test func subdominiosSiImitacionesNo() {
    let lista = [Bloqueado(nombre: "Instagram", web: "instagram.com")]
    #expect(webBloqueada("https://www.instagram.com/reels", lista) != nil)
    #expect(webBloqueada("https://m.instagram.com", lista) != nil)
    #expect(webBloqueada("https://notinstagram.com", lista) == nil)
}

@Test func reescribirNoTocaLoQueNoLee() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("embery-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let rota = dir.appendingPathComponent("rota.md"), bytes = Data([0xFF, 0xFE, 0x00, 0xD8])
    try bytes.write(to: rota)
    #expect(!Boveda.reescribir(rota) { $0 + "x" })
    #expect(try Data(contentsOf: rota) == bytes)
    let buena = dir.appendingPathComponent("buena.md")
    try "a".write(to: buena, atomically: true, encoding: .utf8)
    #expect(Boveda.reescribir(buena) { $0 + "b" })
    #expect(try String(contentsOf: buena, encoding: .utf8) == "ab")
}
