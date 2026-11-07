import Foundation

enum Modo: String, Codable, CaseIterable { case temporizador, cronometro, app }

struct Sesion: Codable, Identifiable {
    var id = UUID()
    var inicio: Date
    var fin: Date
    var modo: Modo
    var segundos: Double
    var pausas: Int
    var tarea: String
    var app: String?
    var appID: String?
    var bloqueos: Int
    var registrada = false
    var proyecto: String?   // carpeta abierta en el editor al empezar
    var nota: String?       // la línea de «¿Qué has hecho?»
    var minutos: Int { Int(segundos / 60) }
    var destellos: Int { minutos }
}

struct Bloqueado: Codable, Identifiable, Hashable {
    var id: String { app ?? web ?? nombre }
    var nombre: String
    var app: String?   // bundle id
    var web: String?   // dominio
}

struct Compra: Codable { var articulo: String; var fecha: Date }

struct Ajustes: Codable {
    var lado = "der"
    var abrirAlIniciar = false   // se enciende en Ajustes; antes se activaba solo en el primer arranque
    var espirituEscritorio = true
    var seguirHora = true
    var objetivoMin = 180
    var duracionMin = 50
    var descansoMin = 10
    var rondas = 2
    var tarea = String(localized: "Programación")
    var bloquear = true
    var boveda = ""
    var carpetaSesiones = "embery"
    var lineaDiaria = true
    var notaSesion = true
    // Opcionales: un datos.json anterior no los trae y no debe darse por roto.
    var sonido: Bool?
    var volumen: Double?
    var silencioFoco: Bool?
    var hueco: Bool?
    var hiloAliento: Bool?
    var consultarUso: Bool?   // preguntar los límites a Claude (Haiku) cuando no llegan solos; de serie, no
    var esconderCompleta: Bool?
    var borde: String?   // "rama" (de serie) o "lateral": el notch lateral con mirada
    var pantalla: String?   // UUID de la pantalla elegida; nil = automática
    var claudeCode: Bool?   // integración con Claude Code en el Hueco; nil = sí
    // Módulos (Ajustes → Módulos); nil = lo de serie de cada uno.
    var modulos: [String: Bool]?
    var pestanaHueco: String?
    var capturaDestino: String?   // "boveda" (de serie), "carpeta" o "notas"
    var capturaCarpeta: String?
    var respirarAntes: Bool?
    var respiracion: String?
    var paisaje: String?
    var paisajeVolumen: Double?
    var paisajeConFoco: Bool?
    var scriptoriumAbierto: Bool?   // el Scriptorium en el Hueco; nil = cerrado
    var archivoEnTarjeta: Bool?     // la tarjeta de una mesa dice qué archivo lee o escribe
    var sonidoScriptorium: Bool?    // la pluma al empezar a escribir; nil = apagado
    var atajoNota: AtajoTeclas?     // nil = ⌃⌥N
    // Integraciones (v5). Todo opcional: nil = lo de serie.
    var obsidian: Bool?             // nil = sí si hay bóveda
    var carpetaEntrada: String?     // relativa a la bóveda; de serie "inbox"
    var plantillaSesion: String?    // relativa a la bóveda; nil = Registro.nota
    var notaDiaria: String?         // patrón con {fecha} = yyyy-MM-dd
    var jornadaClaude: Bool?
    var terminalClaude: String?     // "terminal" (de serie), "iterm" o "app"
    var permisoEnFoco: Bool?        // nil = callar y contar en «Te esperan»
    var vscode: Bool?
    var cursor: Bool?               // Cursor además de VS Code en Proyectos recientes
    var etiquetarProyecto: Bool?
    var avisarCommit: Bool?
    var preguntarAlTerminar: Bool?  // cierre de foco
    var conversacionesHueco: Bool?  // Integraciones › Claude Code › Conversaciones en el Hueco
    var bienvenidaVista: Bool?      // nil = instalación nueva: sale la bienvenida

    var entrada: String { carpetaEntrada ?? "inbox" }
    var patronDiaria: String { notaDiaria ?? String(localized: "daily-notes/{fecha}.md") }
    var registrar: Bool { !boveda.isEmpty && (obsidian ?? true) }
}

struct Datos: Codable {
    var sesiones: [Sesion] = []
    var compras: [Compra] = []
    var bloqueos: [Bloqueado] = [
        Bloqueado(nombre: "Instagram", web: "instagram.com"), Bloqueado(nombre: "TikTok", web: "tiktok.com"),
        Bloqueado(nombre: "YouTube", web: "youtube.com"), Bloqueado(nombre: "x.com", web: "x.com"),
    ]
    var ajustes = Ajustes()
    var tres: Tres?
    var capturas: [Captura]?   // las que esperan a que la bóveda o la carpeta estén
}

struct Articulo { let clave, nombre, efecto: String; let precio: Int; let mueble: Bool }
let TIENDA = [
    Articulo(clave: "luciernagas", nombre: String(localized: "Luciérnagas en frasco"), efecto: String(localized: "+30% de luz"), precio: 20, mueble: false),
    Articulo(clave: "musgo", nombre: String(localized: "Musgo blando"), efecto: String(localized: "+40% de sueño"), precio: 15, mueble: false),
    Articulo(clave: "nido", nombre: String(localized: "Nido de ramitas"), efecto: String(localized: "Mueble · cama"), precio: 60, mueble: true),
    Articulo(clave: "seta", nombre: String(localized: "Setas de luz"), efecto: String(localized: "Mueble · brillan de noche"), precio: 45, mueble: true),
    Articulo(clave: "campanilla", nombre: String(localized: "Campanilla de cristal"), efecto: String(localized: "Mueble · se mece con el viento"), precio: 80, mueble: true),
    Articulo(clave: "farolillo", nombre: String(localized: "Farolillo de papel"), efecto: String(localized: "Mueble · luz"), precio: 90, mueble: true),
    Articulo(clave: "guirnalda", nombre: String(localized: "Guirnalda de luz"), efecto: String(localized: "Mueble · bajo la rama"), precio: 120, mueble: true),
]

