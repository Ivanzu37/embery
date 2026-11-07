// Embery · el Scriptorium: traduce lo que hace una conversación de Claude Code en una actividad que el Hueco puede enseñar.
import Foundation

enum Actividad: String {
    case hojea, escribe, mecanismo, ventana, ayudante, piensa, mano, descansa, cabecea, duerme

    static func de(_ s: SessionInfo?, ahora: Date) -> Actividad {
        guard let s else { return .duerme }
        switch s.state {
        case .perm: return .mano
        case .working:
            switch s.tool {
            case "Read", "Grep", "Glob": return .hojea
            case "Edit", "Write", "NotebookEdit": return .escribe
            case "Bash": return .mecanismo
            case "WebFetch", "WebSearch": return .ventana
            case "Agent", "Task": return .ayudante
            default: return .piensa
            }
        case .idle:
            let t = ahora.timeIntervalSince(s.lastEvent)
            return t < 120 ? .descansa : t < 600 ? .cabecea : .duerme
        }
    }

    // Manda la que pide algo, luego la que trabaja; a igual rango, la más reciente.
    static func principal(_ sesiones: [SessionInfo]) -> SessionInfo? {
        func rango(_ s: SessionInfo) -> Int { s.state == .perm ? 2 : s.state == .working ? 1 : 0 }
        return sesiones.max { (rango($0), $0.lastEvent) < (rango($1), $1.lastEvent) }
    }

    var texto: String {
        switch self {
        case .hojea: String(localized: "hojea")
        case .escribe: String(localized: "escribe")
        case .mecanismo: String(localized: "maneja el mecanismo")
        case .ventana: String(localized: "mira por la ventana")
        case .ayudante: String(localized: "llama a un ayudante")
        case .piensa: String(localized: "piensa")
        case .mano: String(localized: "levanta la mano")
        case .descansa: String(localized: "descansa")
        case .cabecea: String(localized: "cabecea")
        case .duerme: String(localized: "duerme")
        }
    }
}

private let ALTO = 110.0, NOTCH = 32.0, SUELO = 104.0
private let CIELO: [(Double, Col, Col)] = [(0, Col("#34416c"), Col("#e6a27b")), (0.35, Col("#4d7dbe"), Col("#a8cbe8")), (0.7, Col("#2c3264"), Col("#d47d5c")), (1, Col("#060a1a"), Col("#121d40"))]

private func cielo(_ b: Double) -> (Col, Col) {
    var i = 0
    while i < CIELO.count - 2 && b > CIELO[i + 1].0 { i += 1 }
    let (a, b0, b1) = CIELO[i], (c, d0, d1) = CIELO[i + 1], k = suave((b - a) / (c - a))
    return (b0.mezcla(d0, k), b1.mezcla(d1, k))
}

// Lo que enseña la tarjeta de una mesa; se copia del Scriptorium una vez por segundo.
struct FichaMesa: Equatable {
    var id: String?
    var nombre = "", actividad = "", archivo = ""
    var viva = true
    var tareas: [Tarea] = []
    var ctx: Int?
    var ayudantes = 0
}

// La sala bajo el notch: paredes, ventana (bloque de 5 h), estantería y luz de conjunto, con una mesa por conversación
// en orden de llegada, hasta cuatro. Unidades de la tira: 110 de alto, 320 de ancho con una mesa y 136 más por cada otra.
final class Scriptorium {
    static let base = 320.0, modulo = 136.0, maxMesas = 4, esperaVacia = 20.0
    static func ancho(mesas n: Int) -> Double { base + Double(max(1, min(n, maxMesas)) - 1) * modulo }

    // id nil: la mesa de nadie (sin conversación, el escribiente duerme).
    private(set) var mesas: [(id: String?, e: Escribiente, seFue: Date?)] = [(nil, Escribiente(), nil)]
    private(set) var extra = 0
    private(set) var t = 0.0
    private var bloqueObj: Double?, bloque = 0.5, niebla = 0.0, velo = 0.0
    private var reinicio: (t: Double, a: Double)?
    // Con «Reducir movimiento» solo se repinta cuando algo cambió.
    var sucio = true
    private struct Libro { var x, y, w, h: Double; var tumbado: Bool; var c: Col; var l: Double }
    private var libros: [Libro] = []

