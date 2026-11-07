import Foundation

// Lumen, el búho blanco: dibujo, estados, gestos y etapas. Port de lumen.js (tema blanco).

struct Piel { var luz, medio, sombra, borde: Col }
func mezclaPiel(_ a: Piel, _ b: Piel, _ k: Double) -> Piel {
    Piel(luz: a.luz.mezcla(b.luz, k), medio: a.medio.mezcla(b.medio, k), sombra: a.sombra.mezcla(b.sombra, k), borde: k < 0.5 ? a.borde : b.borde)
}

// Cada color va en pareja [cálido, frío]; el frío entra con la distracción.
private enum Tema {
    static let plumaje = (Piel(luz: Col("#ffffff"), medio: Col("#eef2f7"), sombra: Col("#b2bdcd"), borde: Col(110, 130, 165, 0.3)),
                          Piel(luz: Col("#dfe5ef"), medio: Col("#c1c9d7"), sombra: Col("#8792a6"), borde: Col(60, 70, 95, 0.35)))
    static let garras = (Col("#e3e8ef"), Col("#b9c1cf"))
    static let ala = 0.2
    static let disco = ((Col("#ffffff"), Col("#e8edf4")), (Col("#e6ebf2"), Col("#c6cedb")))
    static let iris = [Col("#2a2e3a"), Col("#12141b"), Col("#050608")]
    static let tapa = (Col("#f2f5fa"), Col("#d3d9e3"))
    static let pico = (Col("#c9d1dd"), Col("#9ea7b7"))
    static let halo = 0.32, nuca = 0.2
    static let lado = Col(60, 80, 115), pluma = Col(235, 240, 248), cerrado = Col(125, 140, 165)
}
private func tono(_ par: (Col, Col), _ k: Double) -> Col { par.0.mezcla(par.1, k) }

// Volumen por capas: degradado diagonal, borde en sombra y brillo arriba (sombrear de sala.js, sin calor).
func sombrear(_ l: Lienzo, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ piel: Piel, _ brillo: Double) {
    l.fill(.lineal(cx + rx * 0.6, cy - ry, cx - rx * 0.7, cy + ry).parada(0, piel.luz).parada(0.5, piel.medio).parada(1, piel.sombra))
    let r = max(rx, ry)
    l.fill(.radial(cx, cy, r * 0.2, cx, cy, r * 1.15).parada(0, Col(0, 0, 0, 0)).parada(0.62, Col(0, 0, 0, 0)).parada(1, piel.borde))
    let bx = cx + rx * 0.25, by = cy - ry * 0.55
    l.fill(.radial(bx, by, 0, bx, by, min(rx, ry) * 0.9).parada(0, Col(255, 255, 255, 0.55 * brillo)).parada(1, Col(255, 255, 255, 0)))
}

struct Etapa { let nombre: String; let desde: Double; let tam, penacho, ojo, ahueca, halo: Double }
// Crecimiento por horas de luz: misma silueta; cambian el tamaño, el largo de los penachos, el ojo, lo ahuecado y el alcance del halo.
let ETAPAS = [
    Etapa(nombre: String(localized: "Cría"), desde: 0, tam: 0.74, penacho: -0.1, ojo: 1.2, ahueca: 0.06, halo: 0.8),
    Etapa(nombre: String(localized: "Joven"), desde: 20, tam: 0.87, penacho: -0.045, ojo: 1.08, ahueca: 0.03, halo: 0.92),
    Etapa(nombre: String(localized: "Adulto"), desde: 60, tam: 1, penacho: 0, ojo: 1, ahueca: 0, halo: 1),
    Etapa(nombre: String(localized: "Ancestral"), desde: 150, tam: 1.08, penacho: 0.08, ojo: 0.95, ahueca: 0, halo: 1.35),
]
func etapaPorHoras(_ h: Double) -> Int { ETAPAS.lastIndex { h >= $0.desde } ?? 0 }

