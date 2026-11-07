import Foundation

// El escribiente del Scriptorium: Claude como monje en su mesa, una por conversación. Solo pinta su rincón
// (tablón, mesa, atril, ayudantes, figura); la sala la pinta el Scriptorium. Port de escribiente.js y scriptorium.js (v5).

private let ALTO = 110.0, NOTCH = 32.0, SUELO = 104.0, MESA = 84.0, CANTO = 114.0, PILA = 185.0
private let CADERA = Punto(x: 102, y: 94), TORSO = 24.0, BRAZO = [9.0, 8.0], MANO = 1.1
private let TINTERO = Punto(x: 121.5, y: 82.4), BOCA = Punto(x: 121.6, y: 80.4), TAZA = Punto(x: 116.6, y: 83), RUEDA = Punto(x: 131.5, y: 82.1), CHISPA = Punto(x: 160, y: 70.5)
// Atril: el lomo del libro sube de P0 por U; V va al fondo y N sale de la tabla hacia el que mira.
private let P0 = Punto(x: 128, y: 79.2), U = Punto(x: 13, y: -7.4), V = Punto(x: 2.6, y: -3.4), N = Punto(x: -1.5, y: -3.3)
private let DESCANSOS: [String: Double] = ["te": 7.5, "estirarse": 5.5, "ventana": 6, "respirar": 6]
private let RAPIDEZ: [String: Double] = ["incl": 4.5, "cabeza": 5.5, "giro": 4, "mirarY": 7, "cierre": 9, "chispa": 7, "luz": 1.6, "pluma": 7]
private let RENGLONES = 6, PUNTA = 1.6
private let CORAL = Col("#e0825a"), HABITO = [Col("#3b4458"), Col("#202632")], PIEL = Col("#d6c6b0")
private let LUZ = [255.0, 205, 130], LUZ_FRIA = [150.0, 195, 255]
private let CABECEOS = ["lee": 10.0, "cabecea": 12.0]
private let REPOSO: Set<Actividad> = [.descansa, .cabecea, .duerme]

private func pt(_ s: Double, _ v: Double, _ h: Double = 0) -> Punto {
    Punto(x: P0.x + s * U.x + v * V.x + h * N.x, y: P0.y + s * U.y + v * V.y + h * N.y)
}
private func dist(_ a: Punto, _ b: Punto) -> Double { hypot(a.x - b.x, a.y - b.y) }
private func bump(_ x: Double, _ c: Double, _ w: Double) -> Double { exp(-pow((x - c) / w, 2)) }

private struct Muelle {
    var x = 0.0, v = 0.0
    mutating func hacia(_ obj: Double, _ w: Double, _ dt: Double) {
        v += (w * w * (obj - x) - 2 * w * v) * dt; x += v * dt
    }
}

func poli(_ l: Lienzo, _ ps: [Punto]) {
    l.beginPath()
    for (i, p) in ps.enumerated() { if i == 0 { l.moveTo(p.x, p.y) } else { l.lineTo(p.x, p.y) } }
    l.closePath()
}
// Azar con semilla para que estantería y papeles no cambien entre fotogramas.
func semilla(_ inicio: Int) -> () -> Double {
    var n = inicio
    return { n = n * 16807 % 2147483647; return Double(n) / 2147483647 }
}

// Torso en coordenadas (a lo largo del espinazo, hacia delante); el frente se usa también para el choque con la mesa.
private let TORSO_ESPALDA: [(Double, Double)] = [(1.5, -6.6), (12, -7.6), (21.5, -6.4), (24.6, -3.6), (24.8, 0.2)]
private let TORSO_FRENTE: [(Double, Double)] = [(24.4, 3.4), (21.5, 4.6), (13, 5.8), (3, 7.2), (0, 7)]

private struct Mano {
    var x: Double, y: Double, vx = 0.0, vy = 0.0
    var punto: Punto { Punto(x: x, y: y) }
}

final class Escribiente: Mascota {
    private var s: [String: Muelle] = [
        "incl": Muelle(x: -0.1), "cabeza": Muelle(), "giro": Muelle(), "mirarY": Muelle(),
        "cierre": Muelle(), "chispa": Muelle(x: 0.85), "luz": Muelle(x: 1), "pluma": Muelle(x: 1.2),
    ]
    private var mD = Mano(x: 110, y: 88), mT = Mano(x: 108, y: 88)
    private(set) var plumaEnMano = false
    private var tazaEnMano = false
    private var renglon = 2.5, lineasFrente = 2
    private var pagina: (t0: Double, despues: Int, antes: Int)?
    private var proxPagina = 0.0
    private var rueda = 0.0, humoT = 0.0
    private struct Ayudante { var x = 250.0, v = 0.0, paso = 0.0, vivo = true }
    private var ayudantes: [Ayudante] = []
    private var variante = "", tVar = 0.0, desorden = 0.4
    // contexto es lo que se pinta (suavizado); ctxObj, lo último que llegó; nil = sin dato, mesa sin papeles.
    var contexto = 0.3, ctxObj: Double? = 0.3
    private struct Volando { var x, y, vx, vy, rot, vr, vida: Double }
    private var vuelan: [Volando] = []
    private(set) var falta = 0.0, choque = 0.0
    private var ev: (nombre: String, t: Double)?
    private(set) var act = ""
    private var tAct = 0.0
    private var pendiente: String?
    var incl: Double { s["incl"]!.x }
    private struct Hoja { var dx, inc, tono: Double }
    private var hojas: [Hoja] = []
    private(set) var calor = 0.0
    private var frio = 0.0, ch = 0.0, brasa = 0.0
    struct Nota { var clave: String; var estado: Tarea.Estado; var t0, tCambio: Double }
    private(set) var notas: [Nota] = []
    // v5: lo que pide la conversación (cabecea alterna «lee» y cabecear) y la vida de la mesa en la sala.
    private(set) var actividad: Actividad = .duerme
    private var subvar = "lee", tSub = 0.0
    private(set) var viva = true, presencia = 0.0
    private var tVida = 0.0, humoFin = false
    private(set) var off = 0.0
    private var offV = 0.0
    var trabaja: Bool { ev != nil || !REPOSO.contains(actividad) || abs(offV) > 0.5 || (viva ? presencia < 1 : presencia > 0) || !vuelan.isEmpty }

    override init() {
        super.init()
        setActividad("descansa")
        s["chispa"] = Muelle(); s["luz"] = Muelle(x: 0.3)
        let r = semilla(7)
        hojas = (0..<22).map { _ in Hoja(dx: r() - 0.5, inc: r() - 0.5, tono: r()) }
    }
    override func dibujarParticulas(_ l: Lienzo) {
        for q in particulas {
            let f = q.vida / q.max, vive = sin(f * .pi), r = q.r * (1 + f * 2)
            l.beginPath(); l.arc(q.x, q.y, r)
            l.fill(.radial(q.x, q.y, 0, q.x, q.y, r).parada(0, Col(170, 165, 160, 0.3 * vive)).parada(1, Col(170, 165, 160, 0)))
        }
    }

