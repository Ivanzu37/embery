import Foundation

// El idioma en que se ve la app (el del Mac o el elegido en Ajustes): fechas y días de la semana van con él.
let LOCALE = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "es")

// Registro en la bóveda: una línea en la sección «📓 Registro» de la nota diaria y una nota por sesión.

enum Registro {
    static func fecha(_ d: Date, _ formato: String) -> String {
        let f = DateFormatter(); f.locale = LOCALE; f.dateFormat = formato; return f.string(from: d)
    }
    static func nombreNota(_ s: Sesion) -> String { "\(fecha(s.inicio, "yyyy-MM-dd-HHmm"))-foco" }

    static func linea(_ s: Sesion, enlace: String?) -> String {
        var l = "- \(fecha(s.inicio, "HH:mm"))–\(fecha(s.fin, "HH:mm")) · " + String(localized: "foco \(s.minutos) min", table: "Notas")
        if let p = s.proyecto { l += " · \(p)" }
        l += " · ✦ \(s.destellos)"
        if let n = s.nota { l += " · \(n)" }
        if let enlace { l += " · [[\(enlace)]]" }
        return l
    }

    // Mete la línea en la sección Registro: ocupa el «- » vacío de la plantilla o va detrás de la última línea con texto.
    static func insertar(_ linea: String, en texto: String) -> String {
        var lineas = texto.components(separatedBy: "\n")
        let seccion = String(localized: "Registro", table: "Notas"), relacionado = String(localized: "Relacionado", table: "Notas")
        guard let cab = lineas.firstIndex(where: { $0.hasPrefix("## ") && $0.contains(seccion) }) else {
            let antes = lineas.firstIndex { $0.hasPrefix("## ") && $0.contains(relacionado) } ?? lineas.count
            lineas.insert(contentsOf: ["## 📓 \(seccion)", linea, ""], at: antes)
            return lineas.joined(separator: "\n")
        }
        let fin = lineas[(cab + 1)...].firstIndex { $0.hasPrefix("## ") } ?? lineas.count
        if let vacia = lineas[(cab + 1)..<fin].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "-" }) {
            lineas[vacia] = linea
        } else {
            let ultima = lineas[(cab + 1)..<fin].lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? cab
            lineas.insert(linea, at: ultima + 1)
        }
        return lineas.joined(separator: "\n")
    }

    // Una plantilla propia (Integraciones › Obsidian › Plantilla de la nota) con sus huecos {{…}}.
    // En el frontmatter el texto va entre comillas de YAML y una línea «clave: {{hueco}}» vacía desaparece;
    // en el cuerpo, una línea que solo era un hueco vacío también.
    static func nota(_ s: Sesion, plantilla: String) -> String {
        let huecos = ["fecha": fecha(s.inicio, "yyyy-MM-dd"), "inicio": fecha(s.inicio, "HH:mm"), "fin": fecha(s.fin, "HH:mm"),
                      "minutos": "\(s.minutos)", "tarea": s.tarea, "proyecto": s.proyecto ?? "", "nota": s.nota ?? "",
                      "destellos": "\(s.destellos)", "modo": s.modo.rawValue, "pausas": "\(s.pausas)", "bloqueos": "\(s.bloqueos)",
                      "app": s.app ?? "", "resumen": resumen(s)]
        let texto = ["tarea", "proyecto", "nota", "app", "resumen"]
        var lineas = plantilla.components(separatedBy: "\n"), enFM = lineas.first == "---"
        for i in lineas.indices {
            if i > 0, lineas[i] == "---" { enFM = false; continue }
            let original = lineas[i]
            for (k, v) in huecos {
                if enFM, texto.contains(k) {
                    lineas[i] = lineas[i].replacingOccurrences(of: "\"{{\(k)}}\"", with: "{{\(k)}}")
                        .replacingOccurrences(of: "{{\(k)}}", with: v.isEmpty ? "" : yaml(v))
                } else {
                    lineas[i] = lineas[i].replacingOccurrences(of: "{{\(k)}}", with: v)
                }
            }
            let quitada = lineas[i] != original && lineas[i].trimmingCharacters(in: .whitespaces).isEmpty
            let claveVacia = enFM && original.contains("{{") && lineas[i].trimmingCharacters(in: .whitespaces).hasSuffix(":")
            if quitada || claveVacia { lineas[i] = "\u{0}" }
        }
        return lineas.filter { $0 != "\u{0}" }.joined(separator: "\n")
    }
    // Comillas de YAML: el texto de «qué has hecho» puede traer dos puntos o almohadillas.
    static func yaml(_ t: String) -> String { "\"" + t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

    // «50 min de foco en «Programación» en Xcode, con temporizador. 1 pausa, 2 distracciones bloqueadas, ✦ 50.»
    static func resumen(_ s: Sesion) -> String {
        let modo = switch s.modo {
            case .temporizador: String(localized: "temporizador", table: "Notas")
            case .cronometro: String(localized: "cronómetro", table: "Notas")
            case .app: String(localized: "modo App", table: "Notas")
        }
        let donde = s.app.map { String(localized: " en \($0)", table: "Notas") } ?? ""
        let pausas = s.pausas == 1 ? String(localized: "1 pausa", table: "Notas") : String(localized: "\(s.pausas) pausas", table: "Notas")
        let bloqueos = s.bloqueos == 1 ? String(localized: "1 distracción bloqueada", table: "Notas")
            : String(localized: "\(s.bloqueos) distracciones bloqueadas", table: "Notas")
        return String(localized: "\(s.minutos) min de foco en «\(s.tarea)»", table: "Notas") + donde
            + String(localized: ", con \(modo).", table: "Notas") + " \(pausas), \(bloqueos), ✦ \(s.destellos)."
    }

    // La nota de serie, neutra: quien quiera la suya la hace con la plantilla y estos mismos huecos.
    static let plantillaDeSerie: String = {
        let foco = String(localized: "foco", table: "Notas"), titulo = String(localized: "Foco", table: "Notas")
        return """
        ---
        tags: [\(foco)]
        created: {{fecha}}
        start: {{fecha}}T{{inicio}}
        end: {{fecha}}T{{fin}}
        mode: {{modo}}
        minutes: {{minutos}}
        pauses: {{pausas}}
        sparks: {{destellos}}
        task: {{tarea}}
        app: {{app}}
        project: {{proyecto}}
        note: {{nota}}
        blocked: {{bloqueos}}
        ---
        # \(titulo) {{fecha}} {{inicio}}

        {{nota}}

        {{resumen}}

        ## 🔗 \(String(localized: "Relacionado", table: "Notas"))
        - [[{{fecha}}]]
        """
    }()
    static func nota(_ s: Sesion) -> String { nota(s, plantilla: plantillaDeSerie) }

    // Devuelve false si la bóveda no está (disco sin montar): la sesión queda pendiente y se reintenta más tarde.
    static func escribir(_ s: Sesion, _ a: Ajustes) -> Bool {
        if a.obsidian == false { return true }   // integración apagada: no se registra ni queda pendiente
        guard Boveda.disponible(a.boveda), let diaria = Boveda.diaria(a, s.inicio) else { return false }
        let fm = FileManager.default, raiz = URL(fileURLWithPath: a.boveda, isDirectory: true)
        do {
            var enlace: String?
            if a.notaSesion {
                let dir = raiz.appendingPathComponent(a.carpetaSesiones, isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                var nombre = nombreNota(s), n = 2
                while fm.fileExists(atPath: dir.appendingPathComponent("\(nombre).md").path) { nombre = "\(nombreNota(s))-\(n)"; n += 1 }
                let propia = a.plantillaSesion.flatMap { try? String(contentsOf: raiz.appendingPathComponent($0), encoding: .utf8) }
                try (propia.map { nota(s, plantilla: $0) } ?? nota(s)).write(to: dir.appendingPathComponent("\(nombre).md"), atomically: true, encoding: .utf8)
                enlace = nombre
            }
            if a.lineaDiaria {
                let dia = fecha(s.inicio, "yyyy-MM-dd"), url = diaria
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let l = linea(s, enlace: enlace)
                // Si la nota existe, solo se toca si se ha podido leer: nunca se rehace desde la plantilla encima.
                if fm.fileExists(atPath: url.path) { return Boveda.reescribir(url) { insertar(l, en: $0) } }
                let texto: String
                if let plantilla = try? String(contentsOf: raiz.appendingPathComponent("templates/daily-note.md"), encoding: .utf8) {
                    texto = plantilla.replacingOccurrences(of: "{{date}}", with: dia)
                } else { texto = "---\ntags: [daily]\ncreated: \(dia)\n---\n# \(dia)\n\n## 📓 \(String(localized: "Registro", table: "Notas"))\n- \n" }
                try Data(insertar(l, en: texto).utf8).write(to: url, options: .withoutOverwriting)   // si apareció justo ahora, se reintenta luego
            }
            return true
        } catch {
            NSLog("Embery: no se pudo escribir en la bóveda: \(error)")
            return false
        }
    }
}
