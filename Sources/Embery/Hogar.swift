import Foundation

// El hogar de Lumen: una rama de noche (o de día, según la hora) que guarda tu luz. Las hojas y ramitas crecen con las
// horas de luz, sale una flor por día de racha y las luciérnagas son la luz de hoy. Detrás de Lumen va el cielo, el
// bosque, la rama y los muebles; delante, las luciérnagas, las hojas que caen y las motas.
// Maqueta aprobada: proyectos/embery/assets/prototipo/hogar-v2.html de la bóveda. Se dibuja en un lienzo de 340 × 300.

let HW = 340.0, HH = 300.0, HOGAR_X = HW / 2

private func yTop(_ x: Double) -> Double { 222 + 26 * pow(max(0, x + 12) / 352, 2.3) }
private func grosor(_ x: Double) -> Double { 32 - 27 * pow(max(0, x + 12) / 352, 1.25) }
let SUELO_HOGAR = yTop(HOGAR_X) + 2

private let FRIO = Col(210, 228, 255), CLARO = Col(236, 244, 255)

// Azar con semilla: la escena es siempre la misma y solo crece.
private struct Semilla {
    var s: UInt32
    mutating func next() -> Double {
        s = s &+ 0x6D2B79F5
        var t = (s ^ (s >> 15)) &* (1 | s)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296
    }
}

private typealias P = (x: Double, y: Double)
private func qb(_ a: P, _ c: P, _ b: P, _ s: Double) -> P {
    ((1 - s) * (1 - s) * a.x + 2 * (1 - s) * s * c.x + s * s * b.x, (1 - s) * (1 - s) * a.y + 2 * (1 - s) * s * c.y + s * s * b.y)
}

private struct Ramita { let b, c, p: P; let g0: Double }
private let RAMITAS = [
    Ramita(b: (262, yTop(262) + 2), c: (282, 214), p: (312, 176), g0: 0),
    Ramita(b: (96, yTop(96) + 3), c: (86, 196), p: (62, 172), g0: 20),
    Ramita(b: (296, yTop(296) + 1), c: (312, 236), p: (328, 222), g0: 8),
    Ramita(b: (212, yTop(212) + 6), c: (226, 268), p: (214, 288), g0: 60),
    Ramita(b: (24, yTop(24) + 4), c: (14, 200), p: (2, 186), g0: 100),
]
private func punto(_ r: Ramita, _ s: Double) -> P { qb(r.b, r.c, r.p, s) }

private struct Hoja { var ram: Int, s = 0.0, x = 0.0, lado: Double, largo: Double, f: Double, tono: Double, orden = 0.0 }
private let HOJAS: [Hoja] = {
    var r = Semilla(s: 7), l: [Hoja] = []
    for i in RAMITAS.indices { for k in 0..<7 { l.append(Hoja(ram: i, s: 0.25 + Double(k) * 0.12 + r.next() * 0.05, lado: k % 2 == 1 ? 1 : -1, largo: 9 + r.next() * 6, f: r.next() * 6, tono: r.next())) } }
    for k in 0..<8 { let x = 230 + Double(k) * 13 + r.next() * 6; l.append(Hoja(ram: -1, x: x, lado: r.next() < 0.5 ? 1 : -1, largo: 8 + r.next() * 5, f: r.next() * 6, tono: r.next())) }
    for i in l.indices { l[i].orden = r.next() * 0.6 + Double(i) / Double(l.count) }
    return l.sorted { $0.orden < $1.orden }
}()
private let FLORES: [(Int, Double)] = [(0, 0.98), (1, 0.97), (2, 0.96), (0, 0.6), (1, 0.62), (3, 0.95), (4, 0.95)]
private let CORTEZA: [(x: Double, k: Double, w: Double, a: Double)] = {
    var r = Semilla(s: 3); return (0..<90).map { _ in (-10 + r.next() * 340, r.next(), 8 + r.next() * 26, 0.12 + r.next() * 0.2) }
}()
private let MUSGO: [Double] = { var r = Semilla(s: 9); return (0..<9).map { _ in 6 + r.next() * 300 } }()
private let ESTRELLAS: [(x: Double, y: Double, r: Double, f: Double, ph: Double, a: Double)] = {
    var r = Semilla(s: 11); return (0..<70).map { _ in (r.next() * HW, r.next() * 170, 0.4 + r.next() * r.next() * 1.3, 0.5 + r.next() * 2, r.next() * 6, 0.25 + r.next() * 0.6) }
}()
private struct Arbol { let x, h, w, dy: Double; let pino: Bool }
private let BOSQUE: [[Arbol]] = [0, 1].map { c in
    var r = Semilla(s: UInt32(20 + c)), l: [Arbol] = [], x = -20.0
    let k = Double(c)
    while x < HW + 20 {
        let h = 18 + 12 * k + r.next() * r.next() * (30 + 16 * k), w = 12 + 6 * k + r.next() * 16, pino = r.next() < 0.65, dy = r.next() * (8 + 6 * k)
        l.append(Arbol(x: x, h: h, w: w, dy: dy, pino: pino)); x += 11 + 4 * k + r.next() * 12
    }
    return l
}
private func colinas(_ x: Double) -> Double { 196 - 10 * sin(x * 0.012 + 1) - 6 * sin(x * 0.031 + 2) }

