import Foundation
import Testing
@testable import Embery

private func apunte(_ modo: Modo, segundos: Double, hace: Double, appID: String? = nil) -> Sesion {
    let fin = Date().addingTimeInterval(-hace)
    return Sesion(inicio: fin.addingTimeInterval(-segundos), fin: fin, modo: modo, segundos: segundos, pausas: 1, tarea: "Hesia",
                  app: appID == nil ? nil : "Editor", appID: appID, bloqueos: 2, proyecto: "embery")
}

@Test func soloSeRetomaUnApunteReciente() {
    #expect(Embery.reciente(apunte(.cronometro, segundos: 600, hace: 20)))
    #expect(!Embery.reciente(apunte(.cronometro, segundos: 600, hace: 121)))
}

@Test func elFocoRetomadoSigueDondeIba() throws {
    let s = apunte(.cronometro, segundos: 1800, hace: 10)
    let f = try #require(Embery.foco(retomando: s, Ajustes(), app: nil))
    #expect(f.id == s.id && f.inicio == s.inicio && f.segundos == 1800)
    #expect(f.pausas == 1 && f.bloqueos == 2 && f.tarea == "Hesia" && f.proyecto?.nombre == "embery")
}

// 50 min por ronda y 2 rondas de serie: con 70 min hechos va por la segunda; con 200, no pasa de la última.
@Test func elTemporizadorVuelveASuRonda() throws {
    var a = Ajustes(); a.duracionMin = 50; a.rondas = 2
    #expect(try #require(Embery.foco(retomando: apunte(.temporizador, segundos: 70 * 60, hace: 5), a, app: nil)).ronda == 2)
    #expect(try #require(Embery.foco(retomando: apunte(.temporizador, segundos: 200 * 60, hace: 5), a, app: nil)).ronda == 2)
    #expect(try #require(Embery.foco(retomando: apunte(.temporizador, segundos: 10 * 60, hace: 5), a, app: nil)).ronda == 1)
}

@Test func enModoAppSinLaAppNoSeRetoma() {
    #expect(Embery.foco(retomando: apunte(.app, segundos: 300, hace: 5, appID: "com.ejemplo.cerrada"), Ajustes(), app: nil) == nil)
}
