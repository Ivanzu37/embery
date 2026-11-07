// Embery · el Hueco: une hooks, uso del plan, tokens, Nido, disco, volumen
// y brillo). No lleva reloj propio: avanza con el de la escena (Delegado.paso) y los datos se miran cada segundo.
import Foundation
import Observation

@Observable
final class Hueco {
    enum Vista: Equatable { case reposo, trabajo, permiso, aviso, nivel, hecho, espera, archivo, carpeta, nota, abierto, scriptorium }

    let live = Live()
    let tokens = TokenLedger()
    let nido = Shelf()
    // Raíces es opcional: solo existe si la bóveda vive en un disco externo.
    let raices: Vault?
    let niveles = Levels()

    private(set) var feed = Feed()
    private(set) var estado: EstadoHueco = .reposo
    private(set) var nivel: Level?
    private(set) var archivos: [URL] = []
    private(set) var dias: [String: Int] = [:]
    private(set) var disco = true
    private(set) var gotas = 0
    var abierto = false
    var arrastrando = false
    var arrastrados = 0
    // La carpeta que se arrastra encima (manda el primer elemento) y la zona bajo el cursor: 0 Nido, 1 Claude Code.
    var carpeta: URL?
    var zona = 0
    // Nota rápida (⌃⌥N): el texto se queda hasta la próxima vez si se cierra con esc.
    var nota = false
    var borrador = ""
    // Lo acumulado durante el foco, que sale como «Te esperan» al terminar.
    private(set) var espera: Espera?
    private(set) var avanceFoco: Double?
    private(set) var callando = false
    // La fila de permiso que ya no se puede contestar desde aquí.
    private(set) var yaNoEspera: String?
    var terminal: String?
    @ObservationIgnored var verFoco: () -> Void = {}
    // Tamaño del notch físico (o de la píldora en pantallas sin notch); lo pone la ventana.
    var notch = CGSize(width: 180, height: 32)
    // Ajustes → El Hueco; los copia la app cada medio segundo.
    var visible = true
    var hilo = true
    var consultarUso = false
    private let consulta = ConsultaUso()
    var esconderCompleta = true
    var scriptorium = false
    @ObservationIgnored private var ultimaPluma = Date.distantPast
    // Con un foco en marcha el permiso calla: el hook no espera y Claude Code pregunta en su terminal.
    @ObservationIgnored var callarPermisos = false
    private(set) var actividad: Actividad = .duerme
    private(set) var proyecto = ""
    // Vive aquí para que los monjes sigan donde estaban al cerrar y abrir el panel.
    @ObservationIgnored let sala = Scriptorium()
    private(set) var mesas = 1
    private(set) var fichas: [FichaMesa] = []
    private(set) var resumenSala = ""
    // La mesa cuya tarjeta se ve (al pasar el ratón por la sala) y dónde está, para que el ratón pueda entrar en ella.
    var tarjetaMesa: Int?
    @ObservationIgnored var marcoTarjeta = CGRect.zero

    // Lo que no se dibuja no se observa: estos cambian a cada fotograma o solo los lee la ventana.
    @ObservationIgnored var marco = CGRect.zero
    @ObservationIgnored var marcoPantalla = CGRect.zero
    @ObservationIgnored var sacando = false
    @ObservationIgnored private var server: HookServer?
    @ObservationIgnored private var acumulado = 0.0
    @ObservationIgnored private var segundos = 0
    @ObservationIgnored private var nivelHasta = 0.0
    @ObservationIgnored private var versionTokens = -1
    @ObservationIgnored private var versionNido = -1
    @ObservationIgnored private var ultimo = ""
    @ObservationIgnored private var acumulando = Espera()
    @ObservationIgnored private var enFoco = false
    @ObservationIgnored private var esperaHasta = 0.0

    var vista: Vista {
        if abierto { return .abierto }
        if nota { return .nota }
        if arrastrando { return carpeta != nil ? .carpeta : .archivo }
        if estado == .permiso && !(callando && callarPermisos) { return .permiso }
        if scriptorium && claude { return estado == .aviso ? .aviso : nivel != nil ? .nivel : .scriptorium }
        if estado == .aviso { return .aviso }
        if nivel != nil { return .nivel }
        if espera != nil { return .espera }
        if callando { return .reposo }
        return estado == .hecho ? .hecho : estado == .trabajo ? .trabajo : .reposo
    }
    // Con cuerpo (botones, zonas, campo) pasar el ratón no abre el panel: se abre con un clic en las alas.
    var abrePorEncima: Bool { ![.permiso, .nota, .carpeta].contains(vista) }

