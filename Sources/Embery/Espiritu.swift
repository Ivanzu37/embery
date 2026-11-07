import Foundation

// Lumen fuera del panel: un espíritu de luz que se posa en las cosas del escritorio y cambia de sitio de vez en cuando.
// Port de espiritu.js. Vive en coordenadas del escritorio (puntos, y hacia abajo).

struct Posadero {
    let clave: String
    var escala = 1.0
    var libre = false
    let pos: () -> Punto
}

// Segundos posado antes de cambiar de sitio, según el momento. Dormido no se mueve.
private let RITMO: [Estado: ClosedRange<Double>] = [.foco: 480...720, .descanso: 15...35, .reposo: 60...180, .triste: 60...180, .fin: 60...180]
private let CERCA = 110.0, APARTA = 80.0, AGARRE = 22.0, R = 0.55, ESTELA = 0.5
private func dist(_ a: Punto, _ b: Punto) -> Double { hypot(a.x - b.x, a.y - b.y) }

final class Espiritu: Mascota {
    // Ojos completos y neutros; solo dormido los cierra.
    override class var extra: [Estado: Params] {[
        .reposo: ["cierre": 0, "brillo": 0.8, "deriva": 1], .foco: ["cierre": 0, "brillo": 0.7, "deriva": 0.6], .descanso: ["cierre": 0, "brillo": 0.9, "deriva": 1.2],
        .triste: ["cierre": 0, "brillo": 0.45, "deriva": 0.8], .fin: ["cierre": 0, "brillo": 1.1, "deriva": 1], .dormido: ["cierre": 1, "brillo": 0.35, "deriva": 0.35],
    ]}
    struct Vuelo { let dest: Posadero; let t0, T, D, vmax, anticipa, lado, ruido: Double; var alLlegar: (() -> Void)? }
    struct Mota { var x, y, vx, vy, vida, max, r: Double }

    var posaderos: () -> [Posadero] = { [] }
    var reducir: () -> Bool = { false }
    var avisoEn = Punto(x: 0, y: 40)
    var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0, fv = Punto(x: 0, y: 0), gota = 0.0, ang = 0.0, escala = 1.0
    var activo = false, fundiendo = false, arrastrado = false, prisa = false
    var vuelo: Vuelo?
    var posado: Posadero?
    var espera = 0.0, revision = 0.0
    var cursor: (x: Double, y: Double, t: Double)?
    var cursorV = 0.0, roce = 0.0, ultimaHuida = -10.0
    var rastro: [(x: Double, y: Double, t: Double)] = []
    var motas: [Mota] = []
    var proximaMota = 0.0, proximoMicro = azar(20, 60), dobleEn = 0.0, ladoMirada = 1.0, vistazoEn = 0.0
    let semilla = Double.random(in: 0..<100)
    private var objetivo = Punto(x: 0, y: 0)

    private func conVida(_ e: Estado) -> Bool { e != .foco && e != .dormido && !reducir() }

    // Lienzo de 260 px para que el halo, que al nacer crece mucho, no se corte (u ≈ 24,6 px).
    override func redimensionar(_ w: Double, _ h: Double) { super.redimensionar(w, h); u = w / 10.56; ox = w / 2; oy = h / 2 }
    override func cabeza() -> Punto { Punto(x: 0, y: 0) }
    override func mirar(_ x: Double, _ y: Double) {}

    func moverCursor(_ cx: Double, _ cy: Double, ahora: Double) {
        if let c = cursor { cursorV = hypot(cx - c.x, cy - c.y) / max(0.001, ahora - c.t) }
        cursor = (cx, cy, ahora)
    }
    func bajoCursor(_ px: Double, _ py: Double) -> Bool { activo && !fundiendo && hypot(px - x, py - y) < AGARRE * escala }
    func tocar() { parpadeo = 1; aplastaV += 4; hacer("pulso", 0.9) }
    func evento(_ nombre: String) {
        // Mira hacia el aviso de bloqueo, arriba en el centro, y luego te mira entornando los ojos.
        if nombre == "bloqueo" { objetivo = avisoEn; hacer("bloqueo", 3) } else if nombre == "despertar" { parpadeo = 1 }
    }
    override func alEntrar(_ e: Estado, _ antes: Estado) { if e == .fin { hacer("pulso", 1.2) }; esperar() }
    func esperar() { if let r = RITMO[estado], !reducir() { espera = azar(r.lowerBound, r.upperBound) } else { espera = .infinity } }