// Cielo por hora: arriba, abajo y cuánta noche hay.
private let CIELOS: [(Double, Col, Col, Double)] = [
    (0, Col("#060912"), Col("#111829"), 1), (5, Col("#070b16"), Col("#151c2e"), 1), (6.5, Col("#1a2238"), Col("#45486a"), 0.45),
    (8, Col("#2a3956"), Col("#5b6d8c"), 0.05), (12, Col("#2f4262"), Col("#6a7f9e"), 0), (17, Col("#2b3b5a"), Col("#5f7090"), 0.05),
    (19, Col("#1b2440"), Col("#4b4766"), 0.4), (20.5, Col("#0d1324"), Col("#22283f"), 0.85), (24, Col("#060912"), Col("#111829"), 1),
]
private func cielo(_ h: Double) -> (arriba: Col, abajo: Col, noche: Double) {
    let i = max(1, CIELOS.firstIndex { $0.0 > h } ?? CIELOS.count - 1), a = CIELOS[i - 1], b = CIELOS[i], k = (h - a.0) / (b.0 - a.0)
    return (a.1.mezcla(b.1, k), a.2.mezcla(b.2, k), lerp(a.3, b.3, k))
}
// Fase de la luna de verdad: 0 nueva, 0,5 llena.
private func faseLuna(_ d: Date) -> Double {
    let dias = (d.timeIntervalSince1970 - 947_182_440) / 86400, c = 29.530588
    return (dias.truncatingRemainder(dividingBy: c) + c).truncatingRemainder(dividingBy: c) / c
}

struct DatosHogar {
    var estado: Estado = .reposo
    var horas = 0.0, racha = 0, hoy = 0.0
    var tiene: Set<String> = []
    var reducir = false

    var hojas: Int { let n = Int((4 + min(1, horas / 150) * Double(HOJAS.count - 4)).rounded()); return estado == .triste ? Int((Double(n) * 0.75).rounded()) : n }
    var flores: Int { min(7, racha) }
    var luciernagas: Int { estado == .triste ? 0 : Int((min(1.3, hoy) * 6).rounded()) + (hoy >= 1 ? 1 : 0) }
    fileprivate func crece(_ r: Ramita) -> Double { clamp((horas - r.g0 + 12) / 60, 0, 1) }
}

// Huecos de los muebles, en el lienzo de 340 × 300; los que cuelgan, donde queda su centro.
let MUEBLES_HOGAR: [(clave: String, x: Double, y: Double)] = [
    ("nido", 74, yTop(74) - 6), ("seta", 22, yTop(22) - 10), ("campanilla", 266, yTop(266) + grosor(266) + 14),
    ("farolillo", punto(RAMITAS[0], 0.88).x, punto(RAMITAS[0], 0.88).y + 24), ("guirnalda", 96, yTop(96) + grosor(96) + 12),
]

final class EscenaHogar {
    var d = DatosHogar()
    var horaFija: Double?
    private var t = 0.0, viento = 0.0, rafaga = 0.0, proxRafaga = 6.0, proxFugaz = 14.0
    private var fugaz: (x: Double, y: Double, k: Double)?
    private var luci: [(hx: Double, hy: Double, ph: Double, x: Double, y: Double, a: Double)] = (0..<9).map { i in
        var r = Semilla(s: UInt32(40 + i)); return (30 + r.next() * 280, 70 + r.next() * 150, r.next() * 9, HOGAR_X, 200, 0)
    }
    private var caen: [(x: Double, y: Double, vy: Double, a: Double, v: Double)] = []
    private var motas: [(x: Double, y: Double, vx: Double, v: Double)] = []
    private var noche = 1.0, apagado = 1.0, hora = 0.0, fase = 0.5
    private var sky = (arriba: Col(0, 0, 0), abajo: Col(0, 0, 0), noche: 1.0)