    // Lo llama la app cada medio segundo. enMarcha: hay foco (también en pausa); callar: en marcha y sin pausa.
    func seguirFoco(enMarcha: Bool, callar: Bool, avance: Double?) {
        if avance != avanceFoco { avanceFoco = avance }
        if callar != callando { callando = callar; refrescar() }
        if enMarcha == enFoco { return }
        enFoco = enMarcha
        if enMarcha { acumulando = Espera(); espera = nil; return }
        let e = acumulando.alTerminar(enPermiso: Set(live.sessions.values.filter { $0.state == .perm }.map(\.id)))
        acumulando = Espera()
        guard !e.vacia else { return }
        espera = e
        esperaHasta = ProcessInfo.processInfo.systemUptime + 20
        Sonido.tocar(.claude)
    }
    // El ratón entró en «Te esperan»: el panel se abre y el aviso ya ha cumplido.
    func verEspera() { espera = nil }

    func abrirNota() { abierto = false; nota = true }
    func cerrarNota() { nota = false }

    func abrirClaude(_ u: URL) {
        arrastrando = false; carpeta = nil
        Focus.nuevaSesion(en: u, terminal: terminal)
        Sonido.tocar(.nido)
    }

    // EMBERY_VAULT en el entorno cambia el disco vigilado (para probar con una imagen de disco sin expulsar el de verdad).
    // Sin la integración de Claude Code, el Hueco solo lleva los módulos, el volumen y el brillo.
    let claude: Bool
    @ObservationIgnored var escribiendo = false

    init(boveda: String, claude: Bool) {
        self.claude = claude
        let raiz = boveda.isEmpty ? nil : ProcessInfo.processInfo.environment["EMBERY_VAULT"] ?? Vault.volumen(de: boveda)
        raices = raiz.map { Vault(root: $0) }
    }

    func arrancar() {
        if claude {
            server = HookServer { [weak self] p in
                guard let self else { return }
                self.live.handle(p)
                if self.callarPermisos, p["embery_wait"] as? Bool == true, let id = p["session_id"] as? String { self.server?.soltar(id) }
                self.refrescar()
            }
            server?.start()
            live.seedRecent()
            live.refreshFromDesktop()
            tokens.scan()
            consulta.alLimite = { [weak self] o in self?.live.handleRateLimit(o); self?.refrescar() }
        }
        raices?.onChange = { [weak self] presente in self?.discoCambia(presente) }
        niveles.onChange = { [weak self] l in
            guard let self else { return }
            self.nivelHasta = ProcessInfo.processInfo.systemUptime + 1.6
            if l != self.nivel { self.nivel = l }
            self.refrescar()
        }
        niveles.start()
        refrescar()
    }

    // ahora: segundos de reloj continuo (systemUptime), como el resto de Embery.
    func paso(_ dt: Double, ahora: Double) {
        if nivel != nil && ahora > nivelHasta { nivel = nil }
        if espera != nil && ahora > esperaHasta { espera = nil }
        acumulado += dt
        guard acumulado >= 1, claude else { return }
        acumulado = 0
        segundos += 1
        live.prune()
        soltarPermisos()
        if segundos % 30 == 0 { live.refreshFromDesktop(); raices?.check(); nido.prune() }
        if segundos % 300 == 0 { tokens.scan() }
        // sin dato fresco y con Claude Code en uso en la última hora, se pregunta (si el ajuste lo deja)
        if segundos % 60 == 0, consultarUso, live.edadLimites >= ConsultaUso.cada,
           Date().timeIntervalSince(live.lastActivity) < 3600 { consulta.lanza() }
        refrescar()
    }