    // Sale del panel: nace como una luz grande donde estaba el búho, se recoge en la esfera y vuela a un posadero.
    func salir(_ q: Punto) {
        activo = true; fundiendo = false; vuelo = nil; x = q.x; y = q.y; espera = 1.1; fv = Punto(x: 0, y: 0)
        posado = Posadero(clave: "panel", libre: true) { q }
        hacer("nace", 1)
    }
    // Vuelve al panel: vuela hasta donde aparecerá el búho y se abre en luz.
    func volver(_ q: Punto) {
        guard activo else { return }
        arrastrado = false
        if reducir() { hacer("funde", 0.45); fundiendo = true; return }
        volar(Posadero(clave: "panel", libre: true) { q }, 0.5)
        vuelo?.alLlegar = { [weak self] in self?.hacer("funde", 0.45); self?.fundiendo = true }
    }
    // Recoge la gota de la rama al terminar una sesión: se queda donde la atrapa y su luz da un pulso.
    // vistazo: lado de la pestaña (1 derecha, −1 izquierda); 0,6 s después mira hacia allí 2,6 s.
    func recoger(vistazo: Double? = nil) {
        let q = Punto(x: x, y: y)
        vuelo = nil; fv = Punto(x: 0, y: 0); posado = Posadero(clave: "gota", libre: true) { q }
        esperar(); parpadeo = 1; aplastaV += 4; hacer("pulso", 1.2)
        if let v = vistazo, !reducir() { ladoMirada = v; vistazoEn = t + 0.6 }
    }
    func agarrar() { arrastrado = true; vuelo = nil; posado = nil }
    func soltar() {
        let q = Punto(x: x, y: y)
        arrastrado = false; posado = Posadero(clave: "suelto", libre: true) { q }; aplastaV += 3; esperar()
        fv = Punto(x: 0, y: 0); ultimaHuida = t  // recién soltado no huye del cursor que lo ha dejado ahí
    }
    // T: duración aproximada. Los vuelos tranquilos empiezan mirando al destino y hundiéndose un poco (anticipación).
    func volar(_ dest: Posadero, _ T: Double = azar(2.6, 3.4)) {
        let d = dest.pos()
        if reducir() { x = d.x; y = d.y; vuelo = nil; posado = dest; fv = Punto(x: 0, y: 0); vx = 0; vy = 0; esperar(); return }
        let D = max(1, dist(Punto(x: x, y: y), d))
        vuelo = Vuelo(dest: dest, t0: t, T: T, D: D, vmax: clamp(D / (T * 0.55), 30, 2500), anticipa: T >= 2.5 ? 0.4 : 0,
                      lado: Double.random(in: 0..<100), ruido: estado == .descanso ? 1.6 : 1)
        if gesto?.nombre == "mirada" || gesto?.nombre == "acomoda" { gesto = nil }
        posado = nil
    }
    // Uno de los tres posaderos más cercanos, lejos del cursor.
    func elegir() -> Posadero? {
        let aqui = Punto(x: x, y: y)
        var libres = posaderos().filter { p in p.clave != posado?.clave && (cursor == nil || dist(p.pos(), Punto(x: cursor!.x, y: cursor!.y)) > 160) }
        libres.sort { dist($0.pos(), aqui) < dist($1.pos(), aqui) }
        return libres.isEmpty ? nil : libres[Int.random(in: 0..<min(3, libres.count))]
    }
    private func mota(_ x: Double, _ y: Double, _ vx: Double, _ vy: Double, _ vida: Double) { motas.append(Mota(x: x, y: y, vx: vx, vy: vy, vida: 0, max: vida, r: azar(1.1, 2.1))) }