    func paso(_ dt: Double) {
        let quieto = d.reducir
        if !quieto { t += dt }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        hora = horaFija ?? Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        fase = faseLuna(Date())
        sky = cielo(hora)
        noche = min(1, sky.noche + (d.estado == .dormido ? 0.25 : 0))
        apagado = d.estado == .triste ? 0.6 : 1
        // Viento: brisa casi quieta con ráfagas suaves de vez en cuando.
        if !quieto {
            proxRafaga -= dt
            if proxRafaga <= 0 { rafaga = 1; proxRafaga = azar(9, 23) }
            rafaga = max(0, rafaga - dt / 3.5)
        }
        let calma = d.estado == .foco || d.estado == .dormido ? 0.4 : 1
        viento = calma * (0.15 + 0.85 * (rafaga > 0 ? sin(min(1, 1 - rafaga) * .pi) : 0))
        if !quieto && noche > 0.7 && d.estado != .triste {
            proxFugaz -= dt
            if proxFugaz <= 0 && fugaz == nil { fugaz = (azar(40, 240), azar(10, 50), 0); proxFugaz = azar(25, 55) }
            if var f = fugaz { f.k += dt / 0.9; fugaz = f.k >= 1 ? nil : f }
        }
        pasoFrente(dt, quieto)
    }

    private func gris(_ c: Col) -> Col {
        guard d.estado == .triste else { return c }
        let m = (c.r + c.g + c.b) / 3; return c.mezcla(Col(m, m, m + 6), 0.45)
    }

    // Halo irregular y vivo, nunca un círculo perfecto: una forma ondulada con un degradado que se apaga en el borde.
    private func halo(_ l: Lienzo, _ x: Double, _ y: Double, _ r: Double, _ col: Col, _ a: Double, _ semilla: Double) {
        l.beginPath()
        for i in 0...36 {
            let g = Double(i) / 36 * PI2, rr = r * (1 + 0.12 * sin(g * 3 + t * 0.4 + semilla) + 0.07 * sin(g * 5 - t * 0.3))
            l.lineTo(x + cos(g) * rr, y + sin(g) * rr)
        }
        l.closePath()
        l.fill(.radial(x, y, 0, x, y, r * 1.15).parada(0, col.alfa(a * 3)).parada(0.35, col.alfa(a * 1.4)).parada(1, col.alfa(0)))
    }
    private func mediaElipse(_ l: Lienzo, _ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
        l.moveTo(x - rx, y); l.bezierCurveTo(x - rx, y - ry * 1.33, x + rx, y - ry * 1.33, x + rx, y); l.closePath()
    }
    private func hoja(_ l: Lienzo, _ x: Double, _ y: Double, _ ang: Double, _ largo: Double, _ col: Col, borde: Col? = nil) {
        l.save(); l.translate(x, y); l.rotate(ang)
        l.beginPath(); l.moveTo(0, 0); l.quadraticCurveTo(largo * 0.45, -largo * 0.38, largo, 0); l.quadraticCurveTo(largo * 0.45, largo * 0.38, 0, 0)
        l.fill(col)
        l.beginPath(); l.moveTo(1, 0); l.lineTo(largo * 0.8, 0); l.stroke(Col(0, 0, 0, 0.25), 0.6)
        if let borde { l.beginPath(); l.moveTo(0, 0); l.quadraticCurveTo(largo * 0.45, -largo * 0.38, largo, 0); l.stroke(borde, 0.7) }
        l.restore()
    }
    private func flor(_ l: Lienzo, _ x: Double, _ y: Double, abierta: Bool, _ i: Int, viva: Bool) {
        l.save(); l.translate(x, y); l.rotate(sin(t * 0.7 + Double(i)) * 0.06)
        if !abierta {
            l.beginPath(); l.ellipse(0, 0, 1.8, 2.8, -0.4); l.fill(Col("#7b8aa6"))
            l.beginPath(); l.ellipse(0, -0.8, 1, 1.6, -0.4); l.fill(Col(223, 232, 248, 0.5))
        } else {
            halo(l, 0, 0, viva ? 9 : 7, FRIO, viva ? 0.07 + 0.04 * sin(t * 1.4 + Double(i)) : 0.05, Double(i))
            for _ in 0..<5 { l.rotate(PI2 / 5); l.beginPath(); l.ellipse(0, -2.6, 1.7, 2.6); l.fill(CLARO.alfa(0.92)) }
            l.beginPath(); l.arc(0, 0, 1.3); l.fill(Col("#a9c6ff"))
        }
        l.restore()
    }
    // Lo que cuelga se mece como un péndulo, con el viento.
    private func colgante(_ x: Double, _ y: Double, _ largo: Double, _ fase: Double) -> (x: Double, y: Double, a: Double) {
        let a = d.reducir ? 0 : 0.05 * sin(t * 1.1 + fase) + 0.1 * viento * sin(t * 2.3 + fase)
        return (x + sin(a) * largo, y + cos(a) * largo, a)
    }

