import AppKit

// Módulos de Embery: cada función se enciende en Ajustes → Módulos y vive en una pestaña del Hueco.
// Los seis primeros vienen encendidos de serie; el resto se descubre en Ajustes.

enum Modulo: String, CaseIterable {
    case captura, tres, notas, siguiente, respirar, pausa, paisajes, canto, scriptorium
    case vscode   // Proyectos recientes en el Hueco; se gobierna desde Ajustes › Integraciones › VS Code

    var nombre: String {
        switch self {
        case .captura: String(localized: "Nota rápida")
        case .tres: String(localized: "Pendientes de hoy")
        case .notas: String(localized: "Notas recientes")
        case .vscode: String(localized: "Proyectos recientes en el Hueco")
        case .siguiente: String(localized: "Lo siguiente")
        case .respirar: String(localized: "Respiraciones")
        case .pausa: String(localized: "Pausa de verdad")
        case .paisajes: String(localized: "Paisajes sonoros")
        case .canto: String(localized: "Canto")
        case .scriptorium: "Scriptorium"
        }
    }
    var sub: String {
        switch self {
        case .captura: String(localized: "Apunta una idea sin salir de lo que haces")
        case .tres: String(localized: "Las casillas de tu nota diaria, o una lista en la app")
        case .notas: String(localized: "Las últimas notas que has tocado en la bóveda")
        case .vscode: ""
        case .siguiente: String(localized: "Tu próximo evento del Calendario")
        case .respirar: String(localized: "Caja, 4-7-8 y suspiro, guiadas por la luz")
        case .pausa: String(localized: "En el descanso, levántate; si vuelves antes, Lumen duerme")
        case .paisajes: String(localized: "Lluvia, bosque, mar, chimenea y ruido de color")
        case .canto: String(localized: "Lo que suena en Música o Spotify, con su espectro")
        case .scriptorium: String(localized: "Claude trabajando en una sala bajo el notch")
        }
    }
    var deSerie: Bool { self != .canto && self != .scriptorium }
}

struct Tres: Codable, Equatable {
    struct Item: Codable, Equatable { var texto = ""; var hecha = false }
    var dia: String
    var items = [Item(), Item(), Item()]
}

struct Captura: Codable, Equatable { var texto: String; var fecha: Date }

extension Embery {
    // El Scriptorium sigue en su ajuste de siempre, el mismo que abre y cierra el botón del Hueco.
    func activo(_ m: Modulo) -> Bool {
        if m == .scriptorium { return ajustes.scriptoriumAbierto ?? false }
        return ajustes.modulos?[m.rawValue] ?? (m == .notas ? !ajustes.boveda.isEmpty : m.deSerie)
    }
    func activar(_ m: Modulo, _ si: Bool) {
        if m == .scriptorium { ajustes.scriptoriumAbierto = si; return }
        var d = ajustes.modulos ?? [:]; d[m.rawValue] = si; ajustes.modulos = d
    }

    // Pendientes de hoy en la app (lo que fue «Tres de hoy»): cada día empiezan en blanco.
    var tresHoy: Tres {
        let hoy = Registro.fecha(ahora, "yyyy-MM-dd")
        return datos.tres?.dia == hoy ? datos.tres! : Tres(dia: hoy)
    }
    func cambiarTres(_ i: Int, _ cambio: (inout Tres.Item) -> Void) {
        var t = tresHoy
        cambio(&t.items[i])
        datos.tres = t
    }
    // Pendientes en la app (sin nota diaria): ocupa una línea vacía de las tres de antes o va al final.
    func anadirPendiente(_ texto: String) {
        var t = tresHoy
        if let i = t.items.firstIndex(where: { $0.texto.isEmpty }) { t.items[i].texto = texto } else { t.items.append(.init(texto: texto)) }
        datos.tres = t
    }

    // Captura rápida: se escribe fuera del hilo principal; si el destino no está (disco fuera), espera en cola.
    func capturar(_ texto: String) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        datos.capturas = (datos.capturas ?? []) + [Captura(texto: t, fecha: Date())]
        escribirCapturas()
    }
    func escribirCapturas() {
        let pendientes = datos.capturas ?? [], a = ajustes
        guard !pendientes.isEmpty, !Capturas.ocupado else { return }
        Capturas.ocupado = true
        DispatchQueue.global(qos: .utility).async {
            let hechas = pendientes.prefix { Capturas.escribir($0, a) }
            DispatchQueue.main.async {
                Capturas.ocupado = false
                self.datos.capturas = (self.datos.capturas ?? []).filter { !hechas.contains($0) }
                // Si entró otra mientras se escribía, va detrás.
                if hechas.count == pendientes.count, !(self.datos.capturas ?? []).isEmpty { self.escribirCapturas() }
            }
        }
    }
}