// Los penachos siguen el giro de la cabeza (θ) sin salir de su lado: se desplazan un poco y el lejano baja.
private func contorno(_ l: Lienzo, _ penacho: Double, _ sx: Double, _ theta: Double, _ largo: Double) {
    let g = sin(theta)
    func lado(_ s: Double) -> [[(Double, Double)]] {
        let lejos = max(0, -s * g)
        let punta = (s * (0.27 + 0.05 * max(0, -penacho)) + 0.07 * g - s * 0.04 * lejos, -1.0 - 0.07 * penacho + 0.09 * lejos - largo)
        func q(_ x: Double, _ y: Double) -> (Double, Double) { (x * s * sx, y) }
        return [
            [(punta.0 * 0.33, -0.86), (punta.0 * 0.75, punta.1 + 0.07), punta],
            [(punta.0 + s * 0.04, punta.1 + 0.06), q(0.34, -0.86), q(0.345, -0.74)],
            [q(0.36, -0.55), q(0.46, -0.24), q(0.31, -0.06)],
            [q(0.24, -0.01), q(0.14, 0), (0, -0.005)],
        ]
    }
    let der = lado(1), izq = lado(-1), ini = (0.0, -0.86)
    l.beginPath(); l.moveTo(ini.0, ini.1)
    for t in der { l.bezierCurveTo(t[0].0, t[0].1, t[1].0, t[1].1, t[2].0, t[2].1) }
    for i in stride(from: izq.count - 1, through: 0, by: -1) {
        let a = izq[i][0], b = izq[i][1], desde = i > 0 ? izq[i - 1][2] : ini
        l.bezierCurveTo(b.0, b.1, a.0, a.1, desde.0, desde.1)
    }
    l.closePath()
}

// Contorno del disco facial muestreado en puntos, para poder proyectarlo sobre la cabeza.
private let DISCO: [(Double, Double)] = {
    let ini = (0.0, -0.12)
    let tramos = [((0.07, -0.18), (0.3, -0.2), (0.3, 0.0)), ((0.3, 0.15), (0.12, 0.19), (0.0, 0.14))]
    var der = [ini], a0 = ini
    for (c1, c2, c3) in tramos {
        for i in 1...16 {
            let u = Double(i) / 16, v = 1 - u
            der.append((v * v * v * a0.0 + 3 * v * v * u * c1.0 + 3 * v * u * u * c2.0 + u * u * u * c3.0,
                        v * v * v * a0.1 + 3 * v * v * u * c1.1 + 3 * v * u * u * c2.1 + u * u * u * c3.1))
        }
        a0 = c3
    }
    return der + der.dropFirst().dropLast().reversed().map { (-$0.0, $0.1) }
}()

// La cabeza es un cilindro de radio RH: un punto de la cara en x gira θ y se ve en X, con escala cos.
private let RH = 0.36
private func proyectar(_ x: Double, _ theta: Double) -> (Double, Double) {
    let f = asin(clamp(x / RH, -1, 1)) + theta, c = cos(f)
    let s = sin(f)
    return (c > 0 ? RH * s : RH * (s > 0 ? 1 : s < 0 ? -1 : 0), c)
}
// Entrada y salida suaves de un gesto, para que nunca salte al empezar ni al acabar.
private func envolvente(_ f: Double) -> Double { f < 0 ? 0 : suave(min(f / 0.12, (1 - f) / 0.15, 1)) }
private let ABAJO = Punto(x: 0, y: 3)

