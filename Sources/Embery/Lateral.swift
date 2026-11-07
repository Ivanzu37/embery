import AppKit

// Variante de la pestaña del borde: un notch lateral negro, en el mismo sitio que la rama. Arriba, un lucero que dice
// el estado con su forma; debajo, el hilo de la luz de hoy (en foco, el de la sesión con el del día al lado) y abajo la
// racha o los minutos. Se dibuja como la rama: con el borde de la pantalla a la derecha y espejado a la izquierda.
// Maqueta aprobada: proyectos/embery/assets/prototipo/lateral-v2.html de la bóveda.

let LW = 28.0, LH = 132.0, LY0 = (TH - LH) / 2
private let OREJA_L = 9.0
private let FRIO = Col(210, 228, 255)
private let CLARO = Col(236, 244, 255)

private func cuerpo(_ l: Lienzo, _ x0: Double, _ y0: Double, _ y1: Double) {
    l.beginPath()
    l.moveTo(TW, y0 - OREJA_L)
    l.quadraticCurveTo(TW, y0, TW - OREJA_L, y0)
    l.lineTo(x0 + 13, y0); l.quadraticCurveTo(x0, y0, x0, y0 + 13)
    l.lineTo(x0, y1 - 13); l.quadraticCurveTo(x0, y1, x0 + 13, y1)
    l.lineTo(TW - OREJA_L, y1)
    l.quadraticCurveTo(TW, y1, TW, y1 + OREJA_L)
    l.closePath()
}

private func conBrillo(_ l: Lienzo, _ c: Col, _ desenfoque: Double, _ dibujo: () -> Void) {
    l.save(); l.ctx.setShadow(offset: .zero, blur: desenfoque, color: c.cg); dibujo(); l.restore()
}

final class Lateral {
    private var hoy = 0.0, ses = 0.0, bovedaK = 0.0
    private let semilla = azar(0, 6)

