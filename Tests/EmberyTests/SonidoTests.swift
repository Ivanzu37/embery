import Foundation
import Testing
@testable import Embery

// Ningún sonido se corta mientras se oye ni pasa del pico bajo de serie.
@Test(arguments: Sonido.Evento.allCases)
func caeHastaElSilencio(_ e: Sonido.Evento) {
    for s in Sonido.variantes {
        let x = Sonido.muestras(e, semitonos: s)
        let cola = x.suffix(Int(Sonido.sr * 0.01)).map(abs).max() ?? 1
        #expect(cola < 0.002, "\(e) \(s): la cola acaba en \(cola)")
        #expect((x.map(abs).max() ?? 0) <= Sonido.pico + 1e-9)
    }
}

// Los ajustes de sonido son nuevos: un datos.json anterior, sin ellos, tiene que seguir leyéndose.
@Test func ajustesAntiguosSinSonido() throws {
    let viejo = try JSONEncoder().encode(Ajustes())
    var obj = try #require(JSONSerialization.jsonObject(with: viejo) as? [String: Any])
    for k in ["sonido", "volumen", "silencioFoco"] { obj[k] = nil }
    let a = try JSONDecoder().decode(Ajustes.self, from: JSONSerialization.data(withJSONObject: obj))
    #expect(a.sonido == nil && a.volumen == nil)
}