    // MARK: Detrás de Lumen

    func fondo(_ l: Lienzo) {
        let e = d.estado, quieto = d.reducir
        l.fillRect(0, 0, HW, HH, .lineal(0, 0, 0, HH).parada(0, gris(sky.arriba)).parada(1, gris(sky.abajo)))

        // Estrellas que titilan y, muy de vez en cuando, una fugaz.
        let ae = max(0, noche - 0.15) / 0.85 * apagado
        if ae > 0 {
            for s in ESTRELLAS {
                let tw = quieto ? 1 : 0.6 + 0.4 * sin(t * s.f + s.ph)
                l.beginPath(); l.arc(s.x, s.y, s.r); l.fill(Col(223, 232, 248, s.a * tw * ae))
            }
        }
        if let f = fugaz {
            let x = f.x + 90 * f.k, y = f.y + 34 * f.k
            l.beginPath(); l.moveTo(x - 30, y - 11); l.lineTo(x, y)
            l.ctx.saveGState(); l.ctx.addPath(l.camino); l.ctx.setLineWidth(1); l.ctx.replacePathWithStrokedPath(); l.ctx.clip()
            l.fillRect(x - 31, y - 12, 32, 13, .lineal(x - 30, y - 11, x, y).parada(0, CLARO.alfa(0)).parada(1, CLARO.alfa(0.7 * sin(f.k * .pi))))
            l.ctx.restoreGState()
        }

        // Luna con su fase real y halo irregular; de día, pálida.
        let lx = 282.0, ly = 46.0, lr = 13.0, la = (0.35 + 0.55 * noche) * apagado
        halo(l, lx, ly, 40, Col(200, 215, 240), 0.02 * la + 0.006, 1)
        l.save(); l.alfa = la
        l.beginPath(); l.arc(lx, ly, lr); l.fill(Col("#d6dff0"))
        l.beginPath(); l.arc(lx - 4, ly - 3, 3); l.arc(lx + 4, ly + 4, 2); l.fill(Col(150, 165, 195, 0.35))
        let dx = fase < 0.5 ? -2 * lr * fase * 2 : 2 * lr * (1 - (fase - 0.5) * 2)
        l.save(); l.beginPath(); l.arc(lx, ly, lr + 0.5); l.clip()
        l.beginPath(); l.arc(lx + dx, ly, lr + 0.6); l.fill(gris(sky.arriba).alfa(0.92)); l.restore()
        l.restore()

        // Nubes de borde blando: de día claras, de noche jirones.
        let nc = noche > 0.5 ? Col(70, 84, 112) : Col(184, 198, 220), na = (0.16 + 0.10 * (1 - noche)) * apagado
        for i in 0..<4 {
            let vx = (Double(i) * 97 + t * Double(2 + i)).truncatingRemainder(dividingBy: HW + 160) - 80, vy = 36 + Double(i) * 24
            for k in 0..<4 {
                let px = vx + Double(k) * 16, py = vy + sin(Double(k) * 1.7 + Double(i)) * 3, rx = 26 - Double(k) * 2
                l.save(); l.translate(px, py); l.scale(1, 0.32)
                l.beginPath(); l.arc(0, 0, rx); l.fill(.radial(0, 0, 0, 0, 0, rx).parada(0, nc.alfa(na)).parada(1, nc.alfa(0)))
                l.restore()
            }
        }

        // Estamos arriba en el árbol: colinas en el horizonte y dos capas de copas abajo, con niebla que pasa.
        l.beginPath(); l.moveTo(0, HH)
        var x = 0.0; while x <= HW { l.lineTo(x, colinas(x)); x += 8 }
        l.lineTo(HW, HH); l.closePath(); l.fill(gris(sky.abajo).mezcla(Col(10, 14, 24), 0.22))
        for (ci, capa) in BOSQUE.enumerated() {
            let baseCapa = ci == 1 ? HH + 14 : HH - 18
            l.beginPath(); l.moveTo(-10, HH)
            for a in capa {
                let base = baseCapa + a.dy
                if a.pino {
                    l.lineTo(a.x - a.w / 2, base); l.lineTo(a.x - a.w * 0.3, base - a.h * 0.5); l.lineTo(a.x - a.w * 0.15, base - a.h * 0.5); l.lineTo(a.x, base - a.h)
                    l.lineTo(a.x + a.w * 0.15, base - a.h * 0.5); l.lineTo(a.x + a.w * 0.3, base - a.h * 0.5); l.lineTo(a.x + a.w / 2, base)
                } else {
                    l.lineTo(a.x - a.w / 2, base); l.quadraticCurveTo(a.x - a.w / 2, base - a.h, a.x, base - a.h); l.quadraticCurveTo(a.x + a.w / 2, base - a.h, a.x + a.w / 2, base)
                }
            }
            l.lineTo(HW + 10, HH); l.closePath(); l.fill(gris(sky.abajo).mezcla(Col(6, 9, 16), ci == 1 ? 0.7 : 0.42))
            let fa = (0.10 + 0.12 * noche + (e == .dormido ? 0.08 : 0)) * (ci == 1 ? 1 : 0.7), niebla = Col(170, 185, 215)
            for k in 0..<3 {
                let nx = (Double(k) * 140 + t * Double(3 + k + ci * 2)).truncatingRemainder(dividingBy: HW + 260) - 130, ny = baseCapa - 40 - Double(k) * 12
                l.save(); l.translate(nx, ny); l.scale(1, 0.22)
                l.beginPath(); l.arc(0, 0, 120); l.fill(.radial(0, 0, 0, 0, 0, 120).parada(0, niebla.alfa(fa)).parada(1, niebla.alfa(0)))
                l.restore()
            }
        }

        // Ramitas, detrás de la rama.
        for r in RAMITAS {
            let k = d.crece(r); guard k > 0 else { continue }
            l.beginPath(); l.moveTo(r.b.x, r.b.y)
            for i in 1...16 { let p = punto(r, Double(i) / 16 * k); l.lineTo(p.x, p.y) }
            l.stroke(Col("#2b3244"), 3.4); l.stroke(FRIO.alfa(0.10), 0.8)
        }

        rama(l)

        // Hojas en las ramitas y bajo la punta de la rama.
        let triste = e == .triste
        let tonos = triste ? [Col("#3a4a44"), Col("#44564d"), Col("#4b5c55")] : [Col("#3d5a4c"), Col("#4a6b59"), Col("#56785f")]
        for h in HOJAS.prefix(d.hojas) {
            var x: Double, y: Double, ang: Double
            if h.ram >= 0 {
                let r = RAMITAS[h.ram]; guard h.s <= d.crece(r) else { continue }
                let p = punto(r, h.s), q = punto(r, min(1, h.s + 0.02))
                (x, y, ang) = (p.x, p.y, atan2(q.y - p.y, q.x - p.x) + h.lado * 0.9)
            } else { (x, y, ang) = (h.x, yTop(h.x) + grosor(h.x) * (h.lado > 0 ? 0.9 : 0.2), h.lado > 0 ? 1.9 : -1.2) }
            let mece = quieto ? 0 : (0.06 + 0.22 * viento) * sin(t * (1.1 + h.tono * 0.6) + h.f)
            hoja(l, x, y, ang + mece + (triste ? 0.5 * h.lado : 0), h.largo, tonos[min(2, Int(h.tono * 3))], borde: noche > 0.4 ? FRIO.alfa(0.12 * noche) : nil)
        }

        // Flores de racha; la siguiente espera en capullo. Te busca: todas cerradas.
        for (i, (ri, s)) in FLORES.enumerated() where i <= d.flores {
            let r = RAMITAS[ri]; guard s <= d.crece(r) else { continue }
            let p = punto(r, s)
            flor(l, p.x, p.y - 1, abierta: !triste && i < d.flores, i, viva: i == d.flores - 1)
        }

        let luz = noche * apagado
        if d.tiene.contains("guirnalda") { guirnalda(l, luz) }
        if d.tiene.contains("nido") { nido(l) }
        if d.tiene.contains("seta") { setas(l, luz) }
        if d.tiene.contains("campanilla") { campanilla(l) }
        if d.tiene.contains("farolillo") { farolillo(l, luz) }
    }

