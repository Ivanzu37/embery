import Foundation
import Testing
@testable import Embery

@Test func ajustesAntiguosSinScriptorium() throws {
    let viejo = try JSONEncoder().encode(Ajustes())
    var obj = try #require(JSONSerialization.jsonObject(with: viejo) as? [String: Any])
    obj["scriptoriumAbierto"] = nil
    let a = try JSONDecoder().decode(Ajustes.self, from: JSONSerialization.data(withJSONObject: obj))
    #expect(a.scriptoriumAbierto == nil)
    var b = Ajustes()
    b.scriptoriumAbierto = true
    let c = try JSONDecoder().decode(Ajustes.self, from: JSONEncoder().encode(b))
    #expect(c.scriptoriumAbierto == true)
}

@Test func actividadPorHerramienta() {
    var s = SessionInfo(id: "a", project: "p")
    s.state = .working
    for (tool, esperada) in [("Read", Actividad.hojea), ("Edit", .escribe), ("Agent", .ayudante), ("pensando", .piensa)] {
        s.tool = tool
        #expect(Actividad.de(s, ahora: Date()) == esperada)
    }
    s.state = .perm
    #expect(Actividad.de(s, ahora: Date()) == .mano)
    #expect(Actividad.de(nil, ahora: Date()) == .duerme)
}

@Test func actividadEnReposo() {
    let ahora = Date(timeIntervalSince1970: 1_000_000)
    var s = SessionInfo(id: "a", project: "p")
    s.state = .idle
    for (hace, esperada) in [(30.0, Actividad.descansa), (300, .cabecea), (1200, .duerme)] {
        s.lastEvent = ahora.addingTimeInterval(-hace)
        #expect(Actividad.de(s, ahora: ahora) == esperada)
    }
}

@Test func sesionPrincipalYVista() {
    var vieja = SessionInfo(id: "v", project: "p")
    vieja.state = .perm
    vieja.lastEvent = Date().addingTimeInterval(-500)
    var nueva = SessionInfo(id: "n", project: "p")
    nueva.state = .working
    #expect(Actividad.principal([nueva, vieja])?.id == "v")

    let h = Hueco(boveda: "", claude: true)
    h.scriptorium = true
    #expect(h.vista == .scriptorium)
    h.abierto = true
    #expect(h.vista == .abierto)

    let sin = Hueco(boveda: "", claude: false)
    sin.scriptorium = true
    #expect(sin.vista == .reposo)
}
