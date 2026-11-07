import AppKit

// Sonidos de Embery, sintetizados aquí: sin archivos. Campana pequeña, kalimba y agua; graves y redondos.
// Cada nota dura hasta que su parcial más lento cae a -60 dB, así nada se corta mientras se oye.
// Cada evento tiene cuatro variantes de tono que se alternan al azar, y nada suena en bucle.
enum Sonido {
    enum Evento: String, CaseIterable {
        case foco, bienHecho = "bien-hecho", gota, lumen, bloqueo, permiso, claude, nido, tienda, respira, pluma
    }

    static let sr = 48000.0
    static let pico = 0.22
    // Semitonos de cada variante.
    static let variantes = [0.0, 2, -2, 3]
    // Volumen al que suena el evento, o nil si ahora no debe sonar; lo pone la app con sus ajustes.
    static var ajuste: (Evento) -> Float? = { _ in 0.6 }

    // Parciales: (múltiplo de f, amplitud, caída τ en s).
    static func nota(_ f: Double, _ parciales: [(Double, Double, Double)], ataque: Double = 0.003) -> [Double] {
        let tau = parciales.map(\.2).max() ?? 0.5
        return (0..<Int(sr * (ataque + tau * 6.9))).map { k in
            let t = Double(k) / sr
            return min(1, t / ataque) * parciales.reduce(0) { $0 + $1.1 * exp(-t / $1.2) * sin(2 * .pi * f * $1.0 * t) }
        }
    }
    static func kalimba(_ f: Double) -> [Double] { nota(f, [(1, 1, 0.45), (2, 0.12, 0.12), (5.4, 0.06, 0.03)]) }
    static func campana(_ f: Double, larga: Double = 1) -> [Double] {
        nota(f, [(1, 1, 0.9 * larga), (2, 0.3, 0.45 * larga), (2.76, 0.14, 0.28 * larga), (5.4, 0.04, 0.08)], ataque: 0.002)
    }
    // Gota de agua: un seno que sube de tono deprisa y se apaga.
    static func plic(_ f: Double) -> [Double] {
        var fase = 0.0
        return (0..<Int(sr * (0.002 + 0.045 * 6.9))).map { k in
            let t = Double(k) / sr
            fase += 2 * .pi * f * (1 + 0.7 * (1 - exp(-t / 0.025))) / sr
            return min(1, t / 0.002) * exp(-t / 0.045) * sin(fase)
        }
    }
    // El «hu» de Lumen: grave, con un poco de aire, que baja apenas al final.
    static func hu(_ f: Double) -> [Double] {
        var fase = 0.0, aire = 0.0
        let entra = 0.07, tau = 0.13
        return (0..<Int(sr * (entra + tau * 6.9))).map { k in
            let t = Double(k) / sr
            fase += 2 * .pi * f * (1 - 0.06 * min(1, t / 0.5) + 0.004 * sin(2 * .pi * 5 * t)) / sr
            aire += (Double.random(in: -1...1) - aire) * 0.04
            let env = t < entra ? pow(sin(.pi / 2 * t / entra), 2) : exp(-(t - entra) / tau)
            return env * (sin(fase) + 0.25 * sin(2 * fase) + 0.5 * aire)
        }
    }
    // Roce: ruido suave filtrado que entra y se va.
    static func roce() -> [Double] {
        var a = 0.0, b = 0.0
        let entra = 0.08, tau = 0.05
        return (0..<Int(sr * (entra + tau * 6.9))).map { k in
            let t = Double(k) / sr
            a += (Double.random(in: -1...1) - a) * 0.08; b += (a - b) * 0.3
            return (t < entra ? pow(sin(.pi / 2 * t / entra), 2) : exp(-(t - entra) / tau)) * b * 2.5
        }
    }