final class Buho: Mascota {
    override class var extra: [Estado: Params] {[
        .reposo: ["cierre": 0.38, "penacho": 0.15, "giro": 0, "dil": 0.9, "ahueca": 0, "alas": 0, "feliz": 0, "ceno": 0, "duerme": 0],
        .foco: ["cierre": 0, "penacho": 0.7, "giro": 0, "dil": 1.15, "ahueca": 0, "alas": 0, "feliz": 0, "ceno": 0.25, "duerme": 0],
        .triste: ["cierre": 0.45, "penacho": -0.8, "giro": 0.72, "dil": 0.8, "ahueca": 0, "alas": 0, "feliz": 0, "ceno": -0.5, "duerme": 0],
        .fin: ["cierre": 0, "penacho": 0.5, "giro": 0, "dil": 0.8, "ahueca": 1, "alas": 0.6, "feliz": 1, "ceno": 0, "duerme": 0],
        .descanso: ["energia": 0.45, "animo": 0.3, "frio": 0, "parpado": 0, "ritmo": 0.7, "cierre": 0.55, "penacho": 0.05, "giro": 0, "dil": 0.9, "ahueca": 0.02, "alas": 0, "feliz": 0.45, "ceno": 0, "duerme": 0],
        .dormido: ["energia": 0.05, "animo": 0, "frio": 0.15, "parpado": 0, "ritmo": 0.5, "cierre": 1, "penacho": -0.35, "giro": 0, "dil": 0.8, "ahueca": 0.05, "alas": 0, "feliz": 0, "ceno": 0, "duerme": 1],
    ]}
    let zoom: Double, suelo: Double
    var etapa: Int
    private var etapaVis: Double
    var vistazo = 0.0, proximoVistazo = 4.0, ladoLadeo = 1.0, ladoBloqueo = -1.0
    var arrastrado = false, colgando = 0.0, cuelga = 0.0, balanceo = 0.0