    init() {
        mesas[0].e.poner(.duerme); mesas[0].e.ctxObj = nil; mesas[0].e.contexto = 0
        let r = semilla(7)
        let lomos = ["#3a2c2a", "#2c3340", "#3b3524", "#2a3a33", "#43302e", "#2f2c3a", "#463a26"]
        for y in [50.0, 64, 78, 92] {
            var x = 230.5
            while x < 295 {
                let w = 1.8 + r() * 1.9, h = 7.5 + r() * 4.5, tumbado = r() < 0.08
                let c = Col(lomos[Int(r() * 7)]), l = r()
                libros.append(Libro(x: x, y: y, w: w, h: h, tumbado: tumbado, c: c, l: l))
                x += (tumbado ? h : w) + 0.25 + (r() < 0.12 ? 2.5 : 0)
            }
        }
    }

    var trabaja: Bool { mesas.contains { $0.e.trabaja } || reinicio != nil || abs(niebla - (bloqueObj == nil ? 1 : 0)) > 0.01 }

    static func contexto(_ s: SessionInfo) -> Double? {
        // shortcut: sin % de la statusline se estima sobre 200k tokens; con ventanas de 1M se queda corto hasta que llega el %.
        s.ctx.map { Double($0) / 100 } ?? s.tokens.map { min(1, Double($0) / 200_000) }
    }

