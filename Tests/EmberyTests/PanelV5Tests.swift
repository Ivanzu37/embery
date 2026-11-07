import Foundation
import Testing
@testable import Embery

private func sesion(_ proyecto: String?, min: Double, nota: String? = nil, fin: Date = Date()) -> Sesion {
    Sesion(inicio: fin.addingTimeInterval(-min * 60), fin: fin, modo: .temporizador, segundos: min * 60, pausas: 0, tarea: "Programación",
           bloqueos: 0, proyecto: proyecto, nota: nota)
}

@Test func porProyectoOrdenaYJuntaElResto() {
    var d = Datos()
    d.sesiones = [sesion("a", min: 10), sesion("b", min: 50), sesion(nil, min: 5)] + (1...5).map { sesion("p\($0)", min: Double($0)) }
    let c = Cuentas(datos: d)
    let filas = c.porProyecto(c.semana)
    #expect(filas.map(\.nombre) == ["b", "a", "p5", "p4", "p3", nil])
    // Los dos más pequeños (2 y 1 min) se suman a «Sin proyecto».
    #expect(abs(filas.last!.minutos - 8) < 0.001)
    #expect(Cuentas(datos: Datos()).porProyecto(c.semana).isEmpty)
    var solo = Datos(); solo.sesiones = [sesion(nil, min: 20)]
    #expect(Cuentas(datos: solo).porProyecto(c.semana).isEmpty)
}

@Test func lineaDiariaConProyectoYNota() {
    let s = sesion("proyecto-web", min: 50, nota: "Cerré el formulario")
    let l = Registro.linea(s, enlace: "x")
    #expect(l.hasSuffix(" · foco 50 min · proyecto-web · ✦ 50 · Cerré el formulario · [[x]]"))
    #expect(!Registro.linea(sesion(nil, min: 50), enlace: nil).contains("·  ·"))
    #expect(Registro.linea(sesion(nil, min: 50), enlace: nil).hasSuffix("foco 50 min · ✦ 50"))
}

@Test func notaDeSesionConLineaYPlantilla() {
    let s = sesion("web", min: 25, nota: #"Arreglé "algo": hecho"#)
    let n = Registro.nota(s)
    #expect(n.contains(#"nota: "Arreglé \"algo\": hecho""#))
    #expect(n.contains("proyecto: \"web\""))
    #expect(n.contains("\n\nArreglé \"algo\": hecho\n\n25 min de foco"))
    let p = Registro.nota(s, plantilla: "# {{tarea}} · {{proyecto}}\n{{minutos}} min, ✦ {{destellos}}: {{nota}} {{nada}}")
    #expect(p == #"# Programación · web"# + "\n25 min, ✦ 25: " + #"Arreglé "algo": hecho {{nada}}"#)
}