    // Rama: cuerpo con degradado, corteza, nudo, sombra de Lumen, filo de luna y musgo.
    private func rama(_ l: Lienzo) {
        func contorno() {
            l.beginPath(); l.moveTo(-12, yTop(-12))
            var x = -12.0; while x <= 342 { l.lineTo(x, yTop(x)); x += 6 }
            l.quadraticCurveTo(348, yTop(340) + 3, 340, yTop(340) + grosor(340))
            x = 342; while x >= -12 { l.lineTo(x, yTop(x) + grosor(x)); x -= 6 }
            l.closePath()
        }
        contorno()
        l.fill(.lineal(0, 215, 0, 260).parada(0, Col("#4a5369")).parada(0.45, Col("#30374a")).parada(1, Col("#1d2231")))
        l.save(); contorno(); l.clip()
        for s in CORTEZA {
            let y = yTop(s.x) + 4 + s.k * (grosor(s.x) - 6)
            l.beginPath(); l.moveTo(s.x, y); l.quadraticCurveTo(s.x + s.w / 2, y + 1.2 * (s.k - 0.5), s.x + s.w, y + 0.6); l.stroke(Col(0, 0, 0, s.a), 1)
        }
        l.beginPath(); l.ellipse(40, yTop(40) + 15, 7, 4.5, -0.1); l.stroke(Col(0, 0, 0, 0.35), 1.4)
        l.beginPath(); l.ellipse(40, yTop(40) + 15, 3, 1.8, -0.1); l.fill(Col(0, 0, 0, 0.3))
        l.fillRect(HOGAR_X - 30, SUELO_HOGAR - 6, 60, 20, .radial(HOGAR_X, SUELO_HOGAR, 0, HOGAR_X, SUELO_HOGAR, 30).parada(0, Col(0, 0, 0, 0.35)).parada(1, Col(0, 0, 0, 0)))
        l.restore()
        l.beginPath(); var x = -12.0; while x <= 336 { l.lineTo(x, yTop(x) + 0.6); x += 6 }
        l.stroke(FRIO.alfa((0.14 + 0.16 * noche) * apagado), 1.2)
        let verdes = [Col("#2f4639"), Col("#3d5a4c"), Col("#4a6b59"), Col("#56785f")]
        for x in MUSGO where abs(x - HOGAR_X) >= 26 && abs(x - 74) >= 24 {
            for k in 0..<4 { l.beginPath(); mediaElipse(l, x + (Double(k) - 1.5) * 3, yTop(x) + 0.5 + Double(k % 2), 3.5, 1.8); l.fill(verdes[k]) }
        }
    }