    override func mania() {}

    func setActividad(_ a: String) {
        if ev != nil { pendiente = a; return }
        if a == act { return }
        act = a; tAct = 0
        if a == "descansa" { nuevaVariante() }
        if a == "hojea" { proxPagina = 1.4 }
    }
    func evento(_ nombre: String) { ev = (nombre, 0) }

    func poner(_ a: Actividad) {
        guard a != actividad else { return }
        let antes = actividad
        actividad = a
        if REPOSO.contains(antes) && !REPOSO.contains(a) { evento("prompt") }
        else if !REPOSO.contains(antes) && a == .descansa { evento("stop") }
        if a == .cabecea { subvar = Bool.random() ? "lee" : "cabecea"; tSub = 0 }
        setActividad(mapa)
    }
    private var mapa: String { actividad == .cabecea && subvar == "lee" ? "hojea" : actividad.rawValue }

    func ponerAyudantes(_ n: Int) {
        let vivos = ayudantes.indices.filter { ayudantes[$0].vivo }
        if vivos.count < min(n, 3) { ayudantes += Array(repeating: Ayudante(), count: min(n, 3) - vivos.count) }
        for i in vivos.dropFirst(max(0, n)) { ayudantes[i].vivo = false }
    }
    var cuantosAyudantes: Int { ayudantes.filter(\.vivo).count }

    // La lista entera cada vez: se casan por clave; lo nuevo se clava y lo que cambia de estado se apunta.
    func tareas(_ lista: [Tarea]) {
        let antes = Dictionary(notas.map { ($0.clave, $0) }, uniquingKeysWith: { a, _ in a })
        notas = lista.map { n in
            guard var v = antes[n.clave] else { return Nota(clave: n.clave, estado: n.estado, t0: t, tCambio: t) }
            if v.estado != n.estado { v.estado = n.estado; v.tCambio = t }
            return v
        }
    }
    // Las que caben: en curso y pendientes primero; una recién hecha se queda 2 s en su sitio antes de ceder el hueco.
    var visibles: [Nota] {
        func peso(_ n: Nota) -> Int { n.estado == .hecha && t - n.tCambio > 2 ? 1 : 0 }
        return notas.enumerated().sorted { (peso($0.element), $0.offset) < (peso($1.element), $1.offset) }.prefix(6).map(\.element)
    }

    func terminar() { if viva { viva = false; tVida = 0 } }
    func mover(hacia x: Double, _ dt: Double) {
        var m = Muelle(x: off, v: offV); m.hacia(x, 6, dt); off = m.x; offV = m.v
    }
    func colocar(_ x: Double) { off = x; offV = 0 }
    var luzSala: Double { s["luz"]!.x * max(presencia, 0.3) }
    private func nuevaVariante() {
        if tazaEnMano { return }   // no se cambia de descanso con la taza en la mano
        let otras = DESCANSOS.keys.filter { $0 != variante }
        variante = otras.randomElement() ?? variante; tVar = 0
    }
    private func pasarPagina(_ despues: Int) { pagina = (t, despues, lineasFrente) }

    override func paso(_ dt: Double) {
        tAct += dt
        if var e = ev {
            e.t += dt
            ev = e
            if e.nombre == "prompt" && e.t > 0.9 { ev = nil; setActividad(pendiente ?? "piensa"); pendiente = nil }
            else if e.nombre == "stop" && e.t > 3.8 { ev = nil; setActividad(pendiente ?? "descansa"); pendiente = nil }
            if e.nombre == "stop" && e.t > 1.3 { desorden = max(0.05, desorden - dt * 0.6) }
        }
        if act == "descansa" { tVar += dt; if tVar > (DESCANSOS[variante] ?? 1) { nuevaVariante() } }
        if let p = pagina, t - p.t0 > 1.3 { lineasFrente = p.despues; pagina = nil }
        if act == "hojea" && ev == nil { proxPagina -= dt; if proxPagina <= 0 { pasarPagina(RENGLONES); proxPagina = 3.8 } }
        if act == "mecanismo" {
            rueda += dt * 2.2
            if tAct > 5 {
                humoT -= dt
                if humoT <= 0 {
                    emitir(RUEDA.x + 0.5, RUEDA.y - 2.5, 1, vel: 3, abre: 0.5, vida: 2.6, r: 1.1, roce: 0.55)
                    humoT = 0.45
                }
            }
        }

        let o = objetivo()
        if act == "escribe" && ev == nil && plumaEnMano && pagina == nil && dist(mD.punto, o.D) < 1.6 {
            renglon += dt / 2.6; desorden = min(1, desorden + dt * 0.01)
            if renglon >= Double(RENGLONES) { renglon = 0; pasarPagina(0) }
            lineasFrente = Int(renglon.rounded(.down))
        }
        for k in RAPIDEZ.keys { s[k]?.hacia(o.valor(k), RAPIDEZ[k]! * o.calma, dt) }
        let wm = (act == "escribe" && plumaEnMano ? 12 : 7.5) * o.calma
        func mover(_ m: inout Mano, _ p: Punto) {
            var sx = Muelle(x: m.x, v: m.vx), sy = Muelle(x: m.y, v: m.vy)
            sx.hacia(p.x, wm, dt); sy.hacia(p.y, wm, dt)
            m = Mano(x: sx.x, y: sy.x, vx: sx.v, vy: sy.v)
        }
        mover(&mD, o.D); mover(&mT, o.T)
        if let r = o.recoger, dist(mD.punto, o.D) < 0.9 {
            if r == "pluma" { plumaEnMano.toggle() }
            else { tazaEnMano = r == "taza" }
        }
        pasoV5(dt)

        // Diagnóstico: cuánto le falta a una mano para llegar y si la cabeza entra en la mesa.
        let e = esqueleto(s["incl"]!.x, s["cabeza"]!.x), al = BRAZO[0] + BRAZO[1] + MANO
        falta = max(dist(e.hd, mD.punto) - al, dist(e.ht, mT.punto) - al, 0)
        choque = max(0, e.C.x > CANTO - 3 ? e.C.y + 5.2 - MESA : 0)
    }

