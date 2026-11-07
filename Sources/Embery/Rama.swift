import AppKit

// Pestaña del borde: una rama de luz. La savia sube con la luz de hoy hacia el objetivo (en foco, con la sesión);
// de una ramita cuelga una gota: rocío en normal, que en foco crece alimentada por motas de savia. Port de embery.html.

// El lienzo mide ANCHO: el borde de la pantalla sigue en x = TW y lo que sobra (100 pt) es para la etiqueta de inicio.
let TW = 40.0, TH = 210.0, ANCHO = 140.0
private let HOJAS = [0.27, 0.55], RAMITA = 0.7, CARTEL = 0.95
// La base queda 16 px por encima del fondo del lienzo para que la luz de la salida no se corte.
private let BASE = TH - 16
// Tronco irregular que adelgaza hacia arriba; la punta se dobla un poco hacia el escritorio.
// Nace detrás del borde de la pantalla (x > TW queda fuera del lienzo) y sale curvándose.
private func tronco(_ k: Double) -> Double { TW - 7 - 2.2 * sin(k * 4.1 + 0.6) - 0.8 * sin(k * 9.3 + 1) - 1.5 * k - 4 * pow(k, 6) }
private func sale(_ k: Double) -> Double { let u = min(1, k / 0.12); return u * u * (3 - 2 * u) }
private func grosor(_ k: Double) -> Double { lerp(3.6, 1.3, k) }
private func bez(_ a: Punto, _ c: Punto, _ b: Punto, _ u: Double) -> Punto {
    Punto(x: (1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * c.x + u * u * b.x, y: (1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * c.y + u * u * b.y)
}

func luzEn(_ l: Lienzo, _ x: Double, _ y: Double, _ r: Double, _ a: Double) {
    l.beginPath(); l.arc(x, y, r)
    l.fill(.radial(x, y, 0, x, y, r).parada(0, Col(215, 230, 255, a)).parada(1, Col(215, 230, 255, 0)))
}
// Etiqueta de inicio: 0,5 s abre · 3 s quieta · 0,45 s cierra (reducir: 0,2 s de fundido). e: segundos desde que empezó.
func etiquetaK(_ e: Double, reducir: Bool) -> Double {
    guard e >= 0 else { return 0 }
    if reducir { return e < 0.2 ? e / 0.2 : e < 3.2 ? 1 : e < 3.4 ? 1 - (e - 3.2) / 0.2 : 0 }
    return e < 0.5 ? suave(e / 0.5) : e < 3.5 ? 1 : e < 3.95 ? 1 - suave((e - 3.5) / 0.45) : 0
}
// Luz de espera: Claude espera a que termines. Una luz, sin número y sin latir.
func luzEspera(_ l: Lienzo, _ x: Double, _ y: Double, resp7: Double, _ k: Double) {
    l.sumaLuz = true; luzEn(l, x, y, 6, 0.4 * (0.7 + 0.3 * resp7) * k)
    l.sumaLuz = false; l.beginPath(); l.arc(x, y, 1.15); l.fill(Col(236, 244, 255, 0.85 * k))
}
func formaGota(_ l: Lienzo, _ x: Double, _ y: Double, _ r: Double, _ a: Double, _ tiembla: Double) {
    l.save(); l.translate(x, y); l.rotate(-a)
    l.beginPath(); l.moveTo(0, -r * 1.9)
    l.bezierCurveTo(r * 0.5, -r * 1.2, r * tiembla, -r * 0.4, r * tiembla, r * 0.15)
    l.arc(0, r * 0.15, r * tiembla, 0, .pi); l.bezierCurveTo(-r * tiembla, -r * 0.4, -r * 0.5, -r * 1.2, 0, -r * 1.9)
    l.fill(.radial(-r * 0.3, -r * 0.2, 0, 0, 0, r * 1.4).parada(0, Col(255, 255, 255)).parada(1, Col(160, 190, 240, 0.75)))
    l.restore()
}

final class Rama {
    struct Mota { var k = 0.0, u = 0.0, fin = 0.0, fuera = false }
    var savia = 0.0, cima = 18.0, radioGota = 2.2, proximaMota = 1.0, verCartel = 0.0, balanceo = 0.0
    var motas: [Mota] = []
    var cartel = "50"
    var avisoT = -1e9, pulsoT = -1e9, tragoT = -1e9
    // Compartidos con el notch lateral: etiqueta de inicio, foco empezado y subida de la luz de espera (reloj continuo).
    var etiquetaT = -1e9, focoT = -1e9, esperaSube = -1e9
    var nombre = ""
    private var bovedaK = 0.0

    func rama(_ k: Double) -> Punto { Punto(x: lerp(TW + 5, tronco(k), sale(k)) + balanceo * k * k, y: BASE - (BASE - cima) * k) }
    // Ramita lateral y punto del que cuelga la gota.
    func ramita() -> (p: Punto, c: Punto, q: Punto) { let p = rama(RAMITA); return (p, Punto(x: p.x - 8, y: p.y - 9), Punto(x: p.x - 17, y: p.y + 1)) }
    func centroGota(_ t: Double, reducir: Bool) -> (x: Double, y: Double, a: Double) {
        let q = ramita().q, a = reducir ? 0 : sin(t * 0.8) * 0.09, largo = 3 + radioGota * 0.4 + radioGota * 1.9
        return (q.x + sin(a) * largo, q.y + cos(a) * largo, a)
    }

    private var cortezas: [Int: CGImage] = [:]
    private func corteza() -> CGImage {
        // Mientras la raicilla se suelta o se agarra (≈ 0,8 s) se pinta sin guardar: solo se guardan las dos posturas quietas.
        let q = Int((bovedaK * 20).rounded()), guarda = q == 0 || q == 20
        let clave = Int((balanceo * 8).rounded()) * 2 + (q == 20 ? 1 : 0)
        if guarda, let i = cortezas[clave] { return i }
        let e = Pantallas.actual.backingScaleFactor, w = Int(TW * e), h = Int(TH * e)
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: e, y: -e)
        let l = Lienzo(c)
        let (rp, rc, rq) = ramita()
        // Corteza en gris frío con un filo de luz, para que se lea sobre fondos claros y oscuros.
        let corteza = Col("#3b4659")
        // Sombra de contacto suave: con fondos claros la corteza sola se perdía. El desenfoque no escala con el CTM.
        c.setShadow(offset: .zero, blur: 3 * e, color: Col(0, 0, 0, 0.45).cg); c.beginTransparencyLayer(auxiliaryInfo: nil)
        // El tronco se pinta a tramos para que adelgace.
        var k = 0.0
        while k < 1 { let a = rama(k), b = rama(min(1, k + 0.045)); l.beginPath(); l.moveTo(a.x, a.y); l.lineTo(b.x, b.y); l.stroke(corteza, grosor(k)); k += 0.04 }
        l.beginPath(); l.moveTo(rp.x, rp.y); l.quadraticCurveTo(rc.x, rc.y, rq.x, rq.y); l.stroke(corteza, 1.5)
        // Raicilla que se agarra al borde a media altura; sin bóveda se suelta y cuelga.
        let ra = rama(0.42), b = guarda ? Double(q) / 20 : bovedaK
        l.beginPath(); l.moveTo(ra.x, ra.y)
        l.quadraticCurveTo(lerp(TW - 2, ra.x + 6, b), lerp(ra.y - 2, ra.y + 3, b), lerp(TW + 3, ra.x + 5, b), lerp(ra.y - 9, ra.y + 12, b))
        l.stroke(corteza, 1.3)
        // Ramita corta de la que cuelga el cartel.
        let cp = rama(CARTEL), cs = Punto(x: cp.x - 9, y: cp.y + 1)
        l.beginPath(); l.moveTo(cp.x, cp.y); l.quadraticCurveTo(cp.x - 5, cp.y - 3, cs.x, cs.y); l.stroke(corteza, 1.2)
        func brote(_ k: Double) -> (p: Punto, c: Punto, q: Punto) { let p = rama(k); return (p, Punto(x: p.x - 3, y: p.y - 5), Punto(x: p.x - 7, y: p.y - 6)) }
        for k in HOJAS { let b = brote(k); l.beginPath(); l.moveTo(b.p.x, b.p.y); l.quadraticCurveTo(b.c.x, b.c.y, b.q.x, b.q.y); l.stroke(corteza, 1.2) }
        l.beginPath(); k = 0
        while k <= 1 + 1e-6 { let p = rama(k); l.lineTo(p.x - grosor(k) * 0.45, p.y); k += 0.02 }
        l.stroke(Col(205, 220, 245, 0.26), 0.8)
        func hoja(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ ang: Double) { l.beginPath(); l.ellipse(x, y, rx, ry, ang); l.fill(Col(120, 150, 135, 0.7)) }
        for k in HOJAS { let q = brote(k).q; hoja(q.x - 2.2, q.y - 0.6, 3.2, 1.6, 0.35) }
        let mitad = bez(rp, rc, rq, 0.45); hoja(mitad.x - 1, mitad.y - 3, 2.4, 1.2, 0.9)
        c.endTransparencyLayer()
        let i = c.makeImage()!
        if guarda { cortezas[clave] = i }
        return i
    }

    // ahora: segundos de reloj continuo, para los destellos de aviso, pulso y trago.
    func dibujar(_ l: Lienzo, t: Double, dt: Double, ahora: Double, foco: Bool, pausa: Bool, dormido: Bool, v: Double, resp: Double,
                 hoyLleno: Bool, racha: Bool, esperando: Bool, sinBoveda: Bool, izq: Bool, reducir: Bool) {
        l.save()
        // Con el panel a la izquierda se dibuja espejado; el texto del cartel se vuelve a girar para leerse al derecho.
        if izq { l.translate(TW, 0); l.scale(-1, 1) }
        savia = lerp(savia, v, ease(dt, 0.15))
        // Con «reducir movimiento» la rama, las motas y la gota se quedan quietas; solo cambia la luz.
        // A pasos de 1/8 de punto (un cuarto de píxel): no se nota y permite reutilizar la corteza pintada.
        balanceo = reducir ? 0 : (8 * 1.3 * (sin(t * 0.55) + 0.35 * sin(t * 1.27 + 1))).rounded() / 8
        bovedaK = reducir ? (sinBoveda ? 1 : 0) : lerp(bovedaK, sinBoveda ? 1 : 0, ease(dt, 0.08))
        let aviso = max(0, 1 - (ahora - avisoT) / 0.9), apaga = dormido ? 0.35 : pausa ? 0.5 : 1
        let resp7 = reducir ? 0.5 : (sin(t * PI2 / 7) + 1) / 2
        func trazo(_ desde: Double, _ hasta: Double, _ f: (Double) -> Punto, _ c: Col, _ ancho: Double) {
            l.beginPath(); var k = desde
            while k <= hasta + 1e-6 { let p = f(k); l.lineTo(p.x, p.y); k += 0.02 }
            l.stroke(c, ancho)
        }
        // Luz de espera: medio escondida tras el tronco, en la base. Al terminar sube por la rama y se apaga.
        let sube = ahora - esperaSube
        if foco && esperando && sube > 0.9 { let b = rama(0.12); luzEspera(l, b.x - 2.2, b.y + 2, resp7: resp7, apaga) }
        if sube >= 0 && sube < 0.9 {
            if reducir { let b = rama(0.12); if sube < 0.3 { luzEspera(l, b.x - 2.2, b.y + 2, resp7: 1, 1 - sube / 0.3) } }
            else { let s = sube / 0.9, p = rama(lerp(0.12, 1, suave(s))); luzEspera(l, p.x - 2.2 * (1 - s), p.y + 2 * (1 - s), resp7: 1, 1 - s * s) }
        }
        // La corteza solo cambia con el balanceo: se pinta una vez por postura y aquí solo se pega la imagen.
        let img = corteza(), lc = l.ctx
        l.save(); l.translate(0, TH); l.scale(1, -1); lc.draw(img, in: CGRect(x: 0, y: 0, width: TW, height: TH)); l.restore()
        let (rp, rc, rq) = ramita()
        let cp = rama(CARTEL), cs = Punto(x: cp.x - 9, y: cp.y + 1)
        l.sumaLuz = true
        // Luz tenue donde la rama sale del borde: como si la luz viniera de detrás de la pantalla.
        luzEn(l, TW, rama(0.02).y, 10 + 2 * resp, 0.22 * apaga * (1 - 0.75 * bovedaK))
        // Savia fina dentro de la corteza, con un resplandor suave alrededor.
        trazo(0, savia, rama, Col(200, 220, 255, 0.16 * apaga), 4)
        trazo(0, savia, rama, Col(235, 243, 255, 0.8 * apaga), 1)
        if aviso > 0 { trazo(0, 1, rama, Col(215, 230, 255, 0.5 * aviso), 4) }
        let punta = rama(savia), pulso = max(0, 1 - (ahora - pulsoT) / 0.9)
        luzEn(l, punta.x, punta.y, 7 + 3 * resp + 6 * pulso, (0.35 + 0.4 * pulso + (!foco && hoyLleno ? 0.25 : 0)) * apaga)
        // Luciérnagas en las hojas que la savia ya ha alcanzado.
        for (i, k) in HOJAS.enumerated() where savia >= k {
            let p = rama(k), fi = Double(i)
            luzEn(l, p.x - 11 + ruido(t * 0.8, fi * 7) * 1.4, p.y - 12 + ruido(t * 0.7, fi * 7 + 3) * 1.4, 4.5, (0.5 + 0.4 * (sin(t * 1.7 + fi * 2) + 1) / 2) * apaga)
        }
        // Motas de savia: en normal suben hasta la punta; en foco siguen por la ramita y entran en la gota.
        if !pausa && !dormido && !reducir { proximaMota -= dt; if proximaMota <= 0 { motas.append(Mota()); proximaMota = foco ? 1.2 + Double.random(in: 0..<0.8) : 3 + Double.random(in: 0..<2) } }
        for i in motas.indices {
            var m = motas[i]
            if m.k < (foco ? RAMITA : savia) { m.k += dt * 0.32 } else if foco { m.u += dt * 1.6 } else { m.fin += dt * 2 }
            let pt = m.u > 0 ? bez(rp, rc, rq, min(1, m.u)) : rama(min(m.k, 1))
            luzEn(l, pt.x, pt.y, 2.6, 0.9 * (1 - min(1, m.fin)))
            if m.u >= 1 { m.fuera = true; tragoT = ahora }
            motas[i] = m
        }
        motas.removeAll { $0.fuera || $0.fin >= 1 }
        // La gota: rocío que respira en normal; en foco crece con la sesión. Al tragar una mota se hincha un poco.
        let trago = max(0, 1 - (ahora - tragoT) / 0.4)
        radioGota = lerp(radioGota, cayendo ? 0 : foco ? 2.6 + 6 * v : 2.2, ease(dt, cayendo ? 0.5 : 0.08))
        if radioGota > 0.3 {
            let g = centroGota(t, reducir: reducir), r = radioGota * (1 + 0.05 * resp + 0.12 * trago)
            l.sumaLuz = false
            l.beginPath(); l.moveTo(rq.x, rq.y); l.lineTo(g.x - sin(g.a) * r * 1.9, g.y - cos(g.a) * r * 1.9); l.stroke(Col(215, 230, 255, 0.35), 0.7)
            l.sumaLuz = true
            luzEn(l, g.x, g.y, r * 3 + 3 * resp, 0.3 * apaga)
            l.sumaLuz = false; l.alfa = pausa ? 0.7 : 1
            formaGota(l, g.x, g.y, r, g.a, reducir ? 1 : 1 + 0.06 * sin(t * 3.1)); l.alfa = 1
        }
        // Racha: una lucecita en forma de destello en la punta de la rama (solo fuera del foco).
        if racha && !foco && !dormido {
            let tp = rama(1), a = 0.7 + 0.3 * resp; l.sumaLuz = true; luzEn(l, tp.x - 1, tp.y - 5, 7, 0.3 * a)
            l.beginPath()
            for j in 0..<8 { let an = Double(j) / 8 * PI2 - .pi / 2, rr = j % 2 == 1 ? 1.1 : 3.4; l.lineTo(tp.x - 1 + cos(an) * rr, tp.y - 5 + sin(an) * rr) }
            l.closePath(); l.fill(Col(200, 220, 255, a))
        }
        // Cartel con los minutos, colgado de la ramita con dos hilos fijos; se mece con la rama. Al empezar un foco con nombre,
        // la tabla crece hacia el escritorio (el lado del borde queda en +11,5) y enseña el nombre 3 s.
        verCartel = lerp(verCartel, foco ? 1 : 0, ease(dt, 0.02))
        if verCartel > 0.02 {
            let e = ahora - etiquetaT, ek = nombre.isEmpty ? 0 : etiquetaK(e, reducir: reducir)
            let nom = ek > 0 ? Lienzo.recortar(nombre, cabe: 78, tamano: 11, peso: .medium) : ""
            let wN = 23 + min(92, Lienzo.ancho(nom, tamano: 11, peso: .medium) + 14)
            let w = lerp(23, wN, ek), h = 15.0, mece = reducir ? 0 : sin(t * 0.7) * 0.06 * (1 - ek)
            let hunde = !reducir && e >= 0 && e < 0.3 ? sin(e / 0.3 * .pi) * 1.5 : 0
            l.sumaLuz = false; l.alfa = verCartel
            l.save(); l.translate(cs.x, cs.y + hunde); l.rotate(mece)
            l.beginPath(); l.moveTo(0, 0); l.lineTo(-9.5, 5); l.moveTo(0, 0); l.lineTo(9.5, 5); l.stroke(Col(205, 220, 245, 0.45), 0.6)
            l.beginPath(); l.roundRect(11.5 - w, 5, w, h, 4); l.fill(Col(0, 0, 0)); l.stroke(Col(255, 255, 255, 0.18), 0.8)
            for x in [-9.5, 9.5] { l.beginPath(); l.arc(x, 5 + 1.6, 0.7); l.fill(Col(205, 220, 245, 0.55)) }
            if ek > 0.05 { l.beginPath(); l.moveTo(-11.5, 7.5); l.lineTo(-11.5, 5 + h - 2.5); l.stroke(Col(255, 255, 255, 0.18 * ek), 0.8) }
            func texto(_ s: String, _ x: Double, _ a: Double, redonda: Bool, peso: NSFont.Weight, _ c: Col) {
                l.save(); l.translate(x, 0); if izq { l.scale(-1, 1) }
                l.alfa = verCartel * a; l.texto(s, 0, 5 + h / 2 + 0.5, tamano: 11, peso: peso, color: c, redonda: redonda); l.restore()
            }
            texto(cartel, 0, 1, redonda: true, peso: .semibold, pausa ? Col("#8e8e93") : Col("#d2e4ff"))
            if ek > 0.05 {
                l.save(); l.beginPath(); l.rect(11.5 - w, 5, w - 23, h); l.clip()
                texto(nom, -11.5 - (wN - 23) / 2, suave((ek - 0.5) / 0.4), redonda: false, peso: .medium, Col("#d2e4ff"))
                l.restore()
            }
            l.restore(); l.alfa = 1
        }
        l.sumaLuz = false
        l.restore()
    }

    var cayendo = false
}

// La gota que cae al terminar, en coordenadas del escritorio.
struct Caida { var x, y, r, vy, t0, vida: Double }