    // MARK: Muebles

    private func nido(_ l: Lienzo) {
        let x = 74.0, y = yTop(74) - 4
        l.beginPath(); l.moveTo(x - 20, y - 4); l.bezierCurveTo(x - 18, y + 8, x + 18, y + 8, x + 20, y - 4); l.closePath(); l.fill(Col("#3e3630"))
        l.beginPath(); l.ellipse(x, y - 4, 20, 5); l.fill(Col("#211c18"))
        var r = Semilla(s: 5)
        for _ in 0..<9 { let a = x - 19 + r.next() * 38, b = y - 3 + r.next() * 7; l.beginPath(); l.moveTo(a, b); l.lineTo(a + 6 + r.next() * 6, b + (r.next() - 0.5) * 4); l.stroke(Col("#6b5a4b"), 1.1) }
        l.beginPath(); l.moveTo(x - 18, y - 6); l.quadraticCurveTo(x, y - 11, x + 18, y - 6); l.stroke(FRIO.alfa(0.18), 1)
    }
    private func setas(_ l: Lienzo, _ luz: Double) {
        let x0 = 22.0, y0 = yTop(22)
        for (i, (dx, h, r)) in [(-6.0, 9.0, 5.0), (3, 13, 6.5), (10, 7, 4)].enumerated() {
            let x = x0 + dx
            l.beginPath(); l.moveTo(x - 1.2, y0); l.quadraticCurveTo(x + 1, y0 - h / 2, x, y0 - h); l.lineTo(x + 1.6, y0 - h); l.quadraticCurveTo(x + 2.4, y0 - h / 2, x + 1.4, y0); l.fill(Col("#9aa6bc"))
            let brillo = 0.15 + 0.35 * luz + 0.08 * sin(t * 0.8 + Double(i) * 2)
            halo(l, x, y0 - h - 1, r * 2.4, FRIO, 0.05 * (0.4 + luz), Double(i))
            l.beginPath(); mediaElipse(l, x + 0.2, y0 - h, r, r * 0.62)
            l.fill(.lineal(0, y0 - h - r, 0, y0 - h).parada(0, CLARO.alfa(0.55 + brillo)).parada(1, Col(150, 175, 215, 0.6 + brillo * 0.5)))
            for k in 0..<3 { l.beginPath(); l.arc(x - r * 0.5 + Double(k) * r * 0.5, y0 - h - r * 0.32 + Double(k % 2), 0.6); l.fill(Col(255, 255, 255, 0.8)) }
        }
    }
    private func campanilla(_ l: Lienzo) {
        let x = 266.0, y = yTop(x) + grosor(x) - 2
        let c = colgante(x, y, 12, 1)
        l.beginPath(); l.moveTo(x, y); l.lineTo(c.x, c.y); l.stroke(Col(160, 172, 196, 0.6), 0.7)
        l.save(); l.translate(c.x, c.y); l.rotate(-c.a * 0.5)
        l.beginPath(); l.ellipse(0, 0, 7, 2); l.fill(Col("#5a6680"))
        for (i, dx) in [-5.0, -1.7, 1.7, 5].enumerated() {
            let largo = [15.0, 19, 17, 13][i], b = d.reducir ? 0 : (0.06 + 0.2 * viento) * sin(t * (1.7 + Double(i) * 0.3) + Double(i))
            l.save(); l.translate(dx, 1); l.rotate(b)
            l.beginPath(); l.moveTo(0, 0); l.lineTo(0, 3); l.stroke(Col(160, 172, 196, 0.5), 1)
            l.beginPath(); l.roundRect(-1.1, 3, 2.2, largo, 1.1)
            l.fill(.lineal(0, 3, 0, 3 + largo).parada(0, Col(223, 232, 248, 0.55)).parada(1, Col(223, 232, 248, 0.15)))
            l.restore()
        }
        if viento > 0.6 { l.beginPath(); l.arc(0, 16, 1.2); l.fill(Col(255, 255, 255, (viento - 0.6) * 1.5)) }
        l.restore()
    }
    private func farolillo(_ l: Lienzo, _ luz: Double) {
        let b = punto(RAMITAS[0], 0.88), c = colgante(b.x, b.y, 12, 2.4)
        l.beginPath(); l.moveTo(b.x, b.y); l.lineTo(c.x, c.y); l.stroke(Col(160, 172, 196, 0.6), 0.8)
        l.save(); l.translate(c.x, c.y); l.rotate(-c.a)
        halo(l, 0, 13, 22, FRIO, 0.04 + 0.05 * luz, 3)
        l.beginPath(); l.roundRect(-5, 0, 10, 2.6, 1.3); l.fill(Col("#5a6680"))
        l.beginPath(); l.roundRect(-3.5, 23, 7, 2.4, 1.2); l.fill(Col("#5a6680"))
        l.beginPath(); l.ellipse(0, 12.5, 8.5, 11); l.fill(Col(223, 232, 248, 0.12 + 0.1 * luz)); l.stroke(Col("#5a6680"), 1.3)
        l.beginPath(); l.ellipse(0, 12.5, 3.8, 5.6); l.fill(CLARO.alfa(0.45 + 0.25 * luz + 0.05 * sin(t * 2.1)))
        for yy in [7.5, 12.5, 17.5] { l.beginPath(); l.moveTo(-8, yy); l.quadraticCurveTo(0, yy - 1, 8, yy); l.stroke(Col(90, 102, 128, 0.8), 0.8) }
        l.restore()
    }
    // Dos guirnaldas colgando bajo la rama: así no cruzan a Lumen.
    private func guirnalda(_ l: Lienzo, _ luz: Double) {
        for (x0, x1, n0) in [(4.0, 96.0, 0), (96, 196, 6)] {
            let a = (x: x0, y: yTop(x0) + grosor(x0) - 3), b = (x: x1, y: yTop(x1) + grosor(x1) - 3)
            let caida = 16 + 1.5 * viento * sin(t * 1.3 + x0)
            func pt(_ s: Double) -> P { (a.x + (b.x - a.x) * s, a.y + (b.y - a.y) * s + caida * 4 * s * (1 - s)) }
            l.beginPath(); for i in 0...30 { let p = pt(Double(i) / 30); l.lineTo(p.x, p.y) }
            l.stroke(Col(150, 162, 186, 0.45), 0.7)
            for j in 1..<7 {
                let i = Double(j + n0), p = pt(Double(j) / 7), v = 0.5 + 0.5 * sin(t * (0.6 + Double((j + n0) % 3) * 0.25) + i * 1.7)
                halo(l, p.x, p.y + 3, 6, FRIO, 0.05 * (0.5 + v) * (0.4 + luz), i)
                l.beginPath(); l.ellipse(p.x, p.y + 3, 1.6, 2.2); l.fill(CLARO.alfa(0.35 + 0.4 * luz + 0.25 * v))
            }
        }
    }