    // Vuelo con física: el destino lo atrae con un muelle amortiguado (se pasa un poco y se asienta) y un ruido lo desvía de lado.
    private func volando(_ dt: Double) {
        guard let v = vuelo else { return }
        let edad = t - v.t0, d = v.dest.pos(), dx = d.x - x, dy = d.y - y, dd = max(hypot(dx, dy), 1e-9)
        if edad < v.anticipa { miradaObj = Punto(x: clamp(dx / dd, -0.8, 0.8), y: clamp(dy / dd, -0.6, 0.6)); return }
        // El desvío lateral es máximo a mitad de camino y nulo al salir y al llegar; si no, se queda rondando el destino.
        let ux = dx / dd, uy = dy / dd, mitad = sin(.pi * clamp(1 - dd / v.D, 0, 1))
        let lateral = ruido(t * 2.2, v.lado) * min(v.vmax, 300) * 0.22 * v.ruido * mitad
        // Atracción y respuesta escalan con la duración: el amortiguamiento queda igual en vuelos lentos y rápidos.
        let des = min(v.vmax, dd * 4.8 / v.T), resp = 9 / v.T
        let ax = (ux * des - uy * lateral - fv.x) * resp, ay = (uy * des + ux * lateral - fv.y) * resp
        fv.x += ax * dt; fv.y += ay * dt
        x += fv.x * dt; y = max(8, y + fv.y * dt)
        let rapido = hypot(fv.x, fv.y)
        if (dd < 3 && rapido < 25) || edad > v.T * 3 {
            x = d.x; y = d.y; vuelo = nil; posado = v.dest; fv = Punto(x: 0, y: 0)
            aplastaV += 2.5; esperar(); v.alLlegar?()
            // Al llegar echa un vistazo alrededor.
            if v.alLlegar == nil && gesto == nil && conVida(estado) && Double.random(in: 0..<1) < 0.6 { ladoMirada = Bool.random() ? -1 : 1; hacer("mirada", 1.8) }
        }
    }
    // Microgestos esporádicos, solo fuera del foco y despierto.
    private func micro() {
        switch Int.random(in: 0..<4) {
        case 0: ladoMirada = Bool.random() ? -1 : 1; hacer("mirada", 2.6)
        case 1: parpadeo = 1; dobleEn = t + 0.3
        case 2: hacer("acomoda", 0.9)
        default: mota(x + azar(-4, 4), y - 10, azar(-3, 3), -14, 2.2)
        }
    }

