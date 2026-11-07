import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Embery

// Imita el modo ?act= del prototipo: paso fijo y diagnóstico solo en el último medio segundo de cada tramo.
private func avanzar(_ e: Escribiente, _ tramos: [(String, Double)]) -> (falta: Double, choque: Double) {
    let dt = 1.0 / 60
    var falta = 0.0, choque = 0.0
    for (nombre, seg) in tramos {
        if nombre == "prompt" || nombre == "stop" { e.evento(nombre) } else { e.setActividad(nombre) }
        let pasos = Int((seg / dt).rounded(.up))
        for i in 0..<pasos {
            e.actualizar(dt)
            if Double(i) > seg / dt - 30 { falta = max(falta, e.falta); choque = max(choque, e.choque) }
        }
    }
    return (falta, choque)
}

struct EscribienteTests {
    static let actividades = ["escribe", "hojea", "mecanismo", "ventana", "ayudante", "piensa", "mano", "descansa", "cabecea", "duerme"]
    static let secuencias: [[(String, Double)]] = [
        [("escribe", 8), ("stop", 2.4)], [("descansa", 3), ("prompt", 0.6)], [("hojea", 2)], [("duerme", 20)],
    ]

    @Test func alcanzaYNoChoca() {
        var casos = Self.actividades.map { [($0, 8.0)] }
        casos += Self.secuencias
        for tramos in casos {
            let e = Escribiente()
            let d = avanzar(e, tramos)
            let nombre = tramos.map { "\($0.0):\($0.1)" }.joined(separator: ",")
            #expect(d.falta < 0.05 && d.choque < 0.05, "\(nombre): falta \(d.falta), choque \(d.choque), incl \(e.incl)")
        }
    }

    @Test func plumaVaYVuelve() {
        let e = Escribiente()
        _ = avanzar(e, [("escribe", 4)])
        #expect(e.plumaEnMano)
        _ = avanzar(e, [("descansa", 4)])
        #expect(!e.plumaEnMano)
    }

    @Test func eventosYPendiente() {
        let e = Escribiente()
        e.evento("stop")
        for _ in 0..<240 { e.actualizar(1.0 / 60) }
        #expect(e.act == "descansa")

        let f = Escribiente()
        f.evento("prompt")
        for _ in 0..<18 { f.actualizar(1.0 / 60) }
        f.setActividad("hojea")
        for _ in 0..<60 { f.actualizar(1.0 / 60) }
        #expect(f.act == "hojea")
    }

    // Solo con ESCRIBIENTE_CAPTURAS=<carpeta>: pinta la sala con una mesa a 960×330 para compararla con el prototipo.
    @Test func capturas() throws {
        guard let carpeta = ProcessInfo.processInfo.environment["ESCRIBIENTE_CAPTURAS"] else { return }
        let casos: [(String, Double?, Double?)] = [
            ("escribe:6", nil, nil), ("hojea:2", nil, nil), ("hojea:5", nil, nil), ("mecanismo:7", nil, nil), ("ventana:4", nil, nil),
            ("ayudante:6", nil, nil), ("piensa:4", nil, nil), ("mano:4", nil, nil), ("descansa:4", nil, nil), ("cabecea:5", nil, nil),
            ("duerme:4", nil, nil), ("duerme:20", nil, nil), ("escribe:8,stop:2.4", nil, nil), ("descansa:3,prompt:0.5", nil, nil),
            ("escribe:4", 0.9, nil), ("descansa:4", nil, 0.85),
        ]
        for (acts, contexto, bloque) in casos {
            let tramos = acts.split(separator: ",").map { tramo -> (String, Double) in
                let p = tramo.split(separator: ":"); return (String(p[0]), Double(p[1])!)
            }
            let sala = Scriptorium()
            let e = sala.mesas[0].e
            e.t = 0.9661652850760917
            e.tareas(["hecha", "hecha", "curso", "pendiente", "pendiente"].enumerated().map { Tarea(clave: "\($0.offset)", texto: "", estado: Tarea.Estado(rawValue: $0.element)!) })
            if let contexto { e.ctxObj = contexto; e.contexto = contexto }
            sala.ponerBloque(bloque ?? 0.25)
            _ = avanzar(e, tramos)
            let c = CGContext(data: nil, width: 960, height: 330, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.translateBy(x: 0, y: 330); c.scaleBy(x: 1, y: -1)
            c.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 960, height: 330))
            let l = Lienzo(c)
            l.scale(3, 3); sala.pintar(l, ancho: 320, escala: 3)
            var nombre = acts.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ",", with: "_")
            if contexto != nil { nombre += "_contexto90" }
            if bloque != nil { nombre += "_bloque85" }
            let url = URL(fileURLWithPath: carpeta).appendingPathComponent(nombre + ".png")
            let destino = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destino, try #require(c.makeImage()), nil)
            #expect(CGImageDestinationFinalize(destino), "\(nombre)")
        }
        // Dos mesas con un ayudante, como ?sesiones=2&acts=escribe,hojea&ctx=62,30&ayud=1,0&fijo=6 de la maqueta.
        let sala = Scriptorium()
        var a = SessionInfo(id: "a", project: "mi-boveda"), b = SessionInfo(id: "b", project: "proyecto-web")
        a.state = .working; a.tool = "Edit"; a.ctx = 62; a.ayudantes = 1; a.lastEvent = Date().addingTimeInterval(-5)
        b.state = .working; b.tool = "Read"; b.ctx = 30
        a.tareas = [Tarea(clave: "1", texto: "", estado: .hecha), Tarea(clave: "2", texto: "", estado: .curso), Tarea(clave: "3", texto: "", estado: .pendiente)]
        sala.sincronizar([a, b]); sala.ponerBloque(0.48)
        for _ in 0..<180 { sala.actualizar(1.0 / 30) }
        let w = Int(Scriptorium.ancho(mesas: 2) * 3)
        let c = CGContext(data: nil, width: w, height: 330, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.translateBy(x: 0, y: 330); c.scaleBy(x: 1, y: -1)
        let l = Lienzo(c); l.scale(3, 3); sala.pintar(l, ancho: Double(w) / 3, escala: 3)
        let url = URL(fileURLWithPath: carpeta).appendingPathComponent("dos-mesas.png")
        let destino = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destino, try #require(c.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destino))
    }
}