    // Postura: espinazo, hombros y cabeza para una inclinación y un cabeceo dados.
    private func esqueleto(_ incl: Double, _ cabeza: Double) -> Esqueleto {
        let a = Punto(x: sin(incl), y: -cos(incl)), n = Punto(x: cos(incl), y: sin(incl))
        var e = Esqueleto(a: a, n: n, top: a, hd: a, ht: a, C: a, cuello: 0)
        e.top = e.L(TORSO, 0)
        e.hd = e.L(TORSO - 1.8, 1.6)
        e.ht = Punto(x: e.hd.x - 1.3, y: e.hd.y - 0.5)
        e.cuello = incl * 0.4 + cabeza * 0.6
        e.C = Punto(x: e.top.x + sin(e.cuello) * 5.4 + n.x * 0.6, y: e.top.y - cos(e.cuello) * 5.4 + n.y * 0.6)
        return e
    }
    // El pecho no puede entrar en el tablero; debajo de él (rodillas, tripa) sí hay sitio.
    private func cabeMesa(_ incl: Double) -> Bool {
        let e = esqueleto(incl, 0)
        return TORSO_FRENTE.prefix(3).allSatisfy { u, w in
            let p = e.L(u, w)
            return p.x < CANTO + 0.5 || p.y < MESA - 0.4 || p.y > MESA + 3
        }
    }
    // Se inclina lo justo para llegar con las dos manos.
    private func inclinar(_ base: Double, _ cabeza: Double, _ D: Punto, _ T: Punto) -> Double {
        let alcance = BRAZO[0] + BRAZO[1] + MANO - 0.4
        var i = base
        while i < 0.9 {
            let e = esqueleto(i, cabeza)
            if dist(e.hd, D) <= alcance && dist(e.ht, T) <= alcance { break }
            if !cabeMesa(i + 0.02) { break }
            i += 0.02
        }
        return i
    }
    private func renglonPunto(_ i: Int, _ f: Double) -> Punto { pt(0.08 + 0.4 * f, -0.82 + Double(i) * 0.125, 0.06) }

    private func objetivo() -> Objetivo {
        let tt = t, ta = tAct
        var o = Objetivo()
        var pluma = false, sujetaTaza = false
        func e0() -> Esqueleto { esqueleto(o.incl, o.cabeza) }
        // En reposo, las manos recogidas delante de la tripa; se calcula al final con la postura ya decidida.
        var D: Punto?, T: Punto?
        switch act {
        case "escribe":
            o.incl = 0.5; o.cabeza = 0.22; o.mirarY = 0.8; o.chispa = 0.95 + 0.22 * sin(tt * 4.2); o.pluma = 1.12
            pluma = true; T = pt(0.32, 0.55, 0.1)
            if pagina != nil { D = bordePagina() }
            else if plumaEnMano {
                let i = Int(renglon.rounded(.down))
                var tip = renglonPunto(i, renglon - Double(i))
                tip.y -= 0.35 * abs(sin(tt * 13))
                D = Punto(x: tip.x - PUNTA * cos(o.pluma), y: tip.y - PUNTA * sin(o.pluma))
            }
        case "hojea":
            o.incl = 0.42; o.cabeza = 0.5; o.mirarY = 0.6
            D = pagina != nil ? bordePagina() : pt(0.3, -1.02, 0.2); T = pt(0.3, 0.7, 0.1)
        case "mecanismo":
            o.incl = 0.45; o.cabeza = 0.6; o.mirarY = 0.8
            D = Punto(x: RUEDA.x + 1.4 * cos(rueda), y: RUEDA.y + 1.4 * sin(rueda)); T = pt(0.12, -0.3, 0.1)
        case "ventana":
            o.incl = 0.02; o.cabeza = -0.12; o.giro = 2.75; o.mirarY = -0.4
        case "ayudante":
            o.incl = 0.22; o.cabeza = -0.05; o.giro = 0.15
            let e = e0(), w = sin(tt * 5.5)
            D = Punto(x: e.hd.x + 14.5 + 0.6 * w, y: e.hd.y - 2.5 + 1.4 * w)
        case "piensa":
            o.incl = 0.1; o.cabeza = -0.32; o.mirarY = -0.9; o.pluma = 1.3
            pluma = true
            if plumaEnMano { let e = e0(); D = Punto(x: e.C.x + 5.2, y: e.C.y + 9.4) }
        case "mano":
            o.incl = 0.12; o.cabeza = -0.18; o.giro = 0.75
            let e = e0(), p = tt.truncatingRemainder(dividingBy: 1.8)
            D = Punto(x: e.hd.x + 3, y: e.hd.y - 15.5)
            o.chispa = 0.8 + 0.7 * (bump(p, 0.18, 0.08) + bump(p, 0.5, 0.08))
        case "descansa":
            o.incl = -0.1; o.cabeza = 0.08; o.cierre = 0.15
            let f = tVar / (DESCANSOS[variante] ?? 1)
            if variante == "te" {
                if f < 0.62 && tazaEnMano {
                    let e = e0(); D = Punto(x: e.C.x + 3.6, y: e.C.y + 4); sujetaTaza = true
                    o.cabeza = -0.05; if f > 0.36 && f < 0.56 { o.cierre = 0.6 }
                } else if f < 0.62 { D = Punto(x: TAZA.x, y: TAZA.y - 1.6); o.recoger = "taza" }
            } else if variante == "estirarse" && f > 0.12 && f < 0.7 {
                o.incl = -0.16; o.cabeza = -0.35; o.cierre = 0.85; o.giro = 0.3
                let e = e0(); D = Punto(x: e.hd.x + 2, y: e.hd.y - 16); T = Punto(x: e.ht.x - 1, y: e.ht.y - 16)
            } else if variante == "ventana" && f > 0.1 && f < 0.85 {
                o.giro = 2.7; o.cabeza = -0.1; o.cierre = 0
            } else if variante == "respirar" {
                o.cierre = 0.5; o.incl += 0.035 * sin(tt * 1.2)
            }
        case "cabecea":
            o.incl = 0.12
            let c = ta.truncatingRemainder(dividingBy: 8.5)
            if c < 6.5 { o.cabeza = 0.05 + 0.85 * suave(c / 6.5); o.cierre = 0.25 + 0.75 * suave(c / 5) }
            else { let k = suave((c - 6.5) / 2); o.cabeza = 0.9 - 0.85 * k; o.cierre = 1 - 0.75 * k }
        case "duerme":
            o.luz = 0.42; o.chispa = 0.5; o.cierre = 1; o.calma = 0.45
            if Int(ta / 15) % 2 == 0 {
                // Sobre el libro: brazos cruzados en el borde de la mesa y la cabeza encima.
                o.incl = 0.56; o.cabeza = 2.5; D = Punto(x: 117.2, y: 82.6); T = Punto(x: 120.2, y: 82.2)
            } else { o.incl = -0.14; o.cabeza = 0.62 }
            o.incl += 0.025 * sin(tt * 0.9)
        default: break
        }
        if let ev, ev.nombre == "prompt" {
            o.incl = 0.15; o.cabeza = -0.42; o.cierre = 0; o.giro = 0.3; o.luz = 1; o.chispa = 1.1; o.mirarY = -0.3
            pluma = true; D = nil; T = nil
        }
        if let ev, ev.nombre == "stop" {
            pluma = false; o.giro = 0.4; o.luz = 1
            if ev.t < 1.3 { o.cabeza = 0.1 + 0.4 * max(0, sin(ev.t / 0.65 * 2 * .pi)) }
            else {
                let golpe = 0.7 * max(0, sin((ev.t - 1.3) * .pi * 2.4))
                o.incl = 0.42; o.cabeza = 0.45; o.mirarY = 0.6
                var d = pt(0.04, -0.6, 0.4), tm = pt(0.04, 0.3, 0.4)
                d.y -= golpe; tm.y -= golpe
                D = d; T = tm
            }
        }
        if contexto >= 0.85 && act != "duerme" {
            // Agobio: además, la cabeza cae despacio y vuelve, y la vela da menos luz.
            o.incl += 0.05; o.cabeza += 0.12 + 0.1 * (0.5 + 0.5 * sin(tt * 0.8)); o.luz = min(o.luz, 0.9)
        }
        o.incl += 0.012 * sin(tt * 1.4)

        // Lo que hay en la mano vuelve a su sitio antes de hacer otra cosa.
        if tazaEnMano && !sujetaTaza { D = Punto(x: TAZA.x, y: TAZA.y - 1.6); o.recoger = "dejarTaza" }
        else if pluma != plumaEnMano && !tazaEnMano { D = BOCA; o.recoger = "pluma" }
        let e = e0()
        o.D = D ?? e.L(10, 7.8)
        o.T = T ?? e.L(10.8, 6.4)
        o.incl = inclinar(o.incl, o.cabeza, o.D, o.T)
        return o
    }