    override func paso(_ dt: Double) {
        if fundiendo && fase("funde") < 0 { activo = false; fundiendo = false }
        if !activo { rastro.removeAll(); motas.removeAll(); return }
        let px = x, py = y
        if vuelo != nil { volando(dt) }
        else if !arrastrado, let pos = posado {
            let q = pos.pos(); x = q.x; y = q.y
            // Si su sitio deja de estar libre (esa ventana pasa a ser la activa), se va.
            revision -= dt
            if revision <= 0 {
                revision = 0.5
                if !pos.libre && !posaderos().contains(where: { $0.clave == pos.clave }) { espera = 0; prisa = true }
            }
            espera -= dt
            if espera <= 0 { if let p = elegir() { volar(p, prisa ? 2 : azar(2.6, 3.4)) } else { esperar() }; prisa = false }
            if conVida(estado) && gesto == nil { proximoMicro -= dt; if proximoMicro <= 0 { micro(); proximoMicro = azar(20, 60) } }
        }
        if dobleEn > 0 && t >= dobleEn { parpadeo = 1; dobleEn = 0 }
        if vistazoEn > 0 && t >= vistazoEn && !arrastrado && vuelo == nil { vistazoEn = 0; hacer("mirada", 2.6) }

        // Cerca del cursor te mira; si el cursor le roza trabajando, se aparta.
        let aqui = Punto(x: x, y: y)
        let dc = cursor.map { dist(Punto(x: $0.x, y: $0.y), aqui) } ?? .infinity
        let moviendo = cursor.map { ProcessInfo.processInfo.systemUptime - $0.t < 0.15 } ?? false && cursorV > 250
        let cerca = dc < CERCA && vuelo == nil && estado != .dormido
        raton = cerca ? Punto(x: (cursor!.x - x) / u, y: (cursor!.y - y) / u) : nil
        if cerca { ultimoRaton = t }
        roce = dc < APARTA && moviendo && !arrastrado ? roce + dt : max(0, roce - dt * 2)
        if roce > 0.35 && vuelo == nil && !reducir() && t - ultimaHuida > 4 {
            if let p = elegir() { volar(p, 1.6); ultimaHuida = t; roce = 0 }
        }
        let bl = fase("bloqueo"), mi = fase("mirada")
        if bl >= 0 { mirarA = bl < 0.4 ? Punto(x: (objetivo.x - x) / u, y: (objetivo.y - y) / u) : nil }
        else if mi >= 0 { mirarA = mi < 0.75 ? Punto(x: ladoMirada * 3, y: -0.4) : nil }
        // Sin motivo para mirar a ningún sitio, mira al frente: nada de miradas al azar.
        proximaMirada = .infinity
        if let v = vuelo, t - v.t0 >= v.anticipa { miradaObj = Punto(x: clamp(vx / 300, -0.7, 0.7), y: clamp(vy / 300, -0.5, 0.5)) }
        else if vuelo == nil && !cerca && mirarA == nil { miradaObj = Punto(x: 0, y: 0) }

        // Sin movimiento, un cambio de sitio directo no debe leerse como velocidad (ni estirar la gota ni dejar estela).
        let mueve: Double = reducir() && !arrastrado ? 0 : 1
        vx = lerp(vx, mueve * (x - px) / max(dt, 1e-3), ease(dt, 0.001))
        vy = lerp(vy, mueve * (y - py) / max(dt, 1e-3), ease(dt, 0.001))
        let vel = hypot(vx, vy)
        if vel > 5 { ang = atan2(vy, vx) }
        // Gota: solo la parte de atrás se alarga; un 7 % en un vuelo tranquilo, como mucho un 11 %.
        gota = lerp(gota, clamp(vel / 150, 0, 1) * 0.11, ease(dt, 0.03))
        escala = lerp(escala, vuelo != nil ? 1 : posado?.escala ?? 1, ease(dt, 0.05))

        // Estela: rastro corto mientras se mueve y alguna mota que se desprende por detrás.
        if vel > 25 {
            rastro.append((x, y, t))
            proximaMota -= dt
            if proximaMota <= 0 {
                let bx = -cos(ang), by = -sin(ang), rr = R * u * escala
                mota(x + bx * rr, y + by * rr, bx * azar(8, 24) + azar(-12, 12), by * azar(8, 24) + azar(-12, 12) - 6, azar(0.7, 1.4))
                proximaMota = azar(0.3, 0.65)
            }
        }
        while let q = rastro.first, t - q.t > ESTELA { rastro.removeFirst() }
        for i in motas.indices {
            motas[i].vida += dt; motas[i].x += motas[i].vx * dt; motas[i].y += motas[i].vy * dt
            motas[i].vx *= pow(0.4, dt); motas[i].vy = motas[i].vy * pow(0.5, dt) - 4 * dt
        }
        motas.removeAll { $0.vida >= $0.max }
    }

