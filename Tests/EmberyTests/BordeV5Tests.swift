import Foundation
import Testing
@testable import Embery

@Test func etiquetaAbreQuietaYCierra() {
    #expect(etiquetaK(-1, reducir: false) == 0)
    #expect(etiquetaK(0.25, reducir: false) == 0.5)
    #expect(etiquetaK(0.5, reducir: false) == 1)
    #expect(etiquetaK(3.4, reducir: false) == 1)
    #expect(abs(etiquetaK(3.725, reducir: false) - 0.5) < 1e-9)
    #expect(etiquetaK(3.95, reducir: false) == 0)
    #expect(etiquetaK(0.1, reducir: true) == 0.5)
    #expect(etiquetaK(3.1, reducir: true) == 1)
    #expect(etiquetaK(3.4, reducir: true) == 0)
}

@Test func nombreLargoSeRecortaHastaCaber() {
    #expect(Lienzo.recortar("web", cabe: 78, tamano: 11, peso: .medium) == "web")
    let r = Lienzo.recortar("rediseño-de-la-pagina-principal", cabe: 78, tamano: 11, peso: .medium)
    #expect(r.hasSuffix("…"))
    #expect(Lienzo.ancho(r, tamano: 11, peso: .medium) <= 78)
}