    init(zoom: Double = 1, suelo: Double = 0.84, etapa: Int = 2) {
        self.zoom = zoom; self.suelo = suelo; self.etapa = etapa; etapaVis = Double(etapa)
        super.init()
    }
    override func redimensionar(_ w: Double, _ h: Double) { super.redimensionar(w, h); u *= zoom; oy = h * suelo }
    // Al cambiar de etapa crece poco a poco: la forma se interpola entre las dos etapas vecinas.
    var forma: (tam: Double, penacho: Double, ojo: Double, ahueca: Double, halo: Double) {
        let a = ETAPAS[Int(etapaVis.rounded(.down))], b = ETAPAS[Int(etapaVis.rounded(.up))], k = etapaVis - etapaVis.rounded(.down)
        return (lerp(a.tam, b.tam, k), lerp(a.penacho, b.penacho, k), lerp(a.ojo, b.ojo, k), lerp(a.ahueca, b.ahueca, k), lerp(a.halo, b.halo, k))
    }
    override func cabeza() -> Punto { Punto(x: 0, y: -0.6 * forma.tam - alto) }
    override func mania() {
        let m = ["ladea", "sacude", "lento"].randomElement()!
        ladoLadeo = Bool.random() ? -1 : 1
        hacer(m, ["ladea": 2, "sacude": 0.9, "lento": 1.6][m]!)
    }
    // Dormido no da la vuelta: se despierta un momento y vuelve a dormirse.
    func tocar() { if estado == .dormido { hacer("despertar", 2.4) } else { hacer("vuelta", 1.8) } }
    func evento(_ nombre: String, lado: Double = -1) {
        if nombre == "bloqueo" { ladoBloqueo = lado; hacer("bloqueo", 3) } else if nombre == "despertar" { hacer("despertar", 2.4) }
    }
    override func alEntrar(_ e: Estado, _ antes: Estado) {
        if e == .fin { saltar(0.12, 0.4); emitir(azar(-0.3, 0.3), -0.7, 2, vel: 0.25, g: 0.18, vida: 3.5, r: 0.05, roce: 0.4) }
    }
    override func paso(_ dt: Double) {
        // Distraído mira hacia otro lado, pero cada poco te echa un vistazo.
        if estado == .triste {
            proximoVistazo -= dt
            if proximoVistazo <= 0 { vistazo = 1.3; proximoVistazo = azar(4, 7) }
        }
        vistazo = max(0, vistazo - dt)
        if fase("sacude") > 0.4 && una("pluma") { emitir(azar(-0.25, 0.25), -0.55, 1, vel: 0.2, g: 0.16, vida: 3.5, r: 0.05, roce: 0.4) }
        etapaVis = abs(Double(etapa) - etapaVis) < 0.002 ? Double(etapa) : lerp(etapaVis, Double(etapa), ease(dt, 0.4))
        cuelga = lerp(cuelga, arrastrado ? 1 : 0, ease(dt, 0.02))
        balanceo = lerp(balanceo, colgando, ease(dt, 0.05))
        if arrastrado { mirarA = ABAJO } else if let m = mirarA, m.x == ABAJO.x && m.y == ABAJO.y { mirarA = nil }
    }
    override func dibujarParticulas(_ l: Lienzo) {
        for q in particulas {
            let f = q.vida / q.max, a = min(1, (1 - f) * 3) * min(1, q.vida * 4)
            l.save(); l.translate(q.x + sin(q.vida * 2.6) * 0.06, q.y); l.rotate(sin(q.vida * 2.6) * 0.6)
            l.beginPath(); l.ellipse(0, 0, q.r * 0.35, q.r)
            // Borde y nervio en el tono del tema: sobre el plumaje blanco un nervio oscuro se leía como un corte.
            l.fill(Tema.pluma.alfa(0.8 * a)); l.stroke(Tema.cerrado.alfa(0.25 * a), 0.005)
            l.beginPath(); l.moveTo(0, -q.r); l.lineTo(0, q.r * 1.3); l.stroke(Tema.cerrado.alfa(0.35 * a), 0.005)
            l.restore()
        }
    }
    private func ojo(_ l: Lienzo, _ x: Double, _ lado: Double, _ cierre: Double, _ ceno: Double) {
        let r = 0.085, frio = p["frio"] ?? 0, feliz = p["feliz"] ?? 0
        l.save(); l.translate(x, 0); l.scale(forma.ojo, forma.ojo)
        l.beginPath(); l.arc(0, 0, r); l.save(); l.clip()
        l.fillRect(-r, -r, 2 * r, 2 * r, .radial(0, 0, 0, 0, 0, r).parada(0, Tema.iris[0]).parada(0.6, Tema.iris[1]).parada(1, Tema.iris[2]))
        let px = clamp(mirada.x, -1, 1) * 0.022, py = clamp(mirada.y, -1, 1) * 0.018
        l.beginPath(); l.arc(px - 0.022, py - 0.026, 0.014); l.fill(Col(255, 255, 255, 0.85))
        let tapa = tono(Tema.tapa, frio)
        let c = clamp(cierre, 0, 1), yl = -r + c * 2 * r, k = ceno * r * 0.5 * lado
        l.beginPath(); l.moveTo(-r, -r - 0.01); l.lineTo(r, -r - 0.01); l.lineTo(r, yl - k); l.lineTo(-r, yl + k); l.closePath(); l.fill(tapa)
        if feliz > 0.01 {
            let yb = r - feliz * 1.1 * r
            l.beginPath(); l.moveTo(-r, r + 0.01); l.lineTo(r, r + 0.01); l.lineTo(r, yb + 0.02); l.quadraticCurveTo(0, yb - 0.05 * feliz, -r, yb + 0.02); l.closePath(); l.fill(tapa)
        }
        // Ojo cerrado: una curva suave para que se lea como párpado y no como un ojo que desaparece.
        if c > 0.85 {
            l.beginPath(); l.moveTo(-r * 0.75, r * 0.05); l.quadraticCurveTo(0, r * 0.45, r * 0.75, r * 0.05)
            l.stroke(Tema.cerrado.alfa((c - 0.85) / 0.15 * 0.55), 0.014)
        }
        l.restore()
        l.restore()
    }