    private func pasoV5(_ dt: Double) {
        if actividad == .cabecea && ev == nil {
            tSub += dt
            if tSub > CABECEOS[subvar] ?? 10 { subvar = subvar == "lee" ? "cabecea" : "lee"; tSub = 0; setActividad(mapa) }
        }
        // La mesa se llena despacio; al compactar (caída de 15 puntos o más), las hojas vuelan.
        if let obj = ctxObj {
            let d = obj - contexto
            if d > 0 { contexto = min(obj, contexto + dt * 0.12) }
            else if d < 0 {
                let antes = Int((contexto * 20).rounded())
                contexto = max(obj, contexto - dt * (d < -0.15 ? 0.5 : 0.12))
                if d < -0.15 {
                    for i in Int((contexto * 20).rounded())..<max(antes, Int((contexto * 20).rounded())) {
                        let h = hojas[min(i, hojas.count - 1)]
                        vuelan.append(Volando(x: PILA + h.dx * 2, y: MESA - 0.6 - 0.55 * Double(i), vx: azar(4, 9), vy: -azar(7, 12),
                                              rot: azar(0, 6), vr: azar(-2.5, 2.5), vida: 0))
                    }
                }
            }
        }
        for i in vuelan.indices {
            vuelan[i].vida += dt; vuelan[i].vy += 9 * dt; vuelan[i].vx *= 0.97
            vuelan[i].x += vuelan[i].vx * dt; vuelan[i].y += vuelan[i].vy * dt; vuelan[i].rot += vuelan[i].vr * dt
        }
        vuelan.removeAll { $0.vida >= 1.1 }
        for i in ayudantes.indices {
            var m = Muelle(x: ayudantes[i].x, v: ayudantes[i].v)
            m.hacia(ayudantes[i].vivo ? 212 + 6 * Double(i) : 250, 1.5, dt)
            ayudantes[i].x = m.x; ayudantes[i].v = m.v; ayudantes[i].paso += abs(m.v) * dt * 0.9
        }
        ayudantes.removeAll { !$0.vivo && $0.x >= 245 }
        // Llega: a los 0,3 s la vela prende y el escribiente aparece. Se va: se funde y la vela suelta humo.
        tVida += dt
        if viva { presencia = tVida < 0.3 ? 0 : min(1, presencia + dt / 0.6) }
        else {
            presencia = max(0, presencia - dt / 0.8)
            if presencia < 0.5 && !humoFin { humoFin = true; emitir(CHISPA.x, CHISPA.y - 1, 3, vel: 2, abre: 0.4, vida: 2.4, r: 0.9, roce: 0.5) }
        }
    }

    private func bordePagina() -> Punto {
        let k = suave(clamp((t - pagina!.t0) / 1.2, 0, 1)), th = Double.pi * k
        return pt(0.3, -1.02 * cos(th), 1.02 * sin(th) + 0.2)
    }

    private func ik(_ S: Punto, _ M: Punto) -> (E: Punto, W: Punto, H: Punto) {
        let l1 = BRAZO[0], l2 = BRAZO[1], dx = M.x - S.x, dy = M.y - S.y, d0 = hypot(dx, dy) == 0 ? 1 : hypot(dx, dy)
        let W = Punto(x: M.x - dx / d0 * MANO, y: M.y - dy / d0 * MANO)
        let d = clamp(hypot(W.x - S.x, W.y - S.y), abs(l1 - l2) + 0.3, l1 + l2 - 1e-3), ang = atan2(W.y - S.y, W.x - S.x)
        let A = acos(clamp((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1))
        let E = Punto(x: S.x + l1 * cos(ang + A), y: S.y + l1 * sin(ang + A))
        let Wr = Punto(x: S.x + d * cos(ang), y: S.y + d * sin(ang))
        let ux = (Wr.x - E.x) / l2, uy = (Wr.y - E.y) / l2
        return (E, Wr, Punto(x: Wr.x + ux * MANO, y: Wr.y + uy * MANO))
    }
}

private struct Esqueleto {
    var a: Punto, n: Punto, top: Punto, hd: Punto, ht: Punto, C: Punto, cuello: Double
    func L(_ u: Double, _ w: Double) -> Punto {
        Punto(x: CADERA.x + a.x * u + n.x * w, y: CADERA.y + a.y * u + n.y * w)
    }
}

private struct Objetivo {
    var incl = 0.18, cabeza = 0.15, giro = 0.0, mirarY = 0.0, cierre = 0.0, chispa = 0.85, luz = 1.0, pluma = 1.2, calma = 1.0
    var D = Punto(x: 0, y: 0), T = Punto(x: 0, y: 0)
    var recoger: String?