// Estadísticas que salen de las sesiones; nada de esto se guarda aparte.
struct Cuentas {
    let datos: Datos
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; c.locale = Locale(identifier: "es_ES"); return c }()
    var hoy = Date()

    func minutos(_ dia: Date) -> Double {
        datos.sesiones.filter { cal.isDate($0.fin, inSameDayAs: dia) }.reduce(0) { $0 + $1.segundos } / 60
    }
    func sesiones(_ dia: Date) -> [Sesion] { datos.sesiones.filter { cal.isDate($0.fin, inSameDayAs: dia) } }
    var hoyMin: Double { minutos(hoy) }
    var ayerMin: Double { minutos(cal.date(byAdding: .day, value: -1, to: hoy)!) }
    var horasLuz: Double { datos.sesiones.reduce(0) { $0 + $1.segundos } / 3600 }
    var saldo: Int {
        datos.sesiones.reduce(0) { $0 + $1.destellos } - datos.compras.reduce(0) { s, c in s + (TIENDA.first { $0.clave == c.articulo }?.precio ?? 0) }
    }
    // Días seguidos con alguna sesión, contando desde hoy (o desde ayer si hoy aún no hay ninguna).
    var racha: Int {
        var dia = cal.startOfDay(for: hoy), n = 0
        if minutos(dia) == 0 { dia = cal.date(byAdding: .day, value: -1, to: dia)! }
        while !sesiones(dia).isEmpty { n += 1; dia = cal.date(byAdding: .day, value: -1, to: dia)! }
        return n
    }
    var diasSinFoco: Int {
        guard let ultima = datos.sesiones.map(\.fin).max() else { return 0 }
        return cal.dateComponents([.day], from: cal.startOfDay(for: ultima), to: cal.startOfDay(for: hoy)).day ?? 0
    }
    // Lunes a domingo de esta semana.
    var semana: [Date] {
        let lunes = cal.dateInterval(of: .weekOfYear, for: hoy)!.start
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: lunes)! }
    }
    // Minutos por proyecto en esos días, de más a menos. Pasados cinco, el resto se suma a «Sin proyecto» (nil).
    // Sin ninguna sesión con proyecto no hay nada que enseñar.
    func porProyecto(_ dias: [Date]) -> [(nombre: String?, minutos: Double)] {
        var t: [String?: Double] = [:]
        for s in datos.sesiones where dias.contains(where: { cal.isDate(s.fin, inSameDayAs: $0) }) { t[s.proyecto, default: 0] += s.segundos / 60 }
        var con = t.compactMap { k, v in k.map { (nombre: Optional($0), minutos: v) } }.sorted { $0.minutos > $1.minutos }
        guard !con.isEmpty else { return [] }
        var sin = t[nil] ?? 0
        if con.count > 5 { sin += con[5...].reduce(0) { $0 + $1.minutos }; con = Array(con.prefix(5)) }
        return sin > 0 ? con + [(nil, sin)] : con
    }
    func compradoHoy(_ clave: String) -> Bool { datos.compras.contains { $0.articulo == clave && cal.isDate($0.fecha, inSameDayAs: hoy) } }
    func tiene(_ clave: String) -> Bool { datos.compras.contains { $0.articulo == clave } }
}

enum Almacen {
    static var url: URL {
        let dir = URL(fileURLWithPath: EMBERY_DIR, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("datos.json")
    }
    static func cargar() -> Datos {
        guard let d = try? Data(contentsOf: url) else { return Datos() }
        do { return try leer(d) } catch {
            // Un archivo que no se lee no se pisa: se aparta con fecha antes de empezar de cero.
            try? FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("datos-roto-\(Int(Date().timeIntervalSince1970)).json"))
            return Datos()
        }
    }
    // Quien ya tenía datos.json de antes de la bienvenida no la ve: solo sale en una instalación nueva.
    static func leer(_ d: Data) throws -> Datos {
        var datos = try decodificador.decode(Datos.self, from: d)
        if datos.ajustes.bienvenidaVista == nil { datos.ajustes.bienvenidaVista = true }
        return datos
    }
    static func guardar(_ datos: Datos) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(datos).write(to: url, options: .atomic)
    }
    // El foco en marcha se apunta aparte cada 30 s: si Embery cae, al volver se cierra como sesión hasta ese momento.
    private static var urlEnCurso: URL { url.deletingLastPathComponent().appendingPathComponent("en-curso.json") }
    static func guardarEnCurso(_ s: Sesion?) {
        guard let s else { try? FileManager.default.removeItem(at: urlEnCurso); return }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? e.encode(s).write(to: urlEnCurso, options: .atomic)
    }
    static func enCurso() -> Sesion? {
        guard let d = try? Data(contentsOf: urlEnCurso) else { return nil }
        return try? decodificador.decode(Sesion.self, from: d)
    }
    private static var decodificador: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
