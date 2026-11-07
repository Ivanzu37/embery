import Foundation

// Motor común de Lumen (búho y espíritu): estados, mirada, saltos, gestos y partículas. Port de mascota-base.js.

enum Estado: String { case reposo, foco, triste, fin, descanso, dormido }

typealias Params = [String: Double]

// Tendencia común de cada estado; cada mascota añade los suyos en extra.
let ANIMOS: [Estado: Params] = [
    .reposo: ["energia": 0.55, "animo": 0, "frio": 0, "parpado": 0, "ritmo": 1],
    .foco: ["energia": 0.85, "animo": 0.35, "frio": 0, "parpado": 0.12, "ritmo": 0.8],
    .triste: ["energia": 0.15, "animo": -1, "frio": 1, "parpado": 0.3, "ritmo": 0.55],
    .fin: ["energia": 1, "animo": 1, "frio": 0, "parpado": 0, "ritmo": 1.5],
]

struct Punto { var x: Double; var y: Double }

struct Gesto { let nombre: String; let t0: Double; let dur: Double; var hechos: Set<String> = [] }

struct Particula { var x, y, vx, vy, g, vida, max, r, roce: Double }

class Mascota {
    class var extra: [Estado: Params] { [:] }
    var t = Double.random(in: 0..<10)
    var estado: Estado = .reposo
    var p: Params
    var w = 0.0, h = 0.0, u = 0.0, ox = 0.0, oy = 0.0
    var mirada = Punto(x: 0, y: 0), miradaObj = Punto(x: 0, y: 0)
    var raton: Punto?
    var ultimoRaton = -10.0, proximaMirada = 1.0
    var mirarA: Punto?
    var parpadeo = 0.0, proximoParpadeo = azar(2, 4)
    var salto: (alto: Double, dur: Double, t0: Double)?
    var alto = 0.0, aplasta = 0.0, aplastaV = 0.0
    var gesto: Gesto?
    var proximoGesto = azar(3, 6)
    var particulas: [Particula] = []

    init() {
        p = (ANIMOS[.reposo] ?? [:]).merging(Self.extra[.reposo] ?? [:]) { $1 }
    }

    func redimensionar(_ w: Double, _ h: Double) {
        self.w = w; self.h = h
        u = min(w / 2.6, h / 1.9); ox = w / 2; oy = h * 0.84
    }
    func setEstado(_ e: Estado) { if e == estado { return }; let antes = estado; estado = e; alEntrar(e, antes) }
    func alEntrar(_ e: Estado, _ antes: Estado) {}
    func hacer(_ nombre: String, _ dur: Double) { gesto = Gesto(nombre: nombre, t0: t, dur: dur) }
    // Avance 0..1 del gesto si está en curso; -1 si no.
    func fase(_ nombre: String) -> Double { if let g = gesto, g.nombre == nombre { return (t - g.t0) / g.dur }; return -1 }
    func una(_ clave: String) -> Bool {
        guard gesto != nil, !gesto!.hechos.contains(clave) else { return false }
        gesto!.hechos.insert(clave); return true
    }
    func cabeza() -> Punto { Punto(x: 0, y: -0.5 - alto) }
    // (x, y) en puntos de la vista, con y hacia abajo.
    func mirar(_ x: Double, _ y: Double) {
        guard u > 0 else { return }
        raton = Punto(x: (x - ox) / u, y: (y - oy) / u); ultimoRaton = t
    }
    func saltar(_ alto: Double, _ dur: Double) { salto = (alto, dur, t) }
    func parpadeando() -> Double { sin(parpadeo * .pi) }
    func emitir(_ x: Double, _ y: Double, _ n: Int, vel: Double = 1, dir: Double = -.pi / 2, abre: Double = .pi, g: Double = 0, vida: Double = 0.8, r: Double = 0.02, roce: Double = 0.3) {
        for _ in 0..<n {
            let a = dir + (Double.random(in: 0..<1) - 0.5) * abre, v = vel * azar(0.5, 1.2)
            particulas.append(Particula(x: x, y: y, vx: cos(a) * v, vy: sin(a) * v, g: g, vida: 0, max: vida * azar(0.6, 1.2), r: r * azar(0.6, 1.4), roce: roce))
        }
    }
    func mania() {}
    func paso(_ dt: Double) {}