    func valor(_ clave: String) -> Double {
        switch clave {
        case "incl": incl
        case "cabeza": cabeza
        case "giro": giro
        case "mirarY": mirarY
        case "cierre": cierre
        case "chispa": chispa
        case "luz": luz
        default: pluma
        }
    }
}

private func ojoLuz(_ l: Lienzo, _ x: Double, _ y: Double, _ w: Double, _ h: Double, frio: Double = 0, cierre: Double = 0, brillo: Double = 1, lado: Double = 1) {
    let b = brillo, corte = clamp(cierre, 0, 1)
    let c = (0..<3).map { (LUZ[$0] + (LUZ_FRIA[$0] - LUZ[$0]) * frio).rounded() }
    func col(_ a: Double) -> Col { Col(c[0], c[1], c[2], a) }
    l.save(); l.translate(x, y)
    l.sumaLuz = true
    l.beginPath(); l.arc(0, 0, w * 2.6)
    l.fill(.radial(0, 0, 0, 0, 0, w * 2.6).parada(0, col(0.4 * b * (1 - corte * 0.6))).parada(1, col(0)))
    if corte > 0.95 {
        l.beginPath(); l.moveTo(-w * 0.9, h * 0.3); l.quadraticCurveTo(0, h * 0.6, w * 0.9, h * 0.3)
        l.ctx.setLineCap(.round); l.stroke(col(0.8 * b), h * 0.4)
        l.restore(); return
    }
    l.sumaLuz = false
    l.beginPath(); l.moveTo(-w, 0); l.quadraticCurveTo(0, -h * 2, w, 0); l.quadraticCurveTo(0, h * 2, -w, 0); l.clip()
    let yl = -h + corte * 2 * h
    l.beginPath(); l.moveTo(-w * 1.05, yl); l.lineTo(w * 1.05, yl); l.lineTo(w * 1.05, h + 1); l.lineTo(-w * 1.05, h + 1); l.closePath(); l.clip()
    l.fillRect(-w - 1, -h - 1, 2 * w + 2, 2 * h + 2, .radial(0, 0, 0, 0, 0, w * 1.05)
        .parada(0, Col(255, 252, 240, b)).parada(0.45, col(b)).parada(1, col(0.5 * b)))
    l.restore()
}

extension Escribiente {
    // Solo el rincón de esta mesa, en sus coordenadas; frioSala es la luz fría que entra por la ventana.
    func pintarRincon(_ l: Lienzo, frioSala: Double) {
        let luz = s["luz"]!.x
        ch = clamp(s["chispa"]!.x, 0, 2) * presencia; brasa = clamp((0.75 - luz) / 0.3, 0, 1)
        calor = ch * (1 - 0.55 * brasa) * luz; frio = frioSala * (0.5 + 0.5 * luz)
        l.save()
        l.ctx.setLineCap(.butt)
        tablon(l); mesa(l); papeles(l); atril(l); objetos(l)
        ayudantesDibujo(l)
        l.save(); l.alfa = presencia; figura(l); l.restore()
        dibujarParticulas(l); hojasVolando(l)
        // Luz cálida desde la chispa.
        l.sumaLuz = true
        l.fillRect(60, NOTCH, 200, ALTO, .radial(CHISPA.x, CHISPA.y, 0, CHISPA.x, CHISPA.y, 70)
            .parada(0, Col(224, 130, 90, 0.13 * calor)).parada(1, Col(224, 130, 90, 0)))
        l.restore()
    }
    // La vela va después del oscurecimiento de la sala.
    func pintarChispa(_ l: Lienzo) { chispa(l, ch, brasa) }

    fileprivate func tablon(_ l: Lienzo) {
        l.fillRect(165, 39, 50, 24, Col("#2b2118"))
        l.fillRect(166.2, 40.2, 47.6, 21.6, Col("#1c1611"))
        let pendiente = Col("#968d7c"), curso = Col("#d8c4a0"), hecha = Col("#6f685c")
        for (i, n) in visibles.enumerated() {
            let x = 168 + Double(i % 3) * 15.6, y = 42 + Double(i / 3) * 10.3, inc = Double((i * 37) % 7 - 3) * 0.02
            let ent = suave((t - n.t0) / 0.35), k = suave((t - n.tCambio) / 0.6), esc = 1.15 - 0.15 * ent
            l.save(); l.translate(x + 6.5, y + 4.2); l.rotate(inc); l.scale(esc, esc); l.alfa = ent
            if n.estado == .curso {
                l.save(); l.sumaLuz = true
                let a = 0.32 * k * (0.85 + 0.15 * sin(t * 1.6))
                l.fillRect(-12, -12, 24, 24, .radial(0, 0, 0, 0, 0, 11).parada(0, Col(240, 160, 100, a)).parada(1, Col(240, 160, 100, 0)))
                l.restore()
            }
            l.fillRect(-6.5, -4.2, 13, 8.4, n.estado == .curso ? pendiente.mezcla(curso, k) : n.estado == .hecha ? curso.mezcla(hecha, k) : pendiente)
            for j in 0..<3 { l.fillRect(-5, -2.2 + Double(j) * 2, j == 2 ? 6 : 9.5, 0.55, Col(30, 26, 22, 0.55)) }
            if n.estado == .hecha { l.fillRect(-5.6, -0.4, 11.2 * suave((t - n.tCambio) / 0.5), 0.75, Col("#2a2420")) }
            l.beginPath(); l.arc(0, -3.3, 0.6); l.fill(Col("#7c6538"))
            l.restore()
        }
    }

    fileprivate func mesa(_ l: Lienzo) {
        let pata = Col("#1e1917")
        l.fillRect(121, MESA, 2.4, SUELO - MESA, pata); l.fillRect(199, MESA, 2.4, SUELO - MESA, pata); l.fillRect(121, 97, 80, 1.2, pata)
        l.fillRect(CANTO, MESA - 0.6, 92, 3.2, .lineal(0, MESA - 0.6, 0, MESA + 2.6).parada(0, Col("#3a2f29")).parada(0.3, Col("#2a221e")).parada(1, Col("#1a1513")))
        l.fillRect(CANTO, MESA - 0.6, 92, 0.5, .lineal(CANTO, 0, 206, 0)
            .parada(0, Col(240, 150, 100, 0)).parada(0.5, Col(240, 150, 100, 0.35 * calor)).parada(1, Col(240, 150, 100, 0.04)))
    }

    fileprivate func papeles(_ l: Lienzo) {
        let n = ctxObj == nil ? 0 : Int((contexto * 20).rounded()), des = 0.3 + desorden * 1.4
        for i in 0..<n {
            let h = hojas[i], y = MESA - 0.6 - 0.55 * Double(i + 1), x = 185 + h.dx * des * 2.4
            l.save(); l.translate(x, y); l.rotate(h.inc * des * 0.06)
            l.fillRect(-7.5, 0, 15, 0.55, Col("#5f5849").mezcla(Col("#8a826f"), h.tono))
            l.restore()
        }
        if n > 0 { l.fillRect(185 - 7.5 + hojas[n - 1].dx * des * 2.4, MESA - 0.6 - 0.55 * Double(n), 15, 0.3, Col(255, 200, 150, 0.25 * calor)) }
        let suelo = ctxObj == nil ? 0 : suave((contexto - 0.85) / 0.06)
        if suelo > 0 {
            for (i, (x, r)) in [(171.0, -0.08), (183, 0.05), (196, -0.03), (210, 0.09)].enumerated() {
                l.save(); l.alfa = suelo; l.translate(x, SUELO - 0.3); l.rotate(r)
                l.fillRect(-6, -0.7, 12, 0.7, Col(i % 2 == 1 ? "#8a826f" : "#766e5d")); l.restore()
            }
        }
    }