enum Capturas {
    static var ocupado = false   // solo en el hilo principal
    static func escribir(_ c: Captura, _ a: Ajustes) -> Bool {
        switch a.capturaDestino ?? "boveda" {
        case "notas": return notas(c)
        case "carpeta":
            guard let dir = a.capturaCarpeta else { return false }
            return guardar("# \(titulo(c.texto))\n\n\(c.texto)\n", en: dir, c)
        default:
            guard !a.boveda.isEmpty else { return false }
            let dir = (a.boveda as NSString).appendingPathComponent(a.entrada)
            return guardar(nota(c, plantilla: try? String(contentsOfFile: (a.boveda as NSString).appendingPathComponent("templates/nota.md"), encoding: .utf8)), en: dir, c)
        }
    }

    static func titulo(_ t: String) -> String {
        let primera = t.components(separatedBy: .newlines).first ?? t
        return primera.count > 60 ? String(primera.prefix(60)) + "…" : primera
    }
    // Nombre en minúsculas con guiones, con la fecha delante para que no choquen.
    static func archivo(_ c: Captura) -> String {
        let base = titulo(c.texto).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")).lowercased()
        let slug = base.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").prefix(8).joined(separator: "-")
        return "\(Registro.fecha(c.fecha, "yyyy-MM-dd-HHmmss"))-\(slug.isEmpty ? "captura" : slug).md"
    }

    // Con la plantilla «nota» de la bóveda si la hay: fecha, título, el texto tras el título y el tag #idea.
    static func nota(_ c: Captura, plantilla: String?) -> String {
        let dia = Registro.fecha(c.fecha, "yyyy-MM-dd"), t = titulo(c.texto)
        guard let p = plantilla else { return "---\ntags: [nota, idea]\ncreated: \(dia)\n---\n# \(t)\n\n\(c.texto)\n" }
        var lineas = p.replacingOccurrences(of: "{{date}}", with: dia).replacingOccurrences(of: "{{title}}", with: t)
            .components(separatedBy: "\n")
            // Las líneas de ayuda de la plantilla, entre paréntesis, sobran.
            .filter { !($0.hasPrefix("(") && $0.hasSuffix(")")) }
        if let i = lineas.firstIndex(where: { $0.hasPrefix("tags: [") }), !lineas[i].contains("idea") {
            lineas[i] = lineas[i].replacingOccurrences(of: "]", with: ", idea]")
        }
        let h1 = lineas.firstIndex { $0.hasPrefix("# ") } ?? lineas.count - 1
        lineas.insert(contentsOf: ["", c.texto], at: min(h1 + 1, lineas.count))
        return lineas.joined(separator: "\n")
    }

    private static func guardar(_ texto: String, en dir: String, _ c: Captura) -> Bool {
        // Con el disco fuera, crear la carpeta la dejaría en el disco del Mac, bajo /Volumes.
        if let v = Vault.volumen(de: dir), !Vault.mounted(v) { return false }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (try? texto.write(toFile: (dir as NSString).appendingPathComponent(archivo(c)), atomically: true, encoding: .utf8)) != nil
    }

    private static func notas(_ c: Captura) -> Bool {
        let cuerpo = c.texto.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "<br>")
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Notes\" to make new note with properties {body:\"\(cuerpo)\"}")?.executeAndReturnError(&error)
        return error == nil
    }
}

extension Embery {
    // Tocar el que suena lo apaga; tocar otro cambia a ese y lo recuerda para el foco.
    func alternarPaisaje(_ clave: String) {
        paisajePorFoco = false
        if paisajeSonando == clave { paisajes.apagar(); paisajeSonando = nil; return }
        ajustes.paisaje = clave
        paisajes.tocar(clave, volumen: ajustes.paisajeVolumen ?? 0.5)
        paisajeSonando = clave
    }
}