    func actualizar(_ dt: Double) {
        t += dt
        let obj = (ANIMOS[estado] ?? [:]).merging(Self.extra[estado] ?? [:]) { $1 }, k = ease(dt, 0.06)
        for (c, v) in obj { p[c] = lerp(p[c] ?? v, v, k) }

        proximoParpadeo -= dt
        if proximoParpadeo <= 0 { parpadeo = 1; proximoParpadeo = azar(2.5, 6) }
        parpadeo = max(0, parpadeo - dt * 6)

        let c = cabeza()
        let mira = mirarA ?? (raton != nil && t - ultimoRaton < 3 ? raton : nil)
        if let mira {
            let dx = mira.x - c.x, dy = mira.y - c.y, d = max(hypot(dx, dy), 1e-9), f = min(1, d / 1.1)
            miradaObj = Punto(x: dx / d * f, y: dy / d * f)
        } else {
            proximaMirada -= dt
            if proximaMirada <= 0 {
                miradaObj = Double.random(in: 0..<1) < 0.4 ? Punto(x: 0, y: 0) : Punto(x: azar(-0.8, 0.8), y: azar(-0.5, 0.4))
                proximaMirada = azar(1.2, 3.5)
            }
        }
        let km = ease(dt, 0.0005)
        mirada.x = lerp(mirada.x, miradaObj.x, km); mirada.y = lerp(mirada.y, miradaObj.y, km)

        if let s = salto {
            let f = (t - s.t0) / s.dur
            if f >= 1 { alto = 0; salto = nil; aplastaV += 5 } else { alto = s.alto * 4 * f * (1 - f) }
        }
        aplastaV += (-140 * aplasta - 10 * aplastaV) * dt; aplasta += aplastaV * dt

        if let g = gesto, t - g.t0 > g.dur { gesto = nil; mirarA = nil }
        if gesto == nil && (estado == .reposo || estado == .foco) {
            proximoGesto -= dt
            if proximoGesto <= 0 { mania(); proximoGesto = azar(6, 11) }
        }
        for i in particulas.indices {
            var q = particulas[i]
            q.vida += dt; let r = pow(q.roce, dt)
            q.vx *= r; q.vy *= r; q.vy += q.g * dt; q.x += q.vx * dt; q.y += q.vy * dt
            particulas[i] = q
        }
        particulas.removeAll { $0.vida >= $0.max }
        paso(dt)
    }

    func transformar(_ l: Lienzo) {
        l.translate(0, -alto)
        let sq = clamp(aplasta, -0.6, 0.6) * 0.12
        l.scale(1 + sq, 1 - sq)
    }
    func sombra(_ l: Lienzo, _ x: Double, _ ancho: Double, _ k: Double = 1) {
        let a = ancho * (1 - min(0.4, alto))
        l.save(); l.scale(1, 0.16); l.beginPath(); l.arc(x, 0, a)
        l.fill(.radial(x, 0, 0, x, 0, a).parada(0, Col(0, 0, 0, 0.5 * k)).parada(1, Col(0, 0, 0, 0)))
        l.restore()
    }
    func cuerpo(_ l: Lienzo) {}
    func dibujarParticulas(_ l: Lienzo) {}

    // Dibuja con el origen del lienzo ya puesto en la esquina de la vista.
    func dibujar(_ l: Lienzo) {
        l.save(); l.translate(ox, oy); l.scale(u, u)
        cuerpo(l); dibujarParticulas(l)
        l.restore()
    }
}
