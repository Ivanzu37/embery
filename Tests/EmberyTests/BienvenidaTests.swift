import Foundation
import Testing
import SwiftUI
import AppKit
@testable import Embery

@Test func instalacionNuevaEnsenaLaBienvenida() {
    #expect(Datos().ajustes.bienvenidaVista == nil)
}

@Test func datosDeAntesNoEnsenanLaBienvenida() throws {
    let viejo = try JSONEncoder().encode(Datos())
    #expect(try Almacen.leer(viejo).ajustes.bienvenidaVista == true)
}

@Test func bienvenidaCerradaNoVuelve() throws {
    var d = Datos(); d.ajustes.bienvenidaVista = true
    let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
    #expect(try Almacen.leer(e.encode(d)).ajustes.bienvenidaVista == true)
}

// Solo con EMBERY_CAPTURAS=<carpeta> (y EMBERY_DIR aparte): deja un PNG por paso para revisarlos a ojo.
@MainActor @Test func capturasBienvenida() throws {
    guard let dir = ProcessInfo.processInfo.environment["EMBERY_CAPTURAS"] else { return }
    let m = Embery()
    for paso in 1...3 {
        m.pasoBienvenida = paso
        let r = ImageRenderer(content: BienvenidaVista(m: m, lumen: Buho()).frame(width: 310).padding(12).background(Color.black))
        r.scale = 2
        let img = try #require(r.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:]))
        try img.write(to: URL(fileURLWithPath: dir).appendingPathComponent("bienvenida-\(paso).png"))
    }
}
