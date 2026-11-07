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
        var l = "- \(fecha(s.inicio, "HH:mm"))–\(fecha(s.fin, "HH:mm")) · foco \(s.minutos) min"
        if let p = s.proyecto { l += " · \(p)" }
        l += " · ✦ \(s.destellos)"
        if let n = s.nota { l += " · \(n)" }
        if let enlace { l += " · [[\(enlace)]]" }
        return l
    }

    // Mete la línea en la sección Registro: ocupa el «- » vacío de la plantilla o va detrás de la última línea con texto.
    static func insertar(_ linea: String, en texto: String) -> String {
        var lineas = texto.components(separatedBy: "\n")
        guard let cab = lineas.firstIndex(where: { $0.hasPrefix("## ") && $0.contains("Registro") }) else {
            let antes = lineas.firstIndex { $0.hasPrefix("## ") && $0.contains("Relacionado") } ?? lineas.count
            lineas.insert(contentsOf: ["## 📓 Registro", linea, ""], at: antes)
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
    static func nota(_ s: Sesion, plantilla: String) -> String {
        let huecos = ["fecha": fecha(s.inicio, "yyyy-MM-dd"), "inicio": fecha(s.inicio, "HH:mm"), "fin": fecha(s.fin, "HH:mm"),
                      "minutos": "\(s.minutos)", "tarea": s.tarea, "proyecto": s.proyecto ?? "", "nota": s.nota ?? "", "destellos": "\(s.destellos)"]
        return huecos.reduce(plantilla) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
    }

    // Comillas de YAML: el texto de «qué has hecho» puede traer dos puntos o almohadillas.
    static func yaml(_ t: String) -> String { "\"" + t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

    static func nota(_ s: Sesion) -> String {
        let dia = fecha(s.inicio, "yyyy-MM-dd")
        var fm = """
        ---
        tags: [nota, tema/foco]
        created: \(dia)
        inicio: \(fecha(s.inicio, "yyyy-MM-dd'T'HH:mm"))
        fin: \(fecha(s.fin, "yyyy-MM-dd'T'HH:mm"))
        modo: \(s.modo.rawValue)
        minutos: \(s.minutos)
        pausas: \(s.pausas)
        destellos: \(s.destellos)
        tarea: \(s.tarea)
        """
        if let app = s.app { fm += "\napp: \(app)" }
        if let p = s.proyecto { fm += "\nproyecto: \(yaml(p))" }
        if let n = s.nota { fm += "\nnota: \(yaml(n))" }
        fm += "\nbloqueos: \(s.bloqueos)\n---\n"
        let modo = ["temporizador": "temporizador", "cronometro": "cronómetro", "app": "modo App"][s.modo.rawValue]!
        let donde = s.app.map { " en \($0)" } ?? ""
        let pausas = s.pausas == 1 ? "1 pausa" : "\(s.pausas) pausas"
        let bloqueos = s.bloqueos == 1 ? "1 distracción bloqueada" : "\(s.bloqueos) distracciones bloqueadas"
        return fm + """
        # Foco \(fecha(s.inicio, "yyyy-MM-dd HH:mm"))

        \(s.nota.map { "\($0)\n\n" } ?? "")\(s.minutos) min de foco en «\(s.tarea)»\(donde), con \(modo). \(pausas), \(bloqueos), ✦ \(s.destellos).

        ## 🔗 Relacionado
        - [[\(dia)]]
        - [[embery]]

        """
    }

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
                var texto: String
                if let t = try? String(contentsOf: url, encoding: .utf8) { texto = t }
                else if let plantilla = try? String(contentsOf: raiz.appendingPathComponent("templates/daily-note.md"), encoding: .utf8) {
                    texto = plantilla.replacingOccurrences(of: "{{date}}", with: dia)
                } else { texto = "---\ntags: [daily]\ncreated: \(dia)\n---\n# \(dia)\n\n## 📓 Registro\n- \n" }
                try insertar(linea(s, enlace: enlace), en: texto).write(to: url, atomically: true, encoding: .utf8)
            }
            return true
        } catch {
            NSLog("Embery: no se pudo escribir en la bóveda: \(error)")
            return false
        }
    }
}