    fileprivate func atril(_ l: Lienzo) {
        let f0 = pt(-0.08, -1.08), f1 = pt(1.05, -1.08), b1 = pt(1.05, 1.08), b0 = pt(-0.08, 1.08)
        // Costado que da al que mira, con la rueda de latón.
        poli(l, [f0, f1, Punto(x: f1.x + 1.5, y: MESA - 0.6), Punto(x: f0.x + 0.6, y: MESA - 0.6)]); l.fill(Col("#221c19"))
        poli(l, [f0, f1, b1, b0]); l.fill(Col("#2c2420"))
        l.beginPath(); l.moveTo(f1.x, f1.y); l.lineTo(b1.x, b1.y); l.stroke(Col(240, 150, 100, 0.4 * calor), 0.35)
        poli(l, [f0, f1, Punto(x: f1.x, y: f1.y + 0.7), Punto(x: f0.x, y: f0.y + 0.7)]); l.fill(Col("#16120f"))
        // Rueda.
        l.save(); l.translate(RUEDA.x, RUEDA.y)
        l.beginPath(); l.arc(0, 0, 2); l.fill(Col("#5d4a28"))
        let latón = Col("#a58a4c")
        l.beginPath(); l.arc(0, 0, 1.8); l.stroke(latón, 0.35)
        for i in 0..<4 {
            let a = rueda + Double(i) * .pi / 2
            l.beginPath(); l.moveTo(0, 0); l.lineTo(cos(a) * 1.8, sin(a) * 1.8); l.stroke(latón, 0.35)
        }
        l.beginPath(); l.arc(cos(rueda) * 1.4, sin(rueda) * 1.4, 0.45); l.fill(Col("#c4a560"))
        l.restore()
        libro(l)
    }

    fileprivate func libro(_ l: Lienzo) {
        let S0 = 0.02, S1 = 0.56
        poli(l, [pt(S0 - 0.03, -1.0, -0.05), pt(S1 + 0.03, -1.0, -0.05), pt(S1 + 0.03, 1.0, -0.05), pt(S0 - 0.03, 1.0, -0.05)]); l.fill(Col("#4a2420"))
        let papel = Col("#5d564a").mezcla(Col("#c4b597"), clamp(0.35 + 0.65 * calor, 0, 1))
        func hoja(_ v0: Double, _ v1: Double, _ h0: Double, _ h1: Double, _ lineas: Int, _ parcial: Double, _ sombra: Double) {
            poli(l, [pt(S0, v0, h0), pt(S1, v0, h0), pt(S1, v1, h1), pt(S0, v1, h1)]); l.fill(papel)
            if sombra > 0 { l.fill(Col(0, 0, 0, sombra)) }
            l.ctx.setLineCap(.round)
            let total = lineas + (parcial > 0 ? 1 : 0)
            l.beginPath()
            for i in 0..<max(0, total) {
                let f = i < lineas ? 1.0 : parcial, k = -0.82 + Double(i) * 0.125, v = v0 + (v1 - v0) * (k + 1), h = h0 + (h1 - h0) * (k + 1)
                var j = 0
                while Double(j) <= 14 * f {
                    let p = pt(0.08 + 0.4 * (Double(j) / 14), v, h + 0.04 * sin(Double(j) * 2.3 + Double(i)))
                    if j > 0 { l.lineTo(p.x, p.y) } else { l.moveTo(p.x, p.y) }
                    j += 1
                }
            }
            l.stroke(Col(40, 32, 26, 0.75), 0.3)
        }
        let enCurso = act == "escribe" && pagina == nil ? renglon - renglon.rounded(.down) : 0
        hoja(0, 1, 0, 0, RENGLONES, 0, 0.12)
        hoja(-1, 0, 0, 0, pagina?.despues ?? lineasFrente, pagina != nil ? 0 : enCurso, 0)
        if let p = pagina {
            // La hoja gira sobre el lomo: de la cara de delante a la de atrás.
            let k = suave(clamp((t - p.t0) / 1.2, 0, 1)), th = Double.pi * k
            hoja(0, -cos(th), 0, sin(th), p.antes, 0, 0.25 * sin(th))
        }
        let l0 = pt(S0, 0), l1 = pt(S1, 0)
        l.beginPath(); l.moveTo(l0.x, l0.y); l.lineTo(l1.x, l1.y); l.stroke(Col(20, 14, 10, 0.6), 0.35)
    }

    fileprivate func objetos(_ l: Lienzo) {
        // Candelero.
        let latón = Col("#574628")
        l.beginPath(); l.ellipse(CHISPA.x, MESA - 0.8, 2.6, 0.7); l.fill(latón)
        l.fillRect(CHISPA.x - 0.5, 73, 1, MESA - 73.5, latón); l.fillRect(CHISPA.x - 2.2, 72.4, 4.4, 0.9, latón)
        l.fillRect(CHISPA.x - 2.2, 72.4, 4.4, 0.3, Col(255, 190, 130, 0.55 * calor))
        // Tintero, con la pluma si no está en la mano.
        let tinta = Col("#272b35")
        l.beginPath(); l.roundRect(TINTERO.x - 1.7, TINTERO.y - 2, 3.4, 2.6, 0.7); l.fill(tinta)
        l.fillRect(TINTERO.x - 0.9, TINTERO.y - 2.6, 1.8, 0.8, tinta)
        l.fillRect(TINTERO.x + 1.1, TINTERO.y - 1.7, 0.4, 2, Col(255, 190, 140, 0.4 * calor))
        if !plumaEnMano { pluma(l, Punto(x: TINTERO.x + 0.3, y: TINTERO.y - 1.2), 1.2, 0) }
        if !tazaEnMano { taza(l, TAZA.x, TAZA.y) }
    }
    // Pluma: punta en p, el resto se va en sentido contrario a ang.
    fileprivate func pluma(_ l: Lienzo, _ p: Punto, _ ang: Double, _ punta: Double = PUNTA) {
        let c = cos(ang), s = sin(ang), a = Punto(x: p.x + c * punta, y: p.y + s * punta), b = Punto(x: p.x - c * 6.2, y: p.y - s * 6.2)
        l.beginPath(); l.moveTo(a.x, a.y); l.lineTo(b.x, b.y); l.stroke(Col("#8f8676"), 0.3)
        let m = Punto(x: p.x - c * 3.6, y: p.y - s * 3.6)
        l.beginPath(); l.moveTo(p.x - c * 1.2, p.y - s * 1.2)
        l.quadraticCurveTo(m.x - s * 1.3, m.y + c * 1.3, b.x, b.y); l.quadraticCurveTo(m.x + s * 0.4, m.y - c * 0.4, p.x - c * 1.2, p.y - s * 1.2)
        l.fill(Col("#b8b0a2"))
    }
    fileprivate func taza(_ l: Lienzo, _ x: Double, _ y: Double) {
        let loza = Col("#3d4250")
        l.beginPath(); l.roundRect(x - 1.3, y - 2.2, 2.6, 2.2, 0.5); l.fill(loza)
        l.beginPath(); l.arc(x - 1.5, y - 1.2, 0.6, .pi * 0.5, .pi * 1.5); l.stroke(loza, 0.45)
        l.fillRect(x + 1, y - 2.1, 0.3, 1.9, Col(255, 190, 140, 0.45 * calor))
    }

