import Foundation
import Testing
@testable import Embery

@Test func pantallaElegidaAunqueOtraTengaNotch() {
    #expect(Pantallas.indice(elegida: "B", ids: ["A", "B"], notch: [true, false]) == 1)
}

@Test func pantallaAutomaticaEligeLaPrimeraConNotch() {
    #expect(Pantallas.indice(elegida: nil, ids: ["A", "B", "C"], notch: [false, true, true]) == 1)
}

@Test func pantallaSinNotchUsaLaPrimera() {
    #expect(Pantallas.indice(elegida: nil, ids: ["A", "B"], notch: [false, false]) == 0)
}

@Test func pantallaDesconectadaCaeAAutomaticaYToleraIdsNulos() {
    #expect(Pantallas.indice(elegida: "X", ids: [nil, "B", nil], notch: [false, true, false]) == 1)
    #expect(Pantallas.indice(elegida: "X", ids: [nil, nil], notch: [false, false]) == 0)
}

@Test func ajustesAntiguosSinPantallaNiClaudeCode() throws {
    let json = """
    {"sesiones": [], "compras": [], "bloqueos": [],
     "ajustes": {"lado": "der", "abrirAlIniciar": true, "espirituEscritorio": true, "seguirHora": true, "objetivoMin": 180,
                 "duracionMin": 50, "descansoMin": 10, "rondas": 2, "tarea": "Programación", "bloquear": true,
                 "boveda": "/boveda", "carpetaSesiones": "sesiones", "lineaDiaria": true, "notaSesion": true}}
    """
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    let datos = try d.decode(Datos.self, from: Data(json.utf8))
    #expect(datos.ajustes.pantalla == nil)
    #expect(datos.ajustes.claudeCode == nil)
}

@Test func pantallaYClaudeCodeSobrevivenCodificacion() throws {
    var datos = Datos()
    datos.ajustes.pantalla = "ABC"
    datos.ajustes.claudeCode = false
    let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    let r = try d.decode(Datos.self, from: e.encode(datos))
    #expect(r.ajustes.pantalla == "ABC")
    #expect(r.ajustes.claudeCode == false)
}
