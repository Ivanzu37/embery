import AppKit

// La bóveda de Markdown elegida en Ajustes: nota diaria con sus casillas, notas recientes y abrir en Obsidian.
// La Nota rápida la escribe Capturas en la carpeta de entrada.

enum Boveda {
    struct Casilla: Equatable { var linea: Int; var texto: String; var hecha: Bool }
    struct Reciente: Equatable { var url: URL; var fecha: Date; var carpeta: String }

    // Con el disco fuera, la carpeta no cuenta: crear algo dentro lo dejaría en el disco del Mac.
    static func disponible(_ raiz: String) -> Bool {
        guard !raiz.isEmpty else { return false }
        if let v = Vault.volumen(de: raiz), !Vault.mounted(v) { return false }
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: raiz, isDirectory: &dir) && dir.boolValue
    }

    // Una bóveda tiene .obsidian/ o la carpeta de sus notas diarias. Si no, se busca hacia arriba la que lo sea:
    // elegir una subcarpeta (inbox/, por ejemplo) es el despiste típico. nil: es una bóveda o no hay ninguna encima.
    static func sugerencia(para raiz: URL, patronDiaria: String) -> URL? {
        let fm = FileManager.default, diarias = patronDiaria.split(separator: "/").dropLast().joined(separator: "/")
        func esBoveda(_ u: URL) -> Bool {
            fm.fileExists(atPath: u.appendingPathComponent(".obsidian").path) || (!diarias.isEmpty && fm.fileExists(atPath: u.appendingPathComponent(diarias).path))
        }
        guard !esBoveda(raiz) else { return nil }
        var u = raiz.deletingLastPathComponent()
        while u.path != "/" && u.pathComponents.count > 1 {
            if esBoveda(u) { return u }
            u = u.deletingLastPathComponent()
        }
        return raiz
    }

    static func diaria(_ a: Ajustes, _ d: Date = Date()) -> URL? {
        guard !a.boveda.isEmpty else { return nil }
        let dia = Registro.fecha(d, "yyyy-MM-dd")
        let rel = a.patronDiaria.replacingOccurrences(of: "{fecha}", with: dia).replacingOccurrences(of: "{date}", with: dia)
        return URL(fileURLWithPath: a.boveda, isDirectory: true).appendingPathComponent(rel)
    }

    // MARK: casillas «- [ ]» / «- [x]»

    private static func partir(_ l: String) -> (prefijo: String, hecha: Bool, texto: String)? {
        let sangria = l.prefix { $0 == " " || $0 == "\t" }
        let resto = l.dropFirst(sangria.count)
        guard resto.count >= 5, "-*+".contains(resto.first!), resto.dropFirst().hasPrefix(" ["),
              resto.dropFirst(4).first == "]" else { return nil }
        let marca = resto.dropFirst(3).first!
        guard marca == " " || marca == "x" || marca == "X" else { return nil }
        let texto = resto.dropFirst(5).trimmingCharacters(in: .whitespaces)
        return (String(l.prefix(sangria.count + 3)), marca != " ", texto)
    }

    static func casillas(_ texto: String) -> [Casilla] {
        texto.components(separatedBy: "\n").enumerated().compactMap { i, l in
            partir(l).flatMap { $0.texto.isEmpty ? nil : Casilla(linea: i, texto: $0.texto, hecha: $0.hecha) }
        }
    }

    // Solo cambia la marca de esa línea. Si el archivo se movió desde la lectura, busca la casilla por su texto.
    static func marcar(_ c: Casilla, _ hecha: Bool, en texto: String) -> String? {
        var lineas = texto.components(separatedBy: "\n")
        let igual: (Int) -> Bool = { i in partir(lineas[i])?.texto == c.texto }
        guard let i = (c.linea < lineas.count && igual(c.linea)) ? c.linea : lineas.indices.first(where: igual),
              let p = partir(lineas[i]) else { return nil }
        let sinMarca = lineas[i].dropFirst(p.prefijo.count + 1)
        lineas[i] = p.prefijo + (hecha ? "x" : " ") + sinMarca
        return lineas.joined(separator: "\n")
    }

    // Detrás de la última casilla; sin casillas, al final del archivo.
    static func anadir(_ tarea: String, en texto: String) -> String {
        var lineas = texto.components(separatedBy: "\n")
        let nueva = "- [ ] " + tarea.replacingOccurrences(of: "\n", with: " ")
        if let ultima = lineas.indices.last(where: { partir(lineas[$0]) != nil }) {
            lineas.insert(nueva, at: ultima + 1)
        } else {
            while lineas.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lineas.removeLast() }
            lineas += [nueva, ""]
        }
        return lineas.joined(separator: "\n")
    }

    static func leerCasillas(_ a: Ajustes, _ d: Date = Date()) -> [Casilla]? {
        guard disponible(a.boveda), let u = diaria(a, d), let t = try? String(contentsOf: u, encoding: .utf8) else { return nil }
        return casillas(t)
    }

    @discardableResult
    static func marcar(_ c: Casilla, _ hecha: Bool, _ a: Ajustes, _ d: Date = Date()) -> Bool {
        guard disponible(a.boveda), let u = diaria(a, d), let t = try? String(contentsOf: u, encoding: .utf8),
              let nuevo = marcar(c, hecha, en: t) else { return false }
        return (try? nuevo.write(to: u, atomically: true, encoding: .utf8)) != nil
    }

    @discardableResult
    static func anadir(_ tarea: String, _ a: Ajustes, _ d: Date = Date()) -> Bool {
        let t = tarea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, disponible(a.boveda), let u = diaria(a, d), let texto = try? String(contentsOf: u, encoding: .utf8) else { return false }
        return (try? anadir(t, en: texto).write(to: u, atomically: true, encoding: .utf8)) != nil
    }

    // MARK: notas recientes

    static func recientes(_ raiz: String, cuantas: Int = 5) -> [Reciente] {
        guard disponible(raiz) else { return [] }
        let base = URL(fileURLWithPath: raiz, isDirectory: true).resolvingSymlinksInPath()
        let claves: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: claves, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var notas: [Reciente] = []
        for case let u as URL in e {
            let v = try? u.resourceValues(forKeys: Set(claves))
            if v?.isDirectory == true {
                if u.lastPathComponent == "templates" { e.skipDescendants() }
                continue
            }
            guard u.pathExtension == "md", let f = v?.contentModificationDate else { continue }
            let rel = u.resolvingSymlinksInPath().deletingLastPathComponent().path.dropFirst(base.path.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            notas.append(Reciente(url: u, fecha: f, carpeta: rel))
        }
        return Array(notas.sorted { $0.fecha > $1.fecha }.prefix(cuantas))
    }

    // MARK: abrir

    static func urlObsidian(_ archivo: URL) -> URL? {
        var c = URLComponents(); c.scheme = "obsidian"; c.host = "open"
        c.queryItems = [URLQueryItem(name: "path", value: archivo.path)]
        return c.url
    }

    // Sin Obsidian, el archivo se abre con la app por defecto.
    static func abrir(_ archivo: URL) {
        if let u = urlObsidian(archivo), NSWorkspace.shared.urlForApplication(toOpen: u) != nil, NSWorkspace.shared.open(u) { return }
        NSWorkspace.shared.open(archivo)
    }
}
