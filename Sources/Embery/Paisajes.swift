import AVFoundation

// Paisajes sonoros sintetizados: lluvia, bosque, mar, chimenea y ruido blanco, rosa o marrón. Graves y suaves.
// El motor de audio solo existe mientras suena: en silencio no gasta nada.

final class Generador {
    let clave: String
    private let sr: Double
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0   // ruido rosa (Paul Kellet)
    private var marron = 0.0, lp = 0.0, lp2 = 0.0, t = 0.0
    private var gotas: [(f: Double, fase: Double, amp: Double)] = []
    private var chispas: [(amp: Double, lp: Double)] = []
    private var ola = 0.0, olaV = 0.12

    init(_ clave: String, sr: Double = 48000) { self.clave = clave; self.sr = sr }

    private func blanco() -> Double { Double.random(in: -1...1) }
    private func rosa() -> Double {
        let w = blanco()
        b0 = 0.99886 * b0 + w * 0.0555179; b1 = 0.99332 * b1 + w * 0.0750759; b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856; b4 = 0.55000 * b4 + w * 0.5329522; b5 = -0.7616 * b5 - w * 0.0168980
        let r = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362; b6 = w * 0.115926
        return r * 0.11
    }
    private func marronSig() -> Double { marron = (marron + 0.02 * blanco()) / 1.02; return marron * 3.5 }
    // Paso bajo de un polo: k cerca de 1 = más grave.
    private func bajo(_ x: Double, _ y: inout Double, _ k: Double) -> Double { y = k * y + (1 - k) * x; return y }

    func muestra() -> Double {
        t += 1 / sr
        switch clave {
        case "blanco": return blanco() * 0.25
        case "rosa": return rosa() * 0.9
        case "marron": return marronSig() * 0.9
        case "lluvia":
            // Cortina de agua grave y, de vez en cuando, una gota que suena sobre algo.
            var s = bajo(rosa(), &lp, 0.55) * 0.9
            if Double.random(in: 0..<1) < 6 / sr { gotas.append((Double.random(in: 700...1400), 0, Double.random(in: 0.02...0.06))) }
            for i in gotas.indices { gotas[i].fase += 2 * .pi * gotas[i].f / sr; s += sin(gotas[i].fase) * gotas[i].amp; gotas[i].amp *= 0.9985 }
            gotas.removeAll { $0.amp < 0.0005 }
            return s
        case "mar":
            // Olas: ruido marrón que sube y baja con un ritmo que nunca es exacto.
            ola += olaV / sr
            if ola >= 1 { ola = 0; olaV = Double.random(in: 0.09...0.15) }
            let env = 0.25 + 0.75 * pow(sin(.pi * ola), 2)
            return bajo(marronSig(), &lp, 0.6 + 0.3 * (1 - env)) * env * 1.1
        case "bosque":
            // Viento entre hojas: ruido rosa muy filtrado que respira despacio.
            let viento = 0.55 + 0.45 * sin(t * 0.21) * sin(t * 0.13 + 1)
            return bajo(bajo(rosa(), &lp, 0.85), &lp2, 0.7) * 1.05 * viento
        case "chimenea":
            // Fuego bajo y algún chasquido suave de leña.
            var s = bajo(marronSig(), &lp, 0.5) * 0.7
            if Double.random(in: 0..<1) < 3 / sr { chispas.append((Double.random(in: 0.15...0.4), 0)) }
            for i in chispas.indices {
                chispas[i].lp = 0.6 * chispas[i].lp + 0.4 * blanco() * chispas[i].amp
                s += chispas[i].lp; chispas[i].amp *= 0.993
            }
            chispas.removeAll { $0.amp < 0.001 }
            return s
        default: return 0
        }
    }
}

final class Paisajes {
    static let todos: [(String, String)] = [("lluvia", String(localized: "Lluvia")), ("bosque", String(localized: "Bosque")), ("mar", String(localized: "Mar")), ("chimenea", String(localized: "Chimenea")),
                                            ("blanco", String(localized: "Blanco")), ("rosa", String(localized: "Rosa")), ("marron", String(localized: "Marrón"))]
    private var motor: AVAudioEngine?
    private(set) var sonando: String?
    // Volumen que se pide y el que suena, que lo sigue despacio: nada entra ni sale de golpe.
    private var objetivo = 0.0, actual = 0.0, paso = 0.0
    private var alApagar: (() -> Void)?

    // subida: segundos hasta llegar al volumen (20 al empezar un foco, 3 a mano).
    func tocar(_ clave: String, volumen: Double, subida: Double = 3) {
        if sonando != clave { pararYa() }
        sonando = clave
        objetivo = volumen * 0.5
        paso = 1 / (48000 * max(0.05, subida))
        guard motor == nil else { return }
        let g = Generador(clave), m = AVAudioEngine()
        let formato = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let nodo = AVAudioSourceNode(format: formato) { [weak self] _, _, n, lista -> OSStatus in
            guard let self else { return noErr }
            let buf = UnsafeMutableAudioBufferListPointer(lista)
            let p = buf[0].mData!.assumingMemoryBound(to: Float.self)
            for i in 0..<Int(n) {
                self.actual += max(-self.paso, min(self.paso, self.objetivo - self.actual))
                p[i] = Float(g.muestra() * self.actual)
            }
            if self.objetivo == 0 && self.actual == 0, let fin = self.alApagar { self.alApagar = nil; DispatchQueue.main.async(execute: fin) }
            return noErr
        }
        m.attach(nodo)
        do { try m.connectNode(nodo, to: m.mainMixerNode, format: formato); try m.start(); motor = m } catch { NSLog("Embery: paisajes: \(error)"); sonando = nil }
    }

    func volumen(_ v: Double) { if sonando != nil { objetivo = v * 0.5; paso = 1 / (48000 * 0.3) } }

    // Se apaga bajando poco a poco y luego para el motor.
    func apagar(bajada: Double = 3) {
        guard motor != nil else { sonando = nil; return }
        objetivo = 0; paso = 1 / (48000 * max(0.05, bajada))
        alApagar = { [weak self] in self?.pararYa() }
    }
    private func pararYa() { motor?.stop(); motor = nil; sonando = nil; actual = 0; alApagar = nil }

    // Diez segundos de cada uno, para escucharlos antes de que entren en la app.
    static func exportar(_ dir: URL) {
        for (n, (clave, _)) in todos.enumerated() {
            let g = Generador(clave)
            var x = (0..<Int(48000 * 10)).map { _ in g.muestra() * 0.5 }
            // Entrada y salida de 1 s: el archivo no empieza ni acaba de golpe.
            for i in 0..<48000 { let k = Double(i) / 48000; x[i] *= k; x[x.count - 1 - i] *= k }
            try? Sonido.wav(x).write(to: dir.appendingPathComponent(String(format: "paisaje-%02d-%@.wav", n + 1, clave)))
        }
    }
}
