import SwiftUI

// Respiraciones guiadas: la luz crece al inhalar y se recoge al exhalar. Cada cambio de fase suena una vez, bajito.

struct Patron {
    struct Fase { let texto: String; let segundos: Double; let lleno: Double }
    let clave, nombre: String
    let fases: [Fase]
    let ciclos: Int
    var duracion: Double { fases.reduce(0) { $0 + $1.segundos } * Double(ciclos) }
}

let PATRONES = [
    Patron(clave: "caja", nombre: String(localized: "Caja"), fases: [.init(texto: String(localized: "Inhala"), segundos: 4, lleno: 1), .init(texto: String(localized: "Sostén"), segundos: 4, lleno: 1),
                                                   .init(texto: String(localized: "Exhala"), segundos: 4, lleno: 0), .init(texto: String(localized: "Sostén"), segundos: 4, lleno: 0)], ciclos: 4),
    Patron(clave: "478", nombre: "4-7-8", fases: [.init(texto: String(localized: "Inhala"), segundos: 4, lleno: 1), .init(texto: String(localized: "Sostén"), segundos: 7, lleno: 1),
                                                  .init(texto: String(localized: "Exhala"), segundos: 8, lleno: 0)], ciclos: 4),
    Patron(clave: "suspiro", nombre: String(localized: "Suspiro"), fases: [.init(texto: String(localized: "Inhala"), segundos: 2, lleno: 0.8), .init(texto: String(localized: "Un poco más"), segundos: 1, lleno: 1),
                                                        .init(texto: String(localized: "Exhala despacio"), segundos: 6, lleno: 0)], ciclos: 5),
]
// Las tres respiraciones antes de un foco.
let PREVIA = Patron(clave: "previa", nombre: String(localized: "Antes de empezar"), fases: [.init(texto: String(localized: "Inhala"), segundos: 4, lleno: 1), .init(texto: String(localized: "Exhala"), segundos: 6, lleno: 0)], ciclos: 3)

struct Respiracion: Equatable {
    let clave: String
    let inicio: Double   // systemUptime
    var patron: Patron { clave == PREVIA.clave ? PREVIA : PATRONES.first { $0.clave == clave } ?? PATRONES[0] }
    static func == (a: Respiracion, b: Respiracion) -> Bool { a.clave == b.clave && a.inicio == b.inicio }

    // Fase en curso (índice global), su texto, el tamaño de la luz (0…1) y el ciclo; nil si ya terminó.
    func en(_ t: Double) -> (fase: Int, texto: String, lleno: Double, ciclo: Int)? {
        let p = patron, total = p.fases.reduce(0) { $0 + $1.segundos }
        var s = t - inicio
        guard s >= 0, s < p.duracion else { return nil }
        let ciclo = Int(s / total); s -= Double(ciclo) * total
        var antes = p.fases.last!.lleno
        for (i, f) in p.fases.enumerated() {
            if s < f.segundos { return (ciclo * p.fases.count + i, f.texto, lerp(antes, f.lleno, suave(s / f.segundos)), ciclo + 1) }
            s -= f.segundos; antes = f.lleno
        }
        return nil
    }
}

// La luz que respira; solo se anima mientras hay una respiración en curso.
struct LuzRespira: View {
    let r: Respiracion
    var tam = 120.0
    var conTexto = true
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let e = r.en(ProcessInfo.processInfo.systemUptime), k = 0.45 + 0.55 * (e?.lleno ?? 0)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color.luz.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: tam / 2))
                    .scaleEffect(k * 1.25)
                Circle().fill(RadialGradient(colors: [.white, .luz, .luzOn.opacity(0.4)], center: UnitPoint(x: 0.42, y: 0.38), startRadius: 0, endRadius: tam * 0.32))
                    .frame(width: tam * 0.6, height: tam * 0.6).scaleEffect(k)
            }
            .frame(width: tam, height: tam)
            .overlay(alignment: .bottom) {
                Text(conTexto ? e?.texto ?? "" : "").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.texto).offset(y: 20)
            }
        }
        .accessibilityElement().accessibilityLabel(String(localized: "Respiración guiada"))
    }
}