    // aviso y pulso: segundos desde el último bloqueo y desde el último minuto de foco cumplido.
    // etiqueta, desdeFoco y sube: segundos desde que se abrió la etiqueta de inicio, desde que empezó el foco y desde que
    // la luz de espera empezó a subir al terminar.
    func dibujar(_ l: Lienzo, dt: Double, t tReal: Double, foco: Bool, pausa: Bool, dormido: Bool, hoy hoyReal: Double, ses sesReal: Double,
                 minutos: String, racha: Int, aviso: Double, pulso: Double, nombre: String, etiqueta: Double, desdeFoco: Double,
                 esperando: Bool, sube: Double, sinBoveda: Bool, izq: Bool, reducir: Bool) {
        let x0 = TW - LW, y0 = LY0, y1 = LY0 + LH, ex = x0 + 13
        let t = reducir ? 0 : tReal
        let apagado = dormido ? 0.25 : pausa ? 0.5 : 1
        let resp = reducir ? 0.5 : (sin(t * PI2 / (pausa ? 7 : foco ? 4.2 : 6) + semilla) + 1) / 2
        hoy = lerp(hoy, max(0, hoyReal), ease(dt, 0.15))
        ses = lerp(ses, clamp(sesReal, 0, 1), ease(dt, 0.15))
        let lleno = hoyReal >= 1
        bovedaK = reducir ? (sinBoveda ? 1 : 0) : lerp(bovedaK, sinBoveda ? 1 : 0, ease(dt, 0.08))
        let resp7 = reducir ? 0.5 : (sin(tReal * PI2 / 7 + semilla) + 1) / 2

        l.save()
        if izq { l.translate(TW, 0); l.scale(-1, 1) }

        // Halo: sale del lado recto del cuerpo, irregular y vivo; más ancho cuanta más luz hay hoy. Solo cubre el tramo
        // recto y acaba en x0 + 1, debajo del negro: si llegara a las esquinas o a las orejas aclararía el escritorio.
        if !dormido {
            // Sin bóveda se apaga: esta luz viene de las raíces.
            let fuerza = (0.10 + 0.16 * clamp(hoy, 0, 1.2) + (foco ? 0.06 * resp : 0) + (lleno ? 0.06 : 0)) * apagado * (1 - bovedaK)
            let ya = y0 + 13, yb = y1 - 13
            l.beginPath(); l.moveTo(x0 + 1, ya)
            var y = ya
            while y <= yb {
                let k = (y - y0) / LH
                let r = 6 + 1.4 * sin(k * 7.3 + t * 0.35 + semilla) + 0.9 * sin(k * 15.1 - t * 0.22) + 2.5 * resp * (foco ? 1 : 0.3)
                l.lineTo(x0 - r * pow(sin((y - ya) / (yb - ya) * .pi), 2), y)
                y += 3
            }
            l.lineTo(x0 + 1, yb); l.closePath()
            conBrillo(l, FRIO.alfa(fuerza), 3) { l.fill(.lineal(x0 - 10, 0, x0 + 1, 0).parada(0, FRIO.alfa(0)).parada(1, FRIO.alfa(fuerza))) }
        }

        // Etiqueta de inicio: el negro crece hacia el escritorio en un lóbulo con el nombre, y vuelve.
        let ek = nombre.isEmpty ? 0 : etiquetaK(etiqueta, reducir: reducir)
        let nom = ek > 0 ? Lienzo.recortar(nombre, cabe: 88, tamano: 11, peso: .medium) : ""
        let wL = ek * min(110, Lienzo.ancho(nom, tamano: 11, peso: .medium) + 22), ly = y1 - 27, lh = 22.0

        cuerpo(l, x0, y0, y1)
        l.fill(.lineal(x0, 0, TW, 0).parada(0, Col(5, 6, 8)).parada(1, Col(0, 0, 0)))
        if wL > 0 { l.beginPath(); l.roundRect(x0 - wL, ly, wL + 13, lh, 11); l.fill(Col(5, 6, 8)) }

        // Filo de luz interior: el trazo de 2 px recortado al cuerpo deja 1 px dentro. Sin bóveda, a la mitad.
        let filo = FRIO.alfa((0.10 + 0.08 * resp) * apagado * (1 - 0.5 * bovedaK))
        if wL > 0 {
            // El filo del lóbulo solo fuera del cuerpo: dentro del notch se vería su curva.
            l.save(); l.beginPath(); l.rect(x0 - wL - 2, ly - 2, wL + 2.5, lh + 4); l.clip()
            l.beginPath(); l.roundRect(x0 - wL + 0.5, ly + 0.5, wL + 13, lh - 1, 10.5); l.stroke(filo, 1)
            l.restore()
        }
        l.save(); cuerpo(l, x0, y0, y1); l.clip()
        l.stroke(filo, 2)
        // Aviso: una ola de luz recorre el filo de arriba abajo, dos veces, y para.
        let ola = aviso < 3.2 ? aviso.truncatingRemainder(dividingBy: 1.6) / 1.6 : -1
        if ola >= 0 {
            let oy = reducir ? (y0 + y1) / 2 : lerp(y0 - 10, y1 + 10, ola)
            let a = 0.45 * (reducir ? 0.6 : sin(ola * .pi))
            l.fillRect(x0, oy - 30, LW, 60, .radial(x0 + 2, oy, 0, x0 + 2, oy, 26).parada(0, FRIO.alfa(a)).parada(1, FRIO.alfa(0)))
        }
        l.restore()

        if wL > 4 {
            let cx = x0 - wL / 2 + 4
            l.save(); l.beginPath(); l.roundRect(x0 - wL, ly, wL + 13, lh, 11); l.clip()
            l.translate(cx, 0); if izq { l.scale(-1, 1) }
            l.alfa = suave((ek - 0.5) / 0.4)
            l.texto(nom, 0, ly + lh / 2 + 0.5, tamano: 11, peso: .medium, color: Col("#d2e4ff"), redonda: false)
            l.restore()
        }

        // Al empezar el foco, el lucero se encoge 0,2 s y luego le crecen los rayos en 0,6 s.
        let late = ola >= 0 && !reducir ? max(0, sin(ola * PI2 - 0.9)) : 0
        let encoge = foco && !reducir && desdeFoco >= 0 && desdeFoco < 0.2 ? 1 - 0.6 * sin(desdeFoco / 0.2 * .pi) : 1
        let rayos = !foco ? 0 : reducir || desdeFoco < 0 ? 1 : desdeFoco < 0.2 ? 0 : suave((desdeFoco - 0.2) / 0.6)
        lucero(l, ex, y0 + 22, t: t, resp: resp * encoge, foco: foco, pausa: pausa, dormido: dormido, lleno: lleno, late: late, rayos: rayos)

        // Claude esperando: una luz quieta entre el lucero y el borde. Al terminar sube hacia la oreja y se apaga.
        if foco && esperando && (sube < 0 || sube > 0.9) { luzEspera(l, TW - 7, y0 + 9, resp7: resp7, apagado) }
        if sube >= 0 && sube < 0.9 {
            if reducir { if sube < 0.3 { luzEspera(l, TW - 7, y0 + 9, resp7: 1, 1 - sube / 0.3) } }
            else { let s = sube / 0.9; luzEspera(l, TW - 7 + 4 * s, y0 + 9 - 22 * suave(s), resp7: 1, 1 - s * s) }
        }

        // Progreso: fuera de foco, el hilo central es la luz de hoy; en foco, la sesión, con el día en un hilo fino al lado.
        let hy0 = y0 + 40, largo = LH - 74, hy1 = hy0 + largo
        func pista(_ x: Double, _ w: Double, _ v: Double, _ a: Double) {
            l.beginPath(); l.roundRect(x - w / 2, hy0, w, largo, w / 2); l.fill(Col(255, 255, 255, 0.08 * apagado))
            guard v > 0.01 else { return }
            let alto = largo * clamp(v, 0, 1), top = hy1 - alto
            conBrillo(l, FRIO.alfa(0.8 * a), 5) {
                l.beginPath(); l.roundRect(x - w / 2, top, w, alto, w / 2)
                l.fill(.lineal(0, hy1, 0, top).parada(0, FRIO.alfa(0.35 * a)).parada(1, CLARO.alfa(a)))
            }
            // Punta viva: una perla de luz que respira donde acaba el progreso.
            l.beginPath(); l.arc(x, top, w * 0.9 + 0.6 * resp); l.fill(Col(245, 250, 255, a))
        }
        if foco {
            pista(ex - 6, 1, hoy, 0.55 * apagado)
            pista(ex, 2.2, ses, apagado)
            // Tras cada minuto cumplido sube una mota por el hilo de la sesión.
            if !pausa && !reducir && pulso < 3.6 {
                let m = pulso / 3.6
                l.beginPath(); l.arc(ex, lerp(hy1, hy1 - largo * ses, m), 1.1); l.fill(Col(255, 255, 255, 0.8 * sin(m * .pi)))
            }
        } else {
            pista(ex, 2.2, hoy, apagado)
        }
        // Objetivo sin cumplir: un aro hueco en lo alto del hilo. Cumplido, lo dice la corona del lucero.
        if !lleno { l.beginPath(); l.arc(ex, hy0 - 4, 1.6); l.stroke(Col(255, 255, 255, 0.3 * apagado), 0.7) }

        // Abajo: minutos en foco; fuera de foco, la racha en puntos (como mucho 7) con el de hoy más vivo.
        if foco {
            l.save(); l.translate(ex, y1 - 16)
            if izq { l.scale(-1, 1) }
            l.texto(minutos, 0, 0, tamano: 11, peso: .medium, color: Col(245, 245, 247, pausa ? 0.45 : 0.95))
            l.restore()
        } else if racha > 0 {
            let n = min(7, racha), yb = y1 - 18
            for i in 0..<n {
                l.beginPath(); l.arc(ex, yb + (Double(i) - Double(n - 1) / 2) * 4.4, 0.95)
                l.fill(FRIO.alfa((i == n - 1 ? 0.85 : 0.4) * apagado))
            }
        }
        l.restore()
    }