    // Pluma: ruido entre ~450 Hz y ~2,7 kHz (dos filtros), con el grano irregular del papel; el trazo entra
    // despacio, como un arrastre, y cae.
    static func pluma(tau: Double) -> [Double] {
        var a = 0.0, b = 0.0, c = 0.0, grano = 0.0
        let entra = 0.09
        return (0..<Int(sr * (entra + tau * 6.9))).map { k in
            let t = Double(k) / sr
            a += (Double.random(in: -1...1) - a) * 0.35; b += (a - b) * 0.06; c += (a - b - c) * 0.35
            grano += (Double.random(in: 0...1) - grano) * 0.002
            return (t < entra ? pow(sin(.pi / 2 * t / entra), 2) : exp(-(t - entra) / tau)) * c * (0.6 + 0.8 * grano)
        }
    }

    static func mezcla(_ partes: [(Double, [Double])]) -> [Double] {
        let n = partes.map { Int($0.0 * sr) + $0.1.count }.max() ?? 0
        var out = [Double](repeating: 0, count: n)
        for (t0, p) in partes { let i0 = Int(t0 * sr); for (k, v) in p.enumerated() { out[i0 + k] += v } }
        let m = out.map(abs).max() ?? 1
        return m > 0 ? out.map { $0 / m * pico } : out
    }

    static func muestras(_ e: Evento, semitonos s: Double = 0) -> [Double] {
        let k = pow(2, s / 12)
        switch e {
        case .foco: return mezcla([(0, kalimba(294 * k)), (0.17, kalimba(440 * k))])
        case .bienHecho:
            let f = 196 * k
            return mezcla([(0, campana(f, larga: 1.6)), (0.05, campana(f * 1.26, larga: 1.5)), (0.1, campana(f * 1.5, larga: 1.4)), (0.16, campana(f * 2, larga: 1.2))])
        case .gota: return mezcla([(0, plic(620 * k))])
        case .lumen: return mezcla([(0, hu(330 * k))])
        case .bloqueo: return mezcla([(0, kalimba(175 * k))])
        case .permiso: return mezcla([(0, kalimba(247 * k)), (0.24, kalimba(220 * k))])
        case .claude: return mezcla([(0, campana(660 * k, larga: 0.8))])
        case .nido: return mezcla([(0, roce()), (0.09, plic(560 * k))])
        // Cambio de fase al respirar: una nota de kalimba muy grave, casi un roce.
        case .respira: return mezcla([(0, kalimba(196 * k))]).map { $0 * 0.6 }
        case .tienda: return mezcla([(0, campana(740 * k, larga: 0.7)), (0.08, campana(988 * k, larga: 0.5))])
        // Scriptorium: dos trazos de pluma muy bajos. Cada variante sale con su propio ruido: cuatro plumas distintas que se alternan.
        case .pluma: return mezcla([(0, pluma(tau: 0.07)), (0.2 + 0.03 * s / 3, pluma(tau: 0.05))]).map { $0 * 0.35 }
        }
    }

    static func wav(_ x: [Double]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(x.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for v in x { u16(UInt16(bitPattern: Int16(max(-1, min(1, v)) * 32767))) }
        return d
    }

    private static var cache: [String: NSSound] = [:]
    private static var ultima: [Evento: Int] = [:]

    // Una vez y sin repetir la variante anterior.
    static func tocar(_ e: Evento) {
        guard let vol = ajuste(e) else { return }
        var i = Int.random(in: 0..<variantes.count)
        if i == ultima[e] { i = (i + 1) % variantes.count }
        ultima[e] = i
        let clave = "\(e.rawValue)-\(i)"
        let s = cache[clave] ?? NSSound(data: wav(muestras(e, semitonos: variantes[i])))
        cache[clave] = s
        s?.volume = vol
        s?.play()
    }

    // Embery --exportar-sonidos <carpeta>: un WAV por evento con sus cuatro variantes seguidas, para escucharlos.
    static func exportar(_ carpeta: String) {
        let dir = URL(fileURLWithPath: carpeta)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pausa = [Double](repeating: 0, count: Int(sr * 0.7))
        for (n, e) in Evento.allCases.enumerated() {
            let todo = variantes.flatMap { muestras(e, semitonos: $0) + pausa }
            try? wav(todo).write(to: dir.appendingPathComponent(String(format: "%02d-%@.wav", n + 1, e.rawValue)))
        }
        Paisajes.exportar(dir)
    }
}