    override func cuerpo(_ l: Lienzo) {
        let t = self.t, f = forma, P = { (k: String) in self.p[k] ?? 0 }
        let vu = fase("vuelta"), la = fase("ladea"), sa = fase("sacude"), le = fase("lento"), bl = fase("bloqueo"), de = fase("despertar")
        // App bloqueada: mira la app, vuelve hacia ti y entorna los ojos, sin ceño; un «¿en serio?».
        let haciaApp = bl < 0 ? 0 : suave(bl / 0.15) * (1 - suave((bl - 0.4) / 0.15))
        let entorna = bl < 0 ? 0 : suave((bl - 0.3) / 0.15) * suave((1 - bl) / 0.15)
        var giro = P("giro") * (1 - (vistazo > 0 ? sin(.pi * (1 - vistazo / 1.3)) : 0))
        if estado != .triste { giro += clamp(mirada.x, -1, 1) * 0.3 * (1 - P("duerme")) }
        var theta = vu >= 0 ? PI2 * suave(vu) : giro * .pi / 2
        theta = lerp(theta, ladoBloqueo * 0.95, haciaApp)
        let ladeo = la >= 0 ? ladoLadeo * 0.28 * sin(la * .pi) : 0
        var cierre = P("cierre") + parpadeando()
        if le >= 0 { cierre = max(cierre, sin(le * .pi)) }
        cierre = lerp(cierre, 0.55, entorna)
        let ceno = lerp(P("ceno"), 0, entorna)
        var penacho = P("penacho") + 0.25 * haciaApp, estira = 0.0
        // Despertar: se estira con los ojos cerrados y los abre de golpe.
        if de >= 0 {
            let abre = de < 0.45 ? 1 : 1 - suave((de - 0.45) / 0.06)
            cierre = lerp(cierre, abre, envolvente(de))
            estira = sin(.pi * clamp(de / 0.45, 0, 1))
            penacho += 0.5 * sin(.pi * clamp((de - 0.45) / 0.3, 0, 1))
        }
        cierre = lerp(cierre, 0, 0.8 * cuelga)
        let abreAlas = 0.7 * estira + 0.45 * cuelga
        let sacudida = sa >= 0 ? sin(t * 40) * 0.04 * sin(sa * .pi) : 0
        let frio = P("frio")
        let piel = mezclaPiel(Tema.plumaje.0, Tema.plumaje.1, frio * 0.85)
        let sx = 1 + 0.08 * P("ahueca") + f.ahueca + sacudida - 0.03 * max(0, -P("animo"))
        let resp = sin(t * 1.6 * P("ritmo")) * 0.01
        // Dormido esconde la cabeza en el plumaje: el cuerpo se redondea y la cara baja.
        let hy = -0.6 + 0.06 * P("duerme") + 0.025 * cuelga

        l.save(); l.scale(f.tam, f.tam)
        sombra(l, 0, 0.42)
        l.save(); transformar(l)
        // Al arrastrarlo cuelga y se balancea desde arriba, con retraso.
        l.translate(0, -1); l.rotate(balanceo * 0.35); l.translate(0, 1)
        l.scale(1 + 0.04 * P("duerme"), 1 + resp - 0.025 * max(0, -P("animo")) - 0.05 * P("duerme") + 0.05 * estira + 0.03 * cuelga)
        var brillo = Tema.halo * (0.55 + 0.45 * P("energia")) * (1 - 0.5 * frio) * (1 + 0.3 * P("ahueca"))
        brillo *= (1 - 0.65 * P("duerme")) * (1 + 0.3 * P("duerme") * sin(t * 1.1))
        let rh = 1.05 * f.halo, halo = Col(210, 228, 255)
        l.save(); l.sumaLuz = true
        l.beginPath(); l.arc(0, -0.5, rh)
        l.fill(.radial(0, -0.5, 0.2, 0, -0.5, rh).parada(0, halo.alfa(brillo)).parada(0.35, halo.alfa(brillo * 0.35)).parada(0.7, halo.alfa(brillo * 0.08)).parada(1, halo.alfa(0)))
        l.restore()

        // Garras primero: el cuerpo tapa su arranque, así quedan unidas.
        let garra = tono(Tema.garras, frio)
        for s in [-1.0, 1] { for d in [-0.035, 0, 0.035] { l.beginPath(); l.ellipse(s * 0.1 + d, -0.012, 0.018, 0.028, d * 4); l.fill(garra) } }

        contorno(l, penacho, sx, theta, f.penacho)
        sombrear(l, 0, -0.5, 0.42 * sx, 0.5, piel, 0.22)
        l.save(); contorno(l, penacho, sx, theta, f.penacho); l.clip()
        for s in [-1.0, 1] {
            l.save(); l.translate(s * 0.36, -0.62); l.rotate(-s * 0.35 * (P("alas") * (0.6 + 0.4 * sin(t * 9)) + abreAlas))
            l.beginPath(); l.moveTo(0, 0); l.bezierCurveTo(s * 0.06, 0.15, s * 0.04, 0.4, -s * 0.12, 0.56); l.bezierCurveTo(-s * 0.15, 0.36, -s * 0.12, 0.12, 0, 0)
            l.alfa = Tema.ala; l.fill(piel.sombra); l.alfa = 1
            l.restore()
        }
        let visible = clamp((cos(theta) + 0.45) * 2.5, 0, 1)
        // Cabeza: cada pieza de la cara se proyecta sobre un cilindro que gira θ; por detrás aparece la nuca.
        l.save(); l.translate(0, hy); l.rotate(ladeo)
        let (nx, nc) = proyectar(0, theta + .pi)
        if nc > 0.02 {
            l.save(); l.translate(nx, 0); l.scale(nc, 1); l.alfa = Tema.nuca * nc
            l.beginPath(); l.ellipse(0, 0.02, 0.17, 0.22)
            l.fill(.radial(0, 0, 0, 0, 0, 0.2).parada(0, piel.sombra).parada(1, Col(0, 0, 0, 0)))
            for (x, y) in [(-0.05, -0.08), (0.05, -0.08), (0, 0.0), (-0.06, 0.08), (0.06, 0.08)] {
                l.beginPath(); l.moveTo(x - 0.028, y - 0.014); l.lineTo(x, y); l.lineTo(x + 0.028, y - 0.014); l.stroke(Col(140, 155, 180, 0.18), 0.011)
            }
            l.restore()
        }
        if visible > 0.01 {
            l.save(); l.alfa = visible
            l.beginPath(); for (x, y) in DISCO { l.lineTo(proyectar(x, theta).0, y) }; l.closePath()
            let cx = proyectar(0, theta).0
            l.fill(.radial(cx, 0, 0.05, cx, 0, 0.32).parada(0, tono(Tema.disco.0, frio)).parada(1, tono(Tema.disco.1, frio)))
            for s in [-1.0, 1] {
                let (ex, ec) = proyectar(s * 0.13, theta)
                if ec < 0.06 { continue }
                l.save(); l.translate(ex, 0); l.scale(ec, 1); ojo(l, 0, s, cierre, ceno); l.restore()
            }
            l.restore()
        }
        // Sombra del lado que se aleja: refuerza el volumen de la cabeza al girar.
        let lejos = sin(theta)
        if abs(lejos) > 0.02 {
            let x0 = -RH * 1.1 * (lejos > 0 ? 1 : -1)
            l.beginPath(); l.arc(x0, 0, 0.42)
            l.fill(.radial(x0, 0, 0, x0, 0, 0.42).parada(0, Tema.lado.alfa(0.35 * abs(lejos))).parada(1, Tema.lado.alfa(0)))
        }
        l.restore()
        l.restore()
        // El pico va fuera del recorte del cuerpo: de perfil asoma por el borde de la cabeza.
        let (bx, bc) = proyectar(0, theta)
        if bc > 0.06 && visible > 0.01 {
            l.save(); l.alfa = visible; l.translate(0, hy); l.rotate(ladeo)
            l.translate(bx + 0.03 * sin(theta), 0); l.scale(max(bc, 0.55) * (cos(theta) >= 0 ? 1 : -1), 1)
            l.beginPath(); l.moveTo(-0.032, 0.045); l.quadraticCurveTo(0, 0.035, 0.032, 0.045); l.quadraticCurveTo(0.012, 0.09, 0, 0.125); l.quadraticCurveTo(-0.012, 0.09, -0.032, 0.045); l.closePath()
            l.fill(tono(Tema.pico, frio))
            l.restore()
        }
        l.restore()
        l.restore()
    }
}