    // Lucero: punto de luz sin cara. Reposo, núcleo y halo irregular; foco, rayos finos que giran muy despacio;
    // pausa, creciente; cumplido, corona de chispas; dormido, solo el contorno del creciente; aviso, un latido.
    private func lucero(_ l: Lienzo, _ x: Double, _ y: Double, t: Double, resp: Double, foco: Bool, pausa: Bool, dormido: Bool, lleno: Bool, late: Double, rayos: Double) {
        l.save(); l.translate(x, y)
        defer { l.restore() }
        if dormido {
            l.beginPath(); l.arc(0, 0, 3.6, .pi * 0.3, .pi * 1.7)
            l.arc(1.6, 0, 3.0, .pi * 1.62, .pi * 0.38, inverso: true)
            l.closePath(); l.stroke(FRIO.alfa(0.35), 0.7)
            return
        }
        let a = pausa ? 0.55 : 1, r = 2.6 + 0.35 * resp + 0.8 * late

        // Halo irregular y vivo, nunca un círculo perfecto: capas de la misma forma, cada vez más pequeñas y tenues,
        // con desenfoque para que el borde no se lea como una mancha.
        conBrillo(l, FRIO.alfa(0.5 * a), 6) {
            for capa in [1.0, 0.72, 0.45] {
                l.beginPath()
                for i in 0...40 {
                    let ang = Double(i) / 40 * PI2
                    let rr = capa * ((lleno ? 8.5 : 6.5) + 1.1 * sin(ang * 3 + t * 0.4 + semilla) + 0.7 * sin(ang * 5 - t * 0.27) + 1.5 * resp + 3 * late)
                    if i == 0 { l.moveTo(cos(ang) * rr, sin(ang) * rr) } else { l.lineTo(cos(ang) * rr, sin(ang) * rr) }
                }
                l.fill(FRIO.alfa(0.045 * a))
            }
        }

        if foco && !pausa && rayos > 0 {
            l.save(); l.rotate(t * 0.12)
            let largo = (9 + 1.2 * resp) * rayos
            for _ in 0..<4 {
                l.rotate(.pi / 2)
                l.beginPath(); l.moveTo(-0.45, 0); l.lineTo(0, -largo); l.lineTo(0.45, 0); l.closePath()
                l.fill(.lineal(0, 0, 0, -largo).parada(0, CLARO.alfa(0.55)).parada(1, FRIO.alfa(0)))
            }
            l.restore()
        }
        if lleno {
            for i in 0..<6 {
                let ang = Double(i) / 6 * PI2 + t * 0.05, d = 6.2 + 0.6 * sin(t * 0.8 + Double(i) * 1.7)
                l.beginPath(); l.arc(cos(ang) * d, sin(ang) * d, 0.55); l.fill(CLARO.alfa(0.5 + 0.35 * sin(t * 0.9 + Double(i))))
            }
        }

        conBrillo(l, FRIO.alfa(0.8 * a), 5) {
            l.beginPath(); l.arc(0, 0, r)
            l.fill(.radial(-r * 0.3, -r * 0.3, 0, 0, 0, r).parada(0, Col(255, 255, 255, a)).parada(1, Col(190, 212, 250, 0.85 * a)))
        }
        // Pausa: una sombra muerde el núcleo y queda un creciente; recortada al núcleo para no tapar el halo.
        if pausa {
            l.save(); l.beginPath(); l.arc(0, 0, r + 0.5); l.clip()
            l.beginPath(); l.arc(r * 0.75, -r * 0.2, r * 0.95); l.fill(Col(4, 5, 7))
            l.restore()
        }
    }
}