    fileprivate func hojasVolando(_ l: Lienzo) {
        for h in vuelan {
            l.save(); l.translate(h.x, h.y); l.rotate(h.rot); l.alfa = 1 - suave((h.vida - 0.6) / 0.5)
            l.fillRect(-1.6, -0.3, 3.2, 0.6, Col("#8a826f")); l.restore()
        }
    }

    fileprivate func chispa(_ l: Lienzo, _ k: Double, _ brasa: Double) {
        let x = CHISPA.x, y = CHISPA.y, esc = (0.7 + 0.3 * k) * (1 - 0.45 * brasa)
        l.save(); l.sumaLuz = true
        func halo(_ r: Double, _ a: Double) {
            l.beginPath(); l.arc(x, y, r)
            l.fill(.radial(x, y, 0, x, y, r).parada(0, Col(240, 150, 100, a)).parada(1, Col(240, 150, 100, 0)))
        }
        halo(26 * esc, 0.16 * k * (1 - 0.5 * brasa)); halo(7 * esc, 0.45 * k)
        l.restore()
        let col = CORAL.mezcla(Col("#a5401f"), brasa)
        l.save(); l.translate(x, y); l.rotate(0.12)
        l.ctx.setLineCap(.round)
        l.ctx.setShadow(offset: .zero, blur: 2.2 * u * k, color: col.cg)
        l.beginPath()
        for i in 0..<11 {
            let a = Double(i) / 11 * PI2, largo = (1.75 + 0.55 * Double((i * 7) % 5) / 4) * esc
            l.moveTo(cos(a) * 0.5 * esc, sin(a) * 0.5 * esc); l.lineTo(cos(a) * largo, sin(a) * largo)
        }
        l.stroke(col, 0.62)
        l.restore()
    }

    // Hasta tres, en fila hacia el fondo: cada uno un poco más pequeño y más tenue.
    fileprivate func ayudantesDibujo(_ l: Lienzo) {
        for (i, a) in ayudantes.enumerated().reversed() {
            let k = 1 - 0.08 * Double(i)
            l.save(); l.translate(a.x, SUELO); l.scale(k, k); l.translate(-a.x, -SUELO); l.alfa = 1 - 0.25 * Double(i)
            ayudanteDibujo(l, a.x, a.paso)
            l.restore()
        }
    }

    fileprivate func ayudanteDibujo(_ l: Lienzo, _ ax: Double, _ paso: Double) {
        let bob = -0.5 * abs(sin(paso * 6)), y = SUELO + bob
        l.save(); l.translate(ax, y)
        let g = Degradado.lineal(0, -20, 0, 0).parada(0, Col("#4a5468")).parada(1, Col("#262c39"))
        l.beginPath(); l.moveTo(-4.4, 0); l.quadraticCurveTo(-3.8, -8, -2.9, -13.5); l.lineTo(2.9, -13.5); l.quadraticCurveTo(3.8, -8, 4.4, 0); l.closePath(); l.fill(g)
        l.contraluz(-6, -8, 2, -6, Col(240, 150, 100, 0.6 * calor), 0.9, 1.6 * u)
        // Capucha con la punta hacia atrás (mira a la izquierda).
        l.beginPath(); l.moveTo(1.6, -18.4); l.quadraticCurveTo(5.2, -16, 5.6, -11.4); l.quadraticCurveTo(3.4, -12.8, 1.6, -13.4); l.closePath(); l.fill(g)
        l.beginPath(); l.ellipse(0.2, -16.6, 3.4, 3.6); l.fill(g)
        l.contraluz(-4, -18, 2, -15, Col(240, 150, 100, 0.6 * calor), 0.8, 1.4 * u)
        l.beginPath(); l.ellipse(-1.8, -16.2, 1.5, 2.4); l.fill(Col("#06070a"))
        ojoLuz(l, -2.3, -16.6, 0.55, 0.36, frio: 0.85, cierre: max(s["cierre"]!.x * 0.5, parpadeando()), brillo: s["luz"]!.x)
        // Libro en brazos.
        l.fillRect(-4.8, -11.6, 3.4, 4.6, Col("#4a2420"))
        l.fillRect(-4.8, -11.6, 0.5, 4.6, Col("#8f8572"))
        l.beginPath(); l.arc(-1.6, -9, 0.8); l.fill(PIEL)
        l.restore()
    }

    // Manga de dos piezas con la boca en campana y la mano saliendo de ella.
    @discardableResult
    fileprivate func brazo(_ l: Lienzo, _ S: Punto, _ M: Punto, _ detras: Bool) -> Punto {
        let (E, W, H) = ik(S, M)
        let ux = (W.x - E.x) / BRAZO[1], uy = (W.y - E.y) / BRAZO[1], px = -uy, py = ux
        let c = Col(detras ? "#232835" : "#343c4f")
        l.save()
        l.ctx.setLineCap(.round); l.ctx.setLineJoin(.round)
        l.beginPath(); l.moveTo(S.x, S.y); l.lineTo(E.x, E.y); l.lineTo(E.x + ux * 2, E.y + uy * 2); l.stroke(c, 3.6)
        poli(l, [Punto(x: E.x + px * 1.8 + ux * 1.5, y: E.y + py * 1.8 + uy * 1.5), Punto(x: W.x + px * 2.4, y: W.y + py * 2.4),
                 Punto(x: W.x - px * 2.4, y: W.y - py * 2.4), Punto(x: E.x - px * 1.8 + ux * 1.5, y: E.y - py * 1.8 + uy * 1.5)])
        l.fill(c); if !detras { bordes(l, E) }
        l.beginPath(); l.ellipse(W.x, W.y, 0.7, 2.2, atan2(uy, ux)); l.fill(Col("#0f1218"))
        l.beginPath(); l.ellipse(H.x - ux * 0.2, H.y - uy * 0.2, 1.25, 0.95, atan2(uy, ux))
        l.fill(detras ? PIEL.mezcla(Col("#2a2a30"), 0.45) : PIEL)
        if !detras { l.contraluz(H.x + 2, H.y - 1, H.x - 1, H.y + 1, Col(255, 180, 130, 0.7 * calor), 0.6, 1 * u) }
        l.restore()
        return H
    }
    // Contraluz cálida desde la chispa y fría desde la ventana sobre el trazado actual.
    fileprivate func bordes(_ l: Lienzo, _ c: Punto, _ k: Double = 1) {
        l.contraluz(c.x + 9, c.y - 3, c.x - 2, c.y + 1, Col(240, 150, 100, 0.6 * calor * k), 0.55, 0.7 * u)
        l.contraluz(c.x - 9, c.y - 6, c.x + 1, c.y + 2, Col(165, 200, 255, 0.4 * frio * k), 0.5, 0.6 * u)
    }