    // Permitir / Denegar desde el Hueco. false si Claude ya no espera (respondido en la terminal o fuera de plazo).
    @discardableResult
    func responder(_ id: String, permitir: Bool) -> Bool {
        guard server?.responder(id, permitir: permitir) == true else {
            // Respondido en la terminal o fuera de plazo: lo dice 1,6 s y la fila se va.
            yaNoEspera = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self, self.yaNoEspera == id else { return }
                self.yaNoEspera = nil; self.live.descartado(id); self.refrescar()
            }
            return false
        }
        live.resuelto(id); refrescar()
        return true
    }

    // Los que ya no hace falta retener: respondidos en la terminal, en foco (el permiso calla) o fuera de plazo.
    private func soltarPermisos() {
        guard let server else { return }
        for id in server.esperando where callarPermisos || live.sessions[id]?.state != .perm { server.soltar(id) }
        server.soltarViejos()
    }

    func recibir(_ urls: [URL]) {
        arrastrando = false
        if !nido.add(urls).isEmpty { gotas += 1; Sonido.tocar(.nido) }
        refrescar()
    }

    func sacar(_ u: URL) { nido.remove(u); refrescar() }

    private func discoCambia(_ presente: Bool) {
        if !presente, let raices {
            let dentro = live.sessionsInside(raices)
            if dentro > 0 { live.alert(tag: "disco", label: String(localized: "Sin raíces"), value: "fuera", note: dentro == 1 ? String(localized: "\(raices.name) no está montado · 1 conversación dentro") : String(localized: "\(raices.name) no está montado · \(dentro) conversaciones dentro")) }
        }
        refrescar()
    }

    // Solo se asigna lo que cambió: cada asignación vuelve a pintar el Hueco.
    private func refrescar() {
        guard claude else { return }
        let f = live.feed()
        // Un aviso suena una vez: al entrar en permiso y cuando una conversación termina.
        if callando { acumulando.anotar(hecho: f.doneId, permisos: live.sessions.values.filter { $0.state == .perm }.map(\.id)) }
        if !callando, !f.doneId.isEmpty && (f.doneId != feed.doneId || f.doneTime != feed.doneTime) { Sonido.tocar(.claude) }
        if f != feed { feed = f }
        if live.estado != estado {
            if live.estado == .permiso && !callando { Sonido.tocar(.permiso) }
            estado = live.estado
        }
        let sesiones = Array(live.sessions.values)
        let a = Actividad.de(Actividad.principal(sesiones), ahora: Date())
        if a != actividad { actividad = a }
        // La pluma solo con la sala a la vista, y como mucho una cada 4 s aunque escriban varias mesas.
        if sala.sincronizar(sesiones), vista == .scriptorium, !callando, Date().timeIntervalSince(ultimaPluma) > 4 {
            ultimaPluma = Date(); Sonido.tocar(.pluma)
        }
        sala.ponerBloque(feed.block.map { Double($0) / 100 })
        if sala.mesas.count != mesas { mesas = sala.mesas.count }
        let fs = sala.fichas(live.sessions)
        if fs != fichas { fichas = fs }
        let r = resumen(fs)
        if r != resumenSala { resumenSala = r }
        if let i = tarjetaMesa, i >= fs.count { tarjetaMesa = nil }
        if f.project != proyecto { proyecto = f.project }
        if (raices?.present ?? true) != disco { disco = raices?.present ?? true }
        if nido.version != versionNido { versionNido = nido.version; archivos = nido.items }
        if tokens.version != versionTokens { versionTokens = tokens.version; dias = tokens.days }
        volcar()
    }

    // «Scriptorium: 2 conversaciones; Mi bóveda escribe; proyecto-web descansa. Abrir el Hueco»
    private func resumen(_ fs: [FichaMesa]) -> String {
        let vivas = fs.filter(\.viva), n = live.sessions.count
        let partes = [n == 1 ? String(localized: "1 conversación") : String(localized: "\(n) conversaciones")] + vivas.map { "\($0.nombre) \($0.actividad)" }
        return String(localized: "Scriptorium: ") + partes.joined(separator: "; ") + String(localized: ". Abrir el Hueco")
    }

    // Estado legible en EMBERY_DIR/state.json: sirve para comprobar el Hueco sin mirar la pantalla.
    private func volcar() {
        let filas = feed.rows.map { ["title": $0.title, "project": $0.project, "model": $0.model, "status": $0.status,
                                     "ctx": $0.ctx.map(String.init) ?? $0.tokens.map { "\($0 / 1000)k" } ?? "—"] }
        let hoy = tokens.days[TokenLedger.dayFormat.string(from: Date())] ?? 0
        let nv = nivel.map { "\($0.kind == .volume ? "vol" : "brillo") \($0.muted ? "silencio" : "\($0.percent)%")" } ?? ""
        let obj: [String: Any] = ["estado": "\(live.estado)", "vista": "\(vista)", "rows": filas, "perm": feed.permDetail, "done": feed.doneNote,
                                  "aviso": feed.warnNote, "block": feed.block.map { "\($0)% · \(feed.blockReset)" } ?? "—",
                                  "week": feed.week.map { "\($0)% · \(feed.weekReset)" } ?? "—", "tokensToday": hoy,
                                  "tokenDays": tokens.days.count, "nido": nido.items.map(\.lastPathComponent),
                                  "disk": raices.map { $0.present ? "ok" : "fuera" } ?? "sin disco", "level": nv,
                                  "actividad": actividad.rawValue, "scriptorium": scriptorium, "mesas": fichas.map { $0.viva ? "\($0.nombre): \($0.actividad)" : "vacía" }]
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted]),
              let s = String(data: d, encoding: .utf8), s != ultimo else { return }
        ultimo = s
        try? d.write(to: URL(fileURLWithPath: EMBERY_DIR).appendingPathComponent("state.json"))
    }
}

// Lo que pasa con Claude mientras hay un foco: conversaciones que acaban y permisos que piden, contados una vez por sesión.
struct Espera: Equatable {
    var hechas: Set<String> = []
    var permisos: Set<String> = []
    var vacia: Bool { hechas.isEmpty && permisos.isEmpty }
    var conversaciones: Int { hechas.union(permisos).count }

    mutating func anotar(hecho: String, permisos p: [String]) {
        if !hecho.isEmpty { hechas.insert(hecho) }
        permisos.formUnion(p)
    }
    // Los permisos que ya se contestaron en la terminal no esperan a nadie.
    func alTerminar(enPermiso: Set<String>) -> Espera { Espera(hechas: hechas, permisos: permisos.intersection(enPermiso)) }

    var texto: String {
        let n = conversaciones, m = permisos.count
        let c = n == 1 ? String(localized: "1 conversación") : String(localized: "\(n) conversaciones")
        return m == 0 ? c : c + (m == 1 ? String(localized: " · 1 permiso") : String(localized: " · \(m) permisos"))
    }
}