    // Estela y motas, en coordenadas del escritorio.
    func dibujarEstela(_ l: Lienzo) {
        guard activo else { return }
        l.save(); l.sumaLuz = true
        let rr = R * u * escala, b = p["brillo"] ?? 1, c = Col(215, 230, 255)
        for q in rastro {
            let k = 1 - (t - q.t) / ESTELA, r = rr * (0.35 + 0.65 * k)
            l.beginPath(); l.arc(q.x, q.y, r)
            l.fill(.radial(q.x, q.y, 0, q.x, q.y, r).parada(0, c.alfa(0.13 * pow(k, 1.5) * b)).parada(0.6, c.alfa(0.04 * k * b)).parada(1, c.alfa(0)))
        }
        for m in motas {
            let f = m.vida / m.max, a = min(1, m.vida * 6) * (1 - f) * b
            l.beginPath(); l.arc(m.x, m.y, m.r * 3)
            l.fill(.radial(m.x, m.y, 0, m.x, m.y, m.r * 3).parada(0, Col(240, 246, 255, 0.9 * a)).parada(0.35, Col(200, 220, 255, 0.35 * a)).parada(1, Col(200, 220, 255, 0)))
        }
        l.restore()
    }

    // El párpado se pinta con el degradado de la esfera para que no se note como un parche.
    private func ojo(_ l: Lienzo, _ x: Double, _ y: Double, _ cierre: Double, _ piel: Degradado) {
        let rx = 0.075, ry = 0.1
        l.save()
        l.beginPath(); l.ellipse(x, y, rx, ry); l.clip()
        l.fillRect(x - rx, y - ry, 2 * rx, 2 * ry, Col("#0b0d12"))
        l.beginPath(); l.arc(x - rx * 0.32, y - ry * 0.38, rx * 0.26); l.fill(Col(255, 255, 255, 0.85))
        l.fillRect(x - rx - 0.01, y - ry - 0.01, 2 * rx + 0.02, clamp(cierre, 0, 1) * 2 * ry + 0.01, piel)
        l.restore()
        if cierre > 0.85 {
            l.beginPath(); l.moveTo(x - rx, y + ry * 0.1); l.quadraticCurveTo(x, y + ry * 0.7, x + rx, y + ry * 0.1)
            l.stroke(Col(125, 140, 165, (cierre - 0.85) / 0.15 * 0.7), 0.022)
        }
    }
    // Contorno de gota: el frente sigue redondo y la parte de atrás se alarga.
    private func silueta(_ l: Lienzo, _ radio: Double) {
        l.beginPath()
        for i in 0...48 {
            let a = Double(i) / 48 * PI2, atras = max(0, -cos(a - ang)), r = radio * (1 + gota * atras * atras)
            l.lineTo(cos(a) * r, sin(a) * r)
        }
        l.closePath()
    }

    // Dibuja la esfera en su sitio del escritorio.
    func dibujarEn(_ l: Lienzo) {
        guard activo else { return }
        l.save(); l.translate(x, y); l.scale(u, u); cuerpo(l); l.restore()
    }