    fileprivate func figura(_ l: Lienzo) {
        let e = esqueleto(s["incl"]!.x, s["cabeza"]!.x)
        // Taburete.
        l.beginPath(); l.moveTo(95, 98.5); l.lineTo(93.6, SUELO); l.moveTo(107, 98.5); l.lineTo(108.4, SUELO); l.moveTo(94.2, 101.6); l.lineTo(107.8, 101.6)
        l.stroke(Col("#1f1a19"), 1.1)
        l.fillRect(92.5, 97, 16.5, 1.7, Col("#2a2220"))
        brazo(l, e.ht, mT.punto, true)
        // Faldón: muslo bajo la mesa y caída hasta el suelo.
        let g = Degradado.lineal(0, 62, 0, SUELO).parada(0, HABITO[0]).parada(1, HABITO[1])
        l.beginPath(); l.moveTo(95.5, 97.6); l.quadraticCurveTo(95.5, 91.5, 102, 90.6); l.lineTo(113, 90.2)
        l.quadraticCurveTo(118.2, 89.9, 118.8, 93); l.quadraticCurveTo(119.6, 99, 120.4, SUELO - 0.3); l.lineTo(107.8, SUELO - 0.3)
        l.quadraticCurveTo(106.3, 100.5, 104.6, 98.4); l.lineTo(95.5, 98.4); l.closePath(); l.fill(g)
        bordes(l, Punto(x: 110, y: 95))
        l.beginPath(); l.ellipse(121, SUELO - 0.5, 2.2, 0.8); l.fill(Col("#0d0f14"))
        // Torso.
        l.beginPath()
        let pts = (TORSO_ESPALDA + TORSO_FRENTE).map { e.L($0.0, $0.1) }
        l.moveTo(pts[0].x, pts[0].y)
        for i in 1..<(pts.count - 1) {
            l.quadraticCurveTo(pts[i].x, pts[i].y, (pts[i].x + pts[i + 1].x) / 2, (pts[i].y + pts[i + 1].y) / 2)
        }
        l.lineTo(pts[pts.count - 1].x, pts[pts.count - 1].y); l.closePath(); l.fill(g)
        bordes(l, e.L(14, 0))
        // Cordón dorado con borla.
        let c0 = e.L(6.5, -7.1), c1 = e.L(6.5, 7.2)
        l.beginPath(); l.moveTo(c0.x, c0.y); l.lineTo(c1.x, c1.y); l.moveTo(c1.x - 0.2, c1.y); l.quadraticCurveTo(c1.x + 0.6, c1.y + 3, c1.x + 0.2, c1.y + 5.2)
        l.ctx.setLineCap(.round); l.stroke(Col("#b8923e"), 0.6)
        l.beginPath(); l.arc(c1.x + 0.2, c1.y + 5.4, 0.45); l.fill(Col("#d8b263"))
        cabezaDibujo(l, e)
        let H = brazo(l, e.hd, mD.punto, false)
        if plumaEnMano { pluma(l, H, s["pluma"]!.x) }
        if tazaEnMano { taza(l, H.x + 0.9, H.y + 1) }
    }

    fileprivate func cabezaDibujo(_ l: Lienzo, _ e: Esqueleto) {
        let giro = s["giro"]!.x, k = cos(giro), rot = e.cuello * 0.75 * k
        let g = Degradado.lineal(0, e.C.y - 7, 0, e.C.y + 8).parada(0, Col("#414b60")).parada(1, Col("#262c39"))
        // Punta de la capucha: sale de la nuca y cuelga hacia atrás aunque la cabeza se incline; de frente queda escondida.
        func giraP(_ x: Double, _ y: Double) -> Punto { Punto(x: e.C.x + x * cos(rot) - y * sin(rot), y: e.C.y + x * sin(rot) + y * cos(rot)) }
        let a0 = giraP(-2.6 * k, -4.2), a1 = giraP(-1.2 * k, 5.2), nuca = giraP(-5.6 * k, -0.4)
        let punta = Punto(x: nuca.x - 4.4 * k, y: max(nuca.y + 6.4, a1.y + 1.2))
        l.beginPath(); l.moveTo(a0.x, a0.y); l.quadraticCurveTo(nuca.x - 2.4 * k, nuca.y + 0.6, punta.x, punta.y)
        l.quadraticCurveTo((punta.x + a1.x) / 2, a1.y - 0.4, a1.x, a1.y); l.closePath(); l.fill(g)
        l.save(); l.translate(e.C.x, e.C.y); l.rotate(rot)
        l.beginPath(); l.ellipse(0.2 * k, 5, 6, 2.6); l.fill(g)
        l.beginPath(); l.ellipse(-0.3 * k, -0.2, 5.3, 5.6); l.fill(g)
        bordes(l, Punto(x: 0, y: 0))
        // Cara en sombra.
        let fx = 2.9 * k, rx = 2.2 + 1.2 * (1 - abs(k))
        l.beginPath(); l.ellipse(fx, 0.8, rx, 3.6); l.fill(Col("#06070a"))
        let cierre = max(s["cierre"]!.x, parpadeando())
        for lado in [1.0, -1.0] {
            let az = giro + lado * 0.6, z = sin(az); if z < -0.08 { continue }
            let ex = 3.7 * cos(az), ey = 0.4 + s["mirarY"]!.x * 0.7 + e.cuello * 0.9 * (1 - abs(k))
            ojoLuz(l, ex, ey, 0.72 * (0.45 + 0.55 * clamp(z, 0, 1)), 0.42, frio: 0.85, cierre: cierre, brillo: pow(s["luz"]!.x, 0.7), lado: cos(az) < 0 ? -1 : 1)
        }
        l.restore()
    }
}
