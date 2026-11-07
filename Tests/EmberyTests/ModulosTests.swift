import Foundation
import Testing
@testable import Embery

private let plantilla = "---\ntags: [nota]\ncreated: {{date}}\n---\n# {{title}}\n\n(lo que sea, rápido)\n\n## 🔗 Relacionado\n- [[ ]]"
private let c = Captura(texto: "Ideas para el Hueco\nsegunda línea", fecha: Date(timeIntervalSince1970: 1_792_000_000))

@Test func capturaConPlantilla() {
    let n = Capturas.nota(c, plantilla: plantilla)
    #expect(n.contains("tags: [nota, idea]"))
    #expect(n.contains("# Ideas para el Hueco\n\nIdeas para el Hueco\nsegunda línea"))
    #expect(!n.contains("(lo que sea"))
    #expect(n.contains("## 🔗 Relacionado"))
}

@Test func capturaSinPlantilla() {
    #expect(Capturas.nota(c, plantilla: nil).hasPrefix("---\ntags: [nota, idea]"))
}

@Test func nombreEnMinusculasConGuiones() {
    let a = Capturas.archivo(Captura(texto: "¿Qué tal, Árbol?", fecha: c.fecha))
    #expect(a.hasSuffix("-que-tal-arbol.md"))
}

@Test func respiracionPorFases() throws {
    let r = Respiracion(clave: "caja", inicio: 100)
    #expect(r.en(99) == nil)
    let e = try #require(r.en(101))
    #expect(e.texto == "Inhala" && e.fase == 0 && e.lleno > 0 && e.lleno < 1)
    #expect(try #require(r.en(106)).texto == "Sostén")
    #expect(try #require(r.en(116.5)).ciclo == 2)
    #expect(r.en(100 + PATRONES[0].duracion) == nil)
}