    override func cuerpo(_ l: Lienzo) {
        let t = self.t, s = semilla, P = { (k: String) in self.p[k] ?? 0 }
        let na = fase("nace"), fu = fase("funde"), pu = fase("pulso"), bl = fase("bloqueo"), ac = fase("acomoda")
        let va: Double = { if let v = vuelo, t - v.t0 < v.anticipa { return (t - v.t0) / v.anticipa }; return -1 }()
        // Al nacer, una luz grande se recoge en la esfera; al volver, la esfera se abre en luz y se apaga.
        let abre = na >= 0 ? 1 - suave(na / 0.8) : fu >= 0 ? suave(fu) : 0
        let apaga = fu >= 0 ? 1 - suave(fu) : 1
        let esfera = na >= 0 ? suave((na - 0.35) / 0.45) : fu >= 0 ? 1 - suave(fu / 0.6) : 1
        // Respira con la luz: el halo sube y baja de brillo y la esfera se ensancha un poco al inspirar.
        let resp = sin(t * PI2 / 4.2 + s)
        let brillo = P("brillo") * (1 + 0.08 * resp) * (1 + 0.6 * (pu >= 0 ? sin(pu * .pi) : 0)) * apaga
        // Posado deriva despacio en dos ejes, con un ritmo que no se repite; al anticipar o acomodarse se hunde un poco.
        let quieto: Double = (vuelo != nil && va < 0) || reducir() ? 0 : 1
        let dx = ruido(t * 0.55, s) * 0.045 * P("deriva") * quieto, dy = ruido(t * 0.47, s + 40) * 0.06 * P("deriva") * quieto
        let hunde = (va >= 0 ? sin(va * .pi) * 0.09 : 0) + (ac >= 0 ? sin(ac * .pi) * 0.07 : 0)
        if ac > 0.5 && una("asienta") { aplastaV += 2 }

        l.save(); l.scale(escala, escala); l.translate(dx, dy + hunde)
        // Halo irregular: cuatro nubes ovaladas que derivan y cambian de tamaño despacio; en vuelo se quedan un poco atrás.
        l.save(); l.sumaLuz = true
        let rh = 1.5 * (1 + 1.2 * abre), ax = -cos(ang) * gota * 3, ay = -sin(ang) * gota * 3, halo = Col(210, 228, 255)
        for i in 0..<4 {
            let fi = Double(i), si = s + fi * 17, r = rh * (0.95 + 0.14 * ruido(t * 0.23, si) + 0.08 * fi)
            l.save()
            l.translate(quieto * ruido(t * 0.19, si + 3) * 0.3 + ax * (0.4 + 0.3 * fi), quieto * ruido(t * 0.17, si + 9) * 0.24 + ay * (0.4 + 0.3 * fi))
            l.rotate(t * 0.05 * (i % 2 == 1 ? 1 : -1) + fi * 0.8); l.scale(1, 0.66 + 0.14 * ruido(t * 0.21, si + 5))
            l.beginPath(); l.arc(0, 0, r)
            l.fill(.radial(0, 0, 0.1, 0, 0, r).parada(0, halo.alfa(0.32 * brillo)).parada(0.4, halo.alfa(0.11 * brillo)).parada(0.7, halo.alfa(0.035 * brillo)).parada(1, halo.alfa(0)))
            l.restore()
        }
        l.restore()

        if esfera > 0.01 {
            l.save(); l.alfa = esfera; transformar(l)
            let radio = R * (1 + 0.02 * resp) * (1 - hunde * 0.3)
            let g = Degradado.radial(-0.15, -0.2, 0.05, 0, 0, radio).parada(0, Col("#ffffff")).parada(0.7, Col("#eef2f7")).parada(1, Col("#c9d3e2"))
            silueta(l, radio); l.fill(g)
            // Luz interior: un brillo que se desplaza muy despacio dentro de la esfera, como luz líquida.
            l.save(); silueta(l, radio); l.clip(); l.sumaLuz = true
            let lx = ruido(t * 0.3, s + 7) * 0.12, ly = ruido(t * 0.26, s + 19) * 0.1
            l.fillRect(-1, -1, 2, 2, .radial(lx, ly, 0, lx, ly, 0.32).parada(0, Col(205, 225, 255, 0.22 * brillo)).parada(1, Col(205, 225, 255, 0)))
            l.restore()
            // Los ojos se deslizan por la esfera hacia donde mira.
            let entorna = bl < 0 ? 0 : suave((bl - 0.35) / 0.15) * suave((1 - bl) / 0.15)
            let cierre = lerp(P("cierre"), 0.6, entorna) + parpadeando()
            let mx = clamp(mirada.x, -1, 1) * 0.14, my = clamp(mirada.y, -1, 1) * 0.1
            l.alfa = esfera * suave((esfera - 0.5) / 0.5)
            for k in [-1.0, 1] { ojo(l, k * 0.19 + mx, -0.03 + my, cierre, g) }
            l.restore()
        }
        l.restore()
    }
}
