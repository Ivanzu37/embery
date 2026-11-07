import Foundation
import Testing
@testable import Embery

@Test func ajustesNoIncluyenRutasPersonales() {
    let ajustes = Ajustes()
    #expect(!ajustes.boveda.contains("/Volumes"))
    #expect(ajustes.boveda.isEmpty)
    #expect(ajustes.carpetaSesiones == "embery")
}

@Test func escriturasSinBovedaNoCreanArchivos() {
    let fm = FileManager.default
    let antes = Set((try? fm.contentsOfDirectory(atPath: fm.currentDirectoryPath)) ?? [])
    var ajustes = Ajustes()
    ajustes.boveda = ""
    let ahora = Date()
    let sesion = Sesion(inicio: ahora, fin: ahora, modo: .temporizador, segundos: 60, pausas: 0,
                        tarea: "Prueba", bloqueos: 0)
    let captura = Captura(texto: "Prueba", fecha: ahora)

    #expect(!Registro.escribir(sesion, ajustes))
    #expect(!Capturas.escribir(captura, ajustes))
    #expect(Set((try? fm.contentsOfDirectory(atPath: fm.currentDirectoryPath)) ?? []) == antes)
}

@Test func ajustesCodificadosConservanLaBovedaElegida() throws {
    var ajustes = Ajustes()
    ajustes.boveda = "/Users/alguien/Notas"
    let datos = try JSONEncoder().encode(ajustes)
    let decodificados = try JSONDecoder().decode(Ajustes.self, from: datos)
    #expect(decodificados.boveda == "/Users/alguien/Notas")
}

@Test func rutaVaciaNoVigilaUnVolumen() {
    #expect(Vault.volumen(de: "") == nil)
    #expect(Hueco(boveda: "", claude: false).raices == nil)
}