    // Devuelve si algún escribiente se acaba de poner a escribir (para la pluma).
    @discardableResult
    func sincronizar(_ sesiones: [SessionInfo], ahora: Date = Date()) -> Bool {
        var empiezaAEscribir = false
        let porId = Dictionary(sesiones.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let antes = mesas.map { "\($0.id ?? "")\($0.e.viva)" }
        mesas.removeAll { m in m.seFue.map { ahora.timeIntervalSince($0) > Self.esperaVacia } ?? false }
        for i in mesas.indices where mesas[i].e.viva {
            guard let id = mesas[i].id, porId[id] == nil else { continue }
            // La última que se va no se retira: se queda como la mesa de nadie y su escribiente se duerme.
            if porId.isEmpty && mesas.filter({ $0.e.viva }).count == 1 { mesas[i].id = nil }
            else { mesas[i].e.terminar(); mesas[i].seFue = ahora }
        }
        let sentadas = Set(mesas.compactMap(\.id))
        var extra = 0
        for s in sesiones.filter({ !sentadas.contains($0.id) }).sorted(by: { $0.lastEvent < $1.lastEvent }) {
            if let i = mesas.firstIndex(where: { $0.id == nil && $0.e.viva }) { mesas[i].id = s.id }
            else if mesas.count < Self.maxMesas {
                let e = Escribiente()
                e.colocar(Double(mesas.count) * Self.modulo)
                e.ctxObj = Self.contexto(s); e.contexto = e.ctxObj ?? 0
                mesas.append((s.id, e, nil))
            } else { extra += 1 }
        }
        self.extra = extra
        for m in mesas where m.e.viva {
            guard let id = m.id, let s = porId[id] else {
                m.e.poner(.duerme); m.e.ctxObj = m.e.ctxObj == nil ? nil : 0; m.e.tareas([]); m.e.ponerAyudantes(0)
                continue
            }
            let a = Actividad.de(s, ahora: ahora)
            if a != m.e.actividad { if a == .escribe { empiezaAEscribir = true }; m.e.poner(a); sucio = true }
            let c = Self.contexto(s)
            if c != m.e.ctxObj { m.e.ctxObj = c; sucio = true }
            if m.e.notas.map(\.clave) != s.tareas.map(\.clave) || m.e.notas.map(\.estado) != s.tareas.map(\.estado) { m.e.tareas(s.tareas); sucio = true }
            let n = max(s.ayudantes, a == .ayudante ? 1 : 0)
            if n != m.e.cuantosAyudantes { m.e.ponerAyudantes(n); sucio = true }
        }
        if antes != mesas.map({ "\($0.id ?? "")\($0.e.viva)" }) { sucio = true }
        return empiezaAEscribir
    }

    func fichas(_ sesiones: [String: SessionInfo]) -> [FichaMesa] {
        mesas.map { m in
            guard m.e.viva, let id = m.id, let s = sesiones[id] else { return FichaMesa(id: m.id, viva: false) }
            return FichaMesa(id: id, nombre: s.name, actividad: m.e.actividad.texto, archivo: s.archivo, tareas: s.tareas,
                             ctx: Self.contexto(s).map { Int(($0 * 100).rounded()) }, ayudantes: m.e.cuantosAyudantes)
        }
    }

    // nil: sin dato. Si el bloque se renueva (cae más de 0,5), la noche cierra la ventana y abre ya en el nuevo.
    func ponerBloque(_ b: Double?) {
        guard let b else { if bloqueObj != nil { bloqueObj = nil; sucio = true }; return }
        if reinicio != nil { reinicio!.a = b; return }
        if bloqueObj == nil { bloqueObj = b; bloque = b; sucio = true }
        else if b < bloque - 0.5 { reinicio = (0, b); sucio = true }
        else if b != bloqueObj { bloqueObj = b; sucio = true }
    }

    func actualizar(_ dt: Double) {
        t += dt
        for (i, m) in mesas.enumerated() { m.e.mover(hacia: Double(i) * Self.modulo, dt); m.e.actualizar(dt) }
        if var r = reinicio {
            r.t += dt
            velo = r.t < 0.6 ? suave(r.t / 0.6) : 1 - suave((r.t - 0.6) / 1.2)
            if r.t >= 0.6 { bloque = r.a; bloqueObj = r.a }
            reinicio = r.t >= 1.8 ? nil : r
            if reinicio == nil { velo = 0 }
        } else if let b = bloqueObj { bloque += (b - bloque) * min(1, dt * 1.5) }
        niebla += ((bloqueObj == nil ? 1 : 0) - niebla) * min(1, dt * 1.2)
    }
    // Reducir movimiento: la escena se asienta de golpe y se pinta una vez.
    func asentar() { for _ in 0..<90 { actualizar(1.0 / 30) }; sucio = false }

    // En unidades de la tira, con el lienzo ya escalado; ancho es el de la vista en esas unidades.
    func pintar(_ l: Lienzo, ancho W: Double, escala: Double) {
        let b = bloqueObj == nil ? 0.5 : bloque
        let luz = mesas.map(\.e.luzSala).max() ?? 0.3, calor = mesas.map(\.e.calor).max() ?? 0
        let frioSala = 1 - 0.6 * suave((b - 0.55) / 0.45)
        l.save()
        l.ctx.setLineCap(.butt)
        sala(l, W)
        ventana(l, b, frio: frioSala * (0.5 + 0.5 * luz))
        l.save(); l.translate(W - Self.base, 0); estanteria(l, calor); l.restore()
        for m in mesas { m.e.u = escala; l.save(); l.translate(m.e.off, 0); m.e.pintarRincon(l, frioSala: frioSala); l.restore() }
        l.fillRect(0, NOTCH, W, ALTO, Col(0, 0, 0, (1 - luz) * 0.62))
        for m in mesas { l.save(); l.translate(m.e.off, 0); m.e.pintarChispa(l); l.restore() }
        l.fillRect(0, NOTCH, W, ALTO, .radial(W / 2, 72, 40 * W / Self.base, W / 2, 72, 190 * W / Self.base).parada(0, Col(0, 0, 0, 0)).parada(1, Col(0, 0, 0, 0.55)))
        if extra > 0 {
            l.beginPath(); l.roundRect(W - 38, 90, 26, 14, 7); l.fill(Col(0, 0, 0, 0.6))
            l.texto("+\(extra)", W - 25, 97, tamano: 11, peso: .medium, color: Col("#d2e4ff"))
        }
        // El notch: negro, y la sala nace de él sin raya.
        l.fillRect(0, NOTCH, W, 7, .lineal(0, NOTCH, 0, NOTCH + 7).parada(0, Col(0, 0, 0)).parada(1, Col(0, 0, 0, 0)))
        l.fillRect(0, 0, W, NOTCH, Col(0, 0, 0))
        l.restore()
    }

    private func sala(_ l: Lienzo, _ W: Double) {
        l.fillRect(0, NOTCH, W, SUELO - NOTCH, .lineal(0, NOTCH, 0, SUELO).parada(0, Col("#14161d")).parada(1, Col("#191b22")))
        let rejilla = Col(255, 255, 255, 0.025)
        var f = 0
        for y in stride(from: 44.0, to: SUELO, by: 9) {
            l.beginPath(); l.moveTo(0, y); l.lineTo(W, y); l.stroke(rejilla, 0.4)
            for x in stride(from: Double(f % 2) * 11, to: W, by: 22) { l.beginPath(); l.moveTo(x, y); l.lineTo(x, y + 9); l.stroke(rejilla, 0.4) }
            f += 1
        }
        l.fillRect(0, SUELO, W, ALTO - SUELO, .lineal(0, SUELO, 0, ALTO).parada(0, Col("#101117")).parada(1, Col("#0a0b0e")))
        l.fillRect(0, SUELO, W, 0.4, Col(255, 255, 255, 0.05))
    }

    private func ventana(_ l: Lienzo, _ b: Double, frio: Double) {
        let (arriba, abajo) = cielo(b), x0 = 22.0, x1 = 52.0, cx = 37.0, r = 15.0, base = 92.0, hombro = 56.0
        func hueco() { l.beginPath(); l.moveTo(x0, base); l.lineTo(x0, hombro); l.arc(cx, hombro, r, .pi, 0); l.lineTo(x1, base); l.closePath() }
        // Haz de luz fría hacia el suelo.
        l.save(); l.sumaLuz = true
        poli(l, [Punto(x: x0, y: 48), Punto(x: x1, y: 44), Punto(x: 108, y: SUELO), Punto(x: 40, y: SUELO)])
        l.fill(.lineal(37, 60, 80, 104).parada(0, Col(150, 185, 240, 0.1 * frio)).parada(1, Col(150, 185, 240, 0)))
        l.fillRect(38, SUELO, 64, 2.5, .lineal(40, 0, 100, 0).parada(0, Col(150, 185, 240, 0.16 * frio)).parada(1, Col(150, 185, 240, 0)))
        l.restore()
        // Jamba de piedra.
        l.beginPath(); l.moveTo(x0 - 2.5, base); l.lineTo(x0 - 2.5, hombro); l.arc(cx, hombro, r + 2.5, .pi, 0); l.lineTo(x1 + 2.5, base); l.closePath()
        l.fill(Col("#23252c"))
        hueco(); l.fill(.lineal(0, hombro - r, 0, base).parada(0, arriba).parada(1, abajo))
        l.save(); hueco(); l.clip()
        let claro = 1 - niebla
        let noche = suave((b - 0.6) / 0.3) * claro
        if noche > 0 {
            let r2 = semilla(3)
            for i in 0..<26 {
                let sx = x0 + r2() * 30, sy = 42 + r2() * 46, tw = 0.6 + 0.4 * sin(t * (1 + r2() * 2) + Double(i))
                l.fillRect(sx, sy, 0.45, 0.45, Col(230, 236, 255, noche * tw * (0.4 + r2() * 0.6) * (1 - (sy - 42) / 60)))
            }
        }
        let luna = suave((b - 0.72) / 0.2) * claro
        if luna > 0 {
            let lx = 44.0, ly = 58 - luna * 6
            l.beginPath(); l.arc(lx, ly, 2.6); l.fill(Col(236, 240, 255, 0.9 * luna))
            l.beginPath(); l.arc(lx + 1.1, ly - 0.6, 2.3); l.fill(arriba.mezcla(abajo, 0.3))
        }
        let sol = (1 - suave(b / 0.3)) * claro
        if sol > 0 {
            l.fillRect(x0, 60, 30, 32, .radial(31, 92, 0, 31, 92, 20).parada(0, Col(255, 210, 160, 0.5 * sol)).parada(1, Col(255, 210, 160, 0)))
        }
        l.restore()
        // El día pleno no compite con la vela; sin dato, niebla; al renovarse el bloque, la noche cierra un instante.
        hueco(); l.fill(Col(0, 0, 0, 0.22 * (1 - suave((b - 0.6) / 0.3))))
        if niebla > 0.01 { hueco(); l.fill(Col(112, 118, 130, 0.85 * niebla)) }
        if velo > 0 { hueco(); l.fill(Col(6, 10, 26, velo)) }
        // Parteluz, travesaño y alféizar.
        l.fillRect(cx - 0.6, hombro - r, 1.2, base - hombro + r, Col("#1b1c22")); l.fillRect(x0, 70, x1 - x0, 1.1, Col("#1b1c22"))
        l.fillRect(x0 - 4, base, x1 - x0 + 8, 2.2, Col("#2a2c33"))
        l.fillRect(x0 - 4, base, x1 - x0 + 8, 0.4, Col(170, 200, 255, 0.25 * frio))
    }

    private func estanteria(_ l: Lienzo, _ calor: Double) {
        let madera = Col("#1d1a1b")
        l.fillRect(228, 37, 70, SUELO - 37, Col("#121216"))
        for k in libros {
            if k.tumbado { l.fillRect(k.x, k.y - k.w, k.h, k.w, k.c) } else { l.fillRect(k.x, k.y - k.h, k.w, k.h, k.c) }
            if !k.tumbado { l.fillRect(k.x, k.y - k.h * 0.7, k.w, 0.4, Col(255, 220, 180, 0.05 + 0.06 * k.l)) }
        }
        l.fillRect(226, 36, 3, SUELO - 36, madera); l.fillRect(297, 36, 3, SUELO - 36, madera); l.fillRect(225, 35, 76, 2, madera)
        for y in [50.0, 64, 78, 92] { l.fillRect(228, y, 70, 1.4, madera) }
        l.fillRect(226, 36, 0.5, SUELO - 36, Col(240, 150, 100, 0.18 * calor))
    }
}