    // MARK: Delante de Lumen

    private func pasoFrente(_ dt: Double, _ quieto: Bool) {
        let foco = d.estado == .foco, nl = d.luciernagas
        for i in luci.indices {
            var f = luci[i]
            f.a += ((i < nl ? 1 : 0) - f.a) * min(1, dt * 0.8)
            var tx: Double, ty: Double
            if quieto { (tx, ty) = (f.hx, f.hy) }
            else if foco {
                // En foco rodean a Lumen, lo bastante lejos para no perderse sobre su cuerpo blanco.
                let ang = t * 0.25 + Double(i) / Double(max(1, nl)) * PI2
                (tx, ty) = (HOGAR_X + cos(ang) * (86 + 8 * sin(t * 0.5 + Double(i))), SUELO_HOGAR - 62 + sin(ang) * 38)
            } else {
                (tx, ty) = (f.hx + 22 * sin(t * 0.21 + f.ph) + 9 * sin(t * 0.53 + f.ph * 2), f.hy + 14 * sin(t * 0.17 + f.ph * 1.3) + 6 * sin(t * 0.61 + f.ph))
            }
            let k = min(1, dt * (foco ? 0.9 : 0.6))
            f.x += (tx - f.x) * k; f.y += (ty - f.y) * k
            luci[i] = f
        }
        guard !quieto else { caen = []; motas = []; return }
        // Te busca: alguna hoja se suelta y cae despacio. Con ráfagas fuertes también, muy de vez en cuando.
        if ((d.estado == .triste && Double.random(in: 0..<1) < dt * 0.25) || (rafaga > 0.8 && Double.random(in: 0..<1) < dt * 0.15)) && caen.count < 4 {
            let p = punto(RAMITAS[Int.random(in: 0..<3)], azar(0.4, 0.9)); caen.append((p.x, p.y, 0, azar(0, 6), 1))
        }
        caen = caen.compactMap { var p = $0
            p.vy = min(14, p.vy + 6 * dt); p.y += p.vy * dt; p.x += sin(t * 1.6 + p.a) * 12 * dt; p.a += dt * 1.2
            if p.y > HH - 8 { p.v -= dt / 0.8 }
            return p.v > 0 ? p : nil
        }
        // Bien hecho: motas de luz que suben desde Lumen.
        if d.estado == .fin && Double.random(in: 0..<1) < dt * 14 && motas.count < 26 {
            motas.append((HOGAR_X + azar(-25, 25), SUELO_HOGAR - 20 - azar(0, 30), azar(-4, 4), 1))
        }
        motas = motas.compactMap { var m = $0; m.y -= 22 * dt; m.x += m.vx * dt; m.v -= dt / 2.4; return m.v > 0 ? m : nil }
    }

    func frente(_ l: Lienzo) {
        let foco = d.estado == .foco
        for (i, f) in luci.enumerated() where f.a > 0.01 {
            let pulso = d.reducir ? 0.8 : foco ? 0.55 + 0.45 * sin(t * PI2 / 4.2) : 0.5 + 0.5 * sin(t * 0.9 + f.ph * 3)
            let al = f.a * (d.estado == .dormido ? 0.4 : 1) * (0.45 + 0.55 * pulso) * (0.65 + 0.35 * noche)
            halo(l, f.x, f.y, 12, FRIO, 0.12 * al, Double(i))
            l.beginPath(); l.arc(f.x, f.y, 1.7); l.fill(Col(245, 250, 255, 0.9 * al))
        }
        let hojaCae = d.estado == .triste ? Col("#44564d") : Col("#4a6b59")
        for p in caen { l.save(); l.alfa = p.v; hoja(l, p.x, p.y, sin(p.a) * 1.2, 10, hojaCae); l.restore() }
        for m in motas { l.beginPath(); l.arc(m.x, m.y, 1.1); l.fill(CLARO.alfa(0.85 * sin(m.v * .pi))) }
    }
}
