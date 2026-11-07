// Embery · el Hueco: recibe los hooks de Claude Code por un socket local y lleva la cuenta de cada sesión.
import Foundation

// EMBERY_DIR en el entorno desvía todo (socket, estado, bandeja, límites): para probar sin pisar la app instalada.
// La copia desde ~/.vigil va aquí, en la primera vez que alguien pide la carpeta: antes de leer nada de ella.
let EMBERY_DIR: String = {
    if let d = ProcessInfo.processInfo.environment["EMBERY_DIR"] { return d }
    let d = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/Embery")
    traerDeVigil(a: d)
    return d
}()
let SOCKET_PATH = (EMBERY_DIR as NSString).appendingPathComponent("embery.sock")

// Quien venía del notch de VIGIL conserva sus cuentas: se copian una vez, y ~/.vigil se queda como estaba.
func traerDeVigil(desde viejo: String = (NSHomeDirectory() as NSString).appendingPathComponent(".vigil"), a nuevo: String) {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: nuevo, withIntermediateDirectories: true)
    for f in ["tokens.json", "limits.json", "bandeja.json"] {
        let a = (viejo as NSString).appendingPathComponent(f), b = (nuevo as NSString).appendingPathComponent(f)
        if fm.fileExists(atPath: a), !fm.fileExists(atPath: b) { try? fm.copyItem(atPath: a, toPath: b) }
    }
}

final class HookServer {
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "embery.hooks")
    private let onMessage: ([String: Any]) -> Void
    private var pendientes: [String: (fd: Int32, desde: Date)] = [:]   // solo en `queue`

    private let path: String

    init(path: String = SOCKET_PATH, onMessage: @escaping ([String: Any]) -> Void) { self.path = path; self.onMessage = onMessage }

    func start() {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let cap = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { p in
            p.withMemoryRebound(to: CChar.self, capacity: cap) { _ = strncpy($0, path, cap - 1) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0, listen(fd, 32) == 0 else { close(fd); fd = -1; return }
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let c = accept(self.fd, nil, nil)
            if c >= 0 { self.read(c) }
        }
        src.resume()
        source = src
    }

    private func read(_ c: Int32) {
        var tv = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var data = Data(), buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = recv(c, &buf, buf.count, 0)
            if n <= 0 { break }
            data.append(buf, count: n)
            if data.count > 1_000_000 { break }
        }
        var espera: String?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            if let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                if obj["embery_wait"] as? Bool == true { espera = obj["session_id"] as? String }
                DispatchQueue.main.async { self.onMessage(obj) }
            }
        }
        // El hook del permiso se queda al teléfono hasta que Embery decida, suelte o pase el plazo.
        guard let id = espera else { close(c); return }
        var uno: Int32 = 1
        setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &uno, socklen_t(MemoryLayout<Int32>.size))
        if let antes = pendientes[id] { close(antes.fd) }
        pendientes[id] = (c, Date())
    }

    // Permitir o Denegar: el hook lo devuelve a Claude Code. false si el hook ya no espera.
    @discardableResult
    func responder(_ id: String, permitir: Bool) -> Bool {
        queue.sync {
            guard let p = pendientes.removeValue(forKey: id) else { return false }
            let r = Data(((permitir ? #"{"behavior":"allow"}"# : #"{"behavior":"deny"}"#) + "\n").utf8)
            let n = r.withUnsafeBytes { send(p.fd, $0.baseAddress, r.count, 0) }
            close(p.fd)
            return n == r.count
        }
    }

    // Sin decisión: el hook sale callado y Claude Code pregunta en su terminal.
    func soltar(_ id: String) { queue.async { if let p = self.pendientes.removeValue(forKey: id) { close(p.fd) } } }

    func soltarViejos(_ plazo: TimeInterval = HookServer.espera + 5) {
        queue.async {
            for (id, p) in self.pendientes where Date().timeIntervalSince(p.desde) > plazo { close(p.fd); self.pendientes[id] = nil }
        }
    }

    var esperando: Set<String> { queue.sync { Set(pendientes.keys) } }
    static let espera: TimeInterval = 60   // lo que aguanta embery-hook
}

enum SState { case idle, working, perm }
enum EstadoHueco { case reposo, trabajo, permiso, aviso, hecho }

struct SessionInfo {
    var id: String
    var project: String
    var cwd = ""
    var model = ""
    var state: SState = .idle
    var tool = ""
    var permDetail = ""
    var permTool = "", permCommand = ""
    var turnStart: Date?
    var lastEvent = Date()
    var tools = 0
    var ctx: Int?          // % de contexto (statusline)
    var tokens: Int?       // tokens de contexto (conversación), si no hay %
    var transcript = ""
    var title: String?         // título de la conversación según Claude Code
    var prompt: String?        // si aún no hay título: el arranque del último prompt
    var name: String { title ?? prompt ?? project }
    var whereInfo: [String: String] = [:]
    var permSince: Date?   // app, tty, sesión de iTerm… (lo manda el hook)
    var lastRead = Date.distantPast
    var tareas: [Tarea] = []   // el tablón del Scriptorium (TaskCreate/TaskUpdate o TodoWrite)
    var ayudantes = 0          // Task/Agent en vuelo
    var archivo = ""           // el último archivo que tocó una herramienta
}

struct Tarea: Equatable {
    enum Estado: String { case pendiente, curso, hecha }
    var clave: String
    var texto: String
    var estado: Estado

    // Lo que hace cada herramienta de tareas con la lista. Formato desconocido: la lista no cambia.
    // Comprobado en conversaciones reales (2026-11-06): TaskCreate {subject} → «Task #1 created», ids 1, 2, 3…;
    // TaskUpdate {taskId, status}. TodoWrite {todos: [{content, status}]} trae la lista entera.
    static func aplicar(_ lista: [Tarea], herramienta: String, entrada: [String: Any]?, respuesta: Any?) -> [Tarea] {
        guard let entrada else { return lista }
        func estado(_ v: Any?) -> Estado? {
            switch v as? String { case "pending": .pendiente; case "in_progress": .curso; case "completed": .hecha; default: nil }
        }
        switch herramienta {
        case "TodoWrite":
            guard let todos = entrada["todos"] as? [[String: Any]] else { return lista }
            let nueva = todos.compactMap { t -> Tarea? in
                guard let texto = t["content"] as? String, let e = estado(t["status"]) else { return nil }
                return Tarea(clave: texto, texto: texto, estado: e)
            }
            return nueva.count == todos.count ? nueva : lista
        case "TaskCreate":
            guard let texto = entrada["subject"] as? String else { return lista }
            let id = ((respuesta as? [String: Any])?["task"] as? [String: Any]).flatMap { $0["id"].map { "\($0)" } } ?? "\(lista.count + 1)"
            return lista + [Tarea(clave: id, texto: texto, estado: .pendiente)]
        case "TaskUpdate":
            guard let id = entrada["taskId"].map({ "\($0)" }), let i = lista.firstIndex(where: { $0.clave == id }) else { return lista }
            var l = lista
            if entrada["status"] as? String == "deleted" { l.remove(at: i); return l }
            if let e = estado(entrada["status"]) { l[i].estado = e }
            if let t = entrada["subject"] as? String { l[i].texto = t }
            return l
        default: return lista
        }
    }
}

// Lo que enseña el Hueco.
struct Row: Equatable { var project, model, status: String; var kind: SState; var ctx: Int?; var tokens: Int? = nil; var title: String = ""; var id: String = "" }
struct Feed: Equatable {
    var rows: [Row] = []
    var clockStart: Date?
    var working = 0
    var permProject = "", permDetail = ""
    var permTool = "", permCommand = "", permCwd = ""
    var permSince: Date?
    var project = ""   // el de la conversación principal
    var doneProject = "", doneTime = "", doneNote = ""
    var block: Int?, blockReset = "—", week: Int?, weekReset = "—", blockResetAt: Date?, weekResetAt: Date?
    var curve: [Double?] = []
    var permId = "", doneId = ""
    var warnTag = "límite", warnLabel = "", warnValue = "", warnNote = ""
}

func fmtDuration(_ s: TimeInterval) -> String {
    let t = max(0, Int(s))
    return t >= 60 ? "\(t / 60)m\(String(format: "%02d", t % 60))s" : "\(t)s"
}

struct Limits: Codable {
    var block: Double?, blockReset: Double?, week: Double?, weekReset: Double?, at: Double = 0
    var source: String? = nil   // lo último que dijo la statusline de Claude Code (siempre "terminal")
    var weekAnchor: Double? = nil   // último reinicio semanal exacto: la semana se repite cada 7 días desde él
}

final class Live {
    private(set) var sessions: [String: SessionInfo] = [:]
    private(set) var limits = Live.loadLimits()
    private let io = DispatchQueue(label: "embery.transcripts")
    private var flash: (until: Date, project: String, time: String, note: String)?
    private var flashId = ""
    // aviso de límite: al cruzar el 80 % o el 95 % del bloque o de la semana
    private var warn: (until: Date, tag: String, label: String, value: String, note: String)?
    private var lastSeen: [String: Int] = [:]
    private(set) var lastActivity = Date()
    var warnings = true
    private var desktop: (block: WindowReading?, week: WindowReading?) = (nil, nil)
    private var prompts: [Date] = []
    private(set) var curve: [Double?] = []   // bloque 5 h en las últimas 24 h, tramos de 20 min   // inicios de turno de las últimas horas: afinan el inicio del bloque

    func handle(_ p: [String: Any]) {
        guard let event = p["hook_event_name"] as? String, let id = p["session_id"] as? String else { return }
        let now = Date()
        var s = sessions[id] ?? SessionInfo(id: id, project: Live.project(p["cwd"] as? String))
        s.lastEvent = now
        if let m = p["model"] as? String { s.model = Live.shortModel(m) }
        else if let m = p["model"] as? [String: Any], let mid = m["id"] as? String { s.model = Live.shortModel(mid) }

        if let tp = p["transcript_path"] as? String, !tp.isEmpty { s.transcript = tp }
        if let w = p["where"] as? [String: String] { s.whereInfo.merge(w.filter { !$0.value.isEmpty }) { _, n in n } }
        if event != "StatusLine", let c = p["cwd"] as? String, !c.isEmpty { s.project = Live.project(c); s.cwd = c }

        if event != "StatusLine" { lastActivity = now }

        switch event {
        case "StatusLine":
            if let cw = p["context_window"] as? [String: Any], let u = Live.num(cw["used_percentage"]) { s.ctx = Int(u.rounded()) }
            if let rl = p["rate_limits"] as? [String: Any] {
                let f = rl["five_hour"] as? [String: Any], w = rl["seven_day"] as? [String: Any]
                fijaLimites(f.map { (Live.num($0["used_percentage"]), Live.epoch($0["resets_at"])) },
                            w.map { (Live.num($0["used_percentage"]), Live.epoch($0["resets_at"])) }, now)
            }
            s.lastEvent = sessions[id]?.lastEvent ?? now   // la statusline no cuenta como actividad
        case "SessionEnd":
            sessions[id] = nil; return
        case "UserPromptSubmit":
            s.state = .working; s.turnStart = now; s.tools = 0; s.tool = String(localized: "pensando")
            if let p = p["prompt"] as? String, s.title == nil { s.prompt = Live.firstWords(p) }
            prompts.append(now); prompts.removeAll { now.timeIntervalSince($0) > PlanUsage.blockLength + 3600 }
        case "PreToolUse":
            s.state = .working; if s.turnStart == nil { s.turnStart = now }
            s.tools += 1; s.tool = p["tool_name"] as? String ?? String(localized: "herramienta")
            if Live.ayudante(s.tool) { s.ayudantes += 1 }
            let entrada = p["tool_input"] as? [String: Any]
            if let f = (entrada?["file_path"] ?? entrada?["notebook_path"]) as? String { s.archivo = (f as NSString).lastPathComponent }
        case "PostToolUse", "PostToolUseFailure":
            if s.state == .perm || s.state == .working { s.state = .working; s.tool = String(localized: "pensando") }
            let nombre = p["tool_name"] as? String ?? ""
            if Live.ayudante(nombre) { s.ayudantes = max(0, s.ayudantes - 1) }
            if event == "PostToolUse" { s.tareas = Tarea.aplicar(s.tareas, herramienta: nombre, entrada: p["tool_input"] as? [String: Any], respuesta: p["tool_response"]) }
        case "PermissionRequest":
            s.state = .perm
            s.permDetail = Live.detail(p["tool_name"] as? String, p["tool_input"] as? [String: Any])
            s.permTool = p["tool_name"] as? String ?? "herramienta"
            s.permCommand = Live.comando(p["tool_input"] as? [String: Any])
        case "Notification":
            let kind = p["notification_type"] as? String ?? ""
            if kind == "permission_prompt" {
                s.state = .perm
                if s.permDetail.isEmpty { s.permDetail = p["message"] as? String ?? String(localized: "pide permiso") }
            } else if kind == "idle_prompt" { s.state = .idle; s.turnStart = nil }
        case "Stop", "StopFailure":
            let dur = s.turnStart.map { now.timeIntervalSince($0) } ?? 0
            let failed = event == "StopFailure"
            if s.turnStart != nil || failed {
                flash = (now.addingTimeInterval(4), s.project, fmtDuration(dur),
                         failed ? String(localized: "Se cortó") : s.tools == 1 ? String(localized: "Hecho · 1 herramienta") : String(localized: "Hecho · \(s.tools) herramientas"))
            }
            flashId = id
            s.state = .idle; s.turnStart = nil; s.tool = ""; s.ayudantes = 0
        default: break
        }
        if s.state != .perm { s.permDetail = ""; s.permTool = ""; s.permCommand = ""; s.permSince = nil } else if s.permSince == nil { s.permSince = now }
        sessions[id] = s
        if !s.transcript.isEmpty, now.timeIntervalSince(s.lastRead) > 1.5, event != "PreToolUse" { readTranscript(id) }
    }

    // Modelo y tokens de contexto desde el final de la conversación (.jsonl), fuera del hilo principal.
    private func readTranscript(_ id: String) {
        guard let path = sessions[id]?.transcript else { return }
        sessions[id]?.lastRead = Date()
        io.async {
            let r = Live.tail(path)
            DispatchQueue.main.async {
                guard self.sessions[id] != nil else { return }
                if let m = r.model { self.sessions[id]?.model = Live.shortModel(m) }
                if let t = r.tokens { self.sessions[id]?.tokens = t }
                if let t = r.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { self.sessions[id]?.title = t }
                else if self.sessions[id]?.title == nil, let p = r.lastPrompt { self.sessions[id]?.prompt = Live.firstWords(p) }
            }
        }
    }

    // Del final de la conversación: modelo, tokens de contexto y el título que Claude Code le va poniendo
    // según de qué trata (custom-title en la app de escritorio, ai-title en la terminal; si no, el último prompt).
    struct Tail { var model: String?; var tokens: Int?; var title: String?; var lastPrompt: String?; var cwd: String? }
    static func tail(_ path: String) -> Tail {
        var r = Tail()
        guard let fh = FileHandle(forReadingAtPath: path) else { return r }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        try? fh.seek(toOffset: size > 400_000 ? size - 400_000 : 0)
        guard let data = try? fh.readToEnd() else { return r }
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            if r.tokens != nil, r.title != nil { break }
            // filtro rápido antes de parsear: solo las líneas que interesan
            let head = line.prefix(200)
            guard head.contains(UInt8(ascii: "t")),
                  let o = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = o["type"] as? String else { continue }
            switch type {
            case "custom-title" where r.title == nil: r.title = o["customTitle"] as? String
            case "ai-title" where r.title == nil: r.title = o["aiTitle"] as? String
            case "last-prompt" where r.lastPrompt == nil: r.lastPrompt = o["lastPrompt"] as? String
            case _ where r.cwd == nil && o["cwd"] is String:
                r.cwd = o["cwd"] as? String
                if type == "assistant", r.tokens == nil, let msg = o["message"] as? [String: Any], let u = msg["usage"] as? [String: Any],
                   (o["isSidechain"] as? Bool) != true {
                    let t = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].compactMap { u[$0] as? Int }.reduce(0, +)
                    r.model = msg["model"] as? String; r.tokens = t > 0 ? t : nil
                }
            case "assistant" where r.tokens == nil:
                guard (o["isSidechain"] as? Bool) != true, let msg = o["message"] as? [String: Any],
                      let u = msg["usage"] as? [String: Any] else { continue }
                let t = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].compactMap { u[$0] as? Int }.reduce(0, +)
                r.model = msg["model"] as? String; r.tokens = t > 0 ? t : nil
            default: continue
            }
        }
        return r
    }

    // El rate_limit_event del stream-json de `claude -p` (utilization 0…1), el que trae ConsultaUso.
    func handleRateLimit(_ o: [String: Any]) {
        guard o["type"] as? String == "rate_limit_event",
              let u = (o["rate_limit_info"] as? [String: Any])?["unifiedWindows"] as? [String: Any] else { return }
        let f = u["five_hour"] as? [String: Any], w = u["seven_day"] as? [String: Any]
        guard f != nil || w != nil else { return }
        fijaLimites(f.map { (Live.num($0["utilization"]).map { $0 * 100 }, Live.epoch($0["resetsAt"])) },
                    w.map { (Live.num($0["utilization"]).map { $0 * 100 }, Live.epoch($0["resetsAt"])) }, Date())
    }

    private func fijaLimites(_ block: (Double?, Double?)?, _ week: (Double?, Double?)?, _ now: Date) {
        var l = limits
        if let (u, r) = block { l.block = u; l.blockReset = r }
        if let (u, r) = week {
            l.week = u; l.weekReset = r
            if let r { l.weekAnchor = r }
        }
        l.at = now.timeIntervalSince1970
        l.source = "terminal"
        limits = l
        Live.saveLimits(l)
    }

    // Segundos desde la lectura más reciente del plan, venga de Claude Code o de Claude desktop.
    var edadLimites: TimeInterval {
        let ultima = [limits.at, desktop.block?.at.timeIntervalSince1970 ?? 0, desktop.week?.at.timeIntervalSince1970 ?? 0].max()!
        return Date().timeIntervalSince1970 - ultima
    }

    // Claude desktop: historial del plan → bloque y semana con reinicios deducidos.
    func refreshFromDesktop() {
        let p = prompts
        io.async {
            let samples = PlanUsage.read(), org = PlanUsage.claudeCodeOrg()
            let r = samples.map { PlanUsage.estimate($0, org: org, prompts: p) } ?? (nil, nil)
            let c = samples.map { PlanUsage.curve($0, org: org) } ?? []
            DispatchQueue.main.async { self.desktop = r; self.curve = c }
        }
    }

    // Lo que dijo la statusline, como lectura de un límite (con reinicio exacto).
    private func terminalReading(_ used: Double?, _ reset: Double?, length: TimeInterval) -> WindowReading? {
        guard let used else { return nil }
        let at = Date(timeIntervalSince1970: limits.at), now = Date()
        if let r = reset, r <= now.timeIntervalSince1970 { return nil }
        if reset == nil, now.timeIntervalSince(at) > min(length, 86400) { return nil }
        return WindowReading(used: used, resetsAt: reset.map { Date(timeIntervalSince1970: $0) }, at: at, exact: reset != nil)
    }

    // Gana la lectura más reciente; la hora exacta de Claude Code, si sigue vigente, manda sobre la deducida.
    private func pick(_ term: WindowReading?, _ app: WindowReading?) -> WindowReading? {
        guard var best = [term, app].compactMap({ $0 }).max(by: { $0.at < $1.at }) else { return nil }
        if !best.exact, let t = term, t.exact, let r = t.resetsAt, r > Date() { best.resetsAt = r; best.exact = true }
        return best
    }

    static func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap(Double.init) }
    static func epoch(_ v: Any?) -> Double? {
        if let n = num(v) { return n > 1e12 ? n / 1000 : n }
        if let s = v as? String { return ISO8601DateFormatter().date(from: s)?.timeIntervalSince1970 }
        return nil
    }
    static var limitsURL: URL { URL(fileURLWithPath: EMBERY_DIR).appendingPathComponent("limits.json") }
    static func loadLimits() -> Limits {
        var l = (try? JSONDecoder().decode(Limits.self, from: Data(contentsOf: limitsURL))) ?? Limits()
        if l.weekAnchor == nil { l.weekAnchor = l.weekReset }   // archivos de antes de guardar el ancla
        return l
    }
    static func saveLimits(_ l: Limits) { try? JSONEncoder().encode(l).write(to: limitsURL) }

    static func untilText(_ r: Double?) -> String {
        guard let r else { return "—" }
        let s = max(0, Int(r - Date().timeIntervalSince1970))
        return s >= 3600 ? "\(s / 3600)h\(String(format: "%02d", (s % 3600) / 60))" : "\(s / 60)m"
    }
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = LOCALE; f.dateFormat = "EEE HH:mm"
        return f
    }()
    static func dayText(_ r: Double?) -> String {
        guard let r else { return "—" }
        return dayFormatter.string(from: Date(timeIntervalSince1970: r)).replacingOccurrences(of: ".", with: "")
    }

    // Limpieza: turnos sin noticias en 10 min dejan de contar como trabajo; sesiones quietas 2 h se olvidan.
    func prune() {
        let now = Date()
        for (id, s) in sessions {
            if now.timeIntervalSince(s.lastEvent) > 7200 { sessions[id] = nil }
            else if s.state == .working, now.timeIntervalSince(s.lastEvent) > 600 { sessions[id]?.state = .idle; sessions[id]?.turnStart = nil }
        }
        if let f = flash, f.until < now { flash = nil }
        if let w = warn, w.until < now { warn = nil }
        checkThresholds()
    }

    var estado: EstadoHueco {
        if sessions.values.contains(where: { $0.state == .perm }) { return .permiso }
        if warn != nil { return .aviso }
        if flash != nil { return .hecho }
        if sessions.values.contains(where: { $0.state == .working }) { return .trabajo }
        return .reposo
    }

    func feed() -> Feed {
        var f = Feed()
        let ordered = sessions.values.sorted { a, b in
            let r: (SState) -> Int = { $0 == .perm ? 0 : $0 == .working ? 1 : 2 }
            return r(a.state) != r(b.state) ? r(a.state) < r(b.state) : a.lastEvent > b.lastEvent
        }
        // en el panel, solo las activas: trabajando o esperando permiso (las quietas siguen contando para la voz)
        f.rows = ordered.filter { $0.state != .idle }.prefix(4).map { s in
            s.state == .perm
                ? Row(project: s.project, model: s.model, status: String(localized: "espera permiso"), kind: .perm, ctx: s.ctx, tokens: s.tokens, title: s.name, id: s.id)
                : Row(project: s.project, model: s.model, status: String(localized: "trabajando · \(s.tool)"), kind: .working, ctx: s.ctx, tokens: s.tokens, title: s.name, id: s.id)
        }
        let working = ordered.filter { $0.state == .working }
        f.working = working.count
        f.clockStart = working.compactMap(\.turnStart).min()
        if let p = ordered.first(where: { $0.state == .perm }) { f.permDetail = p.permDetail }
        if let fl = flash { f.doneProject = fl.project; f.doneTime = fl.time; f.doneNote = fl.note; f.doneId = flashId }
        if let p = ordered.first(where: { $0.state == .perm }) {
            f.permId = p.id; f.permTool = p.permTool.isEmpty ? String(localized: "permiso") : p.permTool
            f.permCommand = p.permCommand.isEmpty ? p.permDetail : p.permCommand
            f.permCwd = p.cwd; f.permSince = p.permSince
            f.permProject = p.project
        }
        f.project = Actividad.principal(Array(sessions.values)).map(\.project) ?? ""
        if let w = warn { f.warnTag = w.tag; f.warnLabel = w.label; f.warnValue = w.value; f.warnNote = w.note }
        // ≈ = reinicio deducido del historial de la app; sin ≈ = hora exacta de Claude Code
        let block = pick(terminalReading(limits.block, limits.blockReset, length: PlanUsage.blockLength), desktop.block)
        var week = pick(terminalReading(limits.week, limits.weekReset, length: PlanUsage.weekLength), desktop.week)
        if var w = week, !w.exact, var r = limits.weekAnchor {
            while r <= Date().timeIntervalSince1970 { r += PlanUsage.weekLength }
            w.resetsAt = Date(timeIntervalSince1970: r); w.exact = true; week = w
        }
        func mark(_ w: WindowReading) -> String { w.exact ? "" : "≈" }
        // la app mira cada 5–15 min: una lectura de más de 30 min se ha saltado alguna (¿app cerrada o icono de la barra apagado?)
        func stale(_ w: WindowReading?) -> String {
            guard let w, Date().timeIntervalSince(w.at) > 1800, w.resetsAt != nil else { return "" }
            return " · " + Live.hace(Live.ago(w.at))
        }
        // el bloque cambia en minutos: una lectura de más de 1 h no se enseña como si fuera de ahora
        if let b = block, Date().timeIntervalSince(b.at) > 3600 {
            f.blockReset = String(localized: "sin dato · \(Live.hace(Live.ago(b.at)))")
        } else {
            f.block = block.map { Int($0.used.rounded()) }
            f.blockResetAt = block?.resetsAt
            f.blockReset = block.map { b in b.resetsAt.map { mark(b) + Live.untilText($0.timeIntervalSince1970) } ?? Live.hace(Live.ago(b.at)) } ?? "—"
            f.blockReset += stale(block)
        }
        f.week = week.map { Int($0.used.rounded()) }
        f.weekResetAt = week?.resetsAt
        f.weekReset = week.map { w in w.resetsAt.map { mark(w) + Live.dayText($0.timeIntervalSince1970) } ?? Live.hace(Live.ago(w.at)) } ?? "—"
        f.weekReset += stale(week)
        f.curve = curve
        return f
    }

    static func ayudante(_ herramienta: String) -> Bool { herramienta == "Task" || herramienta == "Agent" }

    static func project(_ cwd: String?) -> String {
        guard let c = cwd, !c.isEmpty else { return String(localized: "sesión") }
        return ((c as NSString).lastPathComponent).lowercased().replacingOccurrences(of: " ", with: "-")
    }
    static func shortModel(_ m: String) -> String {
        // claude-opus-5-5 → opus 5.5
        let parts = m.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
        guard let name = parts.first else { return m }
        let nums = parts.dropFirst().prefix(while: { $0.count <= 2 && Int($0) != nil })
        return nums.isEmpty ? String(name) : "\(name) \(nums.joined(separator: "."))"
    }
    // El comando entero, para la fila de permiso (se corta al final en pantalla y sale completo en la ayuda).
    static func comando(_ input: [String: Any]?) -> String {
        let i = input ?? [:]
        let d = (i["command"] ?? i["file_path"] ?? i["url"] ?? i["pattern"] ?? i["description"] ?? "") as? String ?? ""
        return d.replacingOccurrences(of: "\n", with: " ")
    }
    static func detail(_ tool: String?, _ input: [String: Any]?) -> String {
        let t = tool ?? "herramienta"
        let i = input ?? [:]
        var d = (i["command"] ?? i["file_path"] ?? i["url"] ?? i["pattern"] ?? i["description"] ?? "") as? String ?? ""
        if i["file_path"] != nil { d = (d as NSString).lastPathComponent }
        d = d.replacingOccurrences(of: "\n", with: " ")
        if d.count > 44 { d = String(d.prefix(44)) + "…" }
        return d.isEmpty ? t : "\(t) · \(d)"
    }
    // Al arrancar: las conversaciones con actividad en las últimas 2 h vuelven al panel (los hooks solo avisan de lo nuevo).
    func seedRecent() {
        io.async {
            let root = URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects"))
            let fm = FileManager.default
            let cutoff = Date().addingTimeInterval(-7200)
            var found: [(String, String, Date, Tail)] = []
            for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                where f.pathExtension == "jsonl" {
                    guard let m = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, m > cutoff else { continue }
                    found.append((f.deletingPathExtension().lastPathComponent, f.path, m, Live.tail(f.path)))
                }
            }
            DispatchQueue.main.async {
                for (id, path, m, t) in found where self.sessions[id] == nil {
                    var s = SessionInfo(id: id, project: Live.project(t.cwd))
                    s.cwd = t.cwd ?? ""
                    s.transcript = path; s.lastEvent = m; s.lastRead = Date()
                    if let mo = t.model { s.model = Live.shortModel(mo) }
                    s.tokens = t.tokens
                    s.title = t.title.flatMap { $0.isEmpty ? nil : $0 }
                    if s.title == nil { s.prompt = t.lastPrompt.map { Live.firstWords($0) } }
                    self.sessions[id] = s
                }
            }
        }
    }

    // Tras Permitir o Denegar desde el Hueco: Claude sigue con la respuesta (también con la negativa).
    func resuelto(_ id: String) {
        guard var s = sessions[id], s.state == .perm else { return }
        s.state = .working; s.tool = String(localized: "pensando"); s.permDetail = ""; s.permTool = ""; s.permCommand = ""; s.permSince = nil; s.lastEvent = Date()
        sessions[id] = s
    }

    // El hook ya no espera: la pregunta sigue en la terminal, el Hueco deja de enseñarla.
    func descartado(_ id: String) {
        guard var s = sessions[id], s.state == .perm else { return }
        s.state = .idle; s.permDetail = ""; s.permTool = ""; s.permCommand = ""; s.permSince = nil
        sessions[id] = s
    }

    // Un clic en el Hueco te lleva a la sesión.
    func focus(_ id: String) {
        if let s = sessions[id] { Focus.go(s) } else { Focus.log("sesión no encontrada \(id.prefix(8))") }
    }

    private func checkThresholds() {
        let f = feed()
        for (key, label, value, reset, resetAt) in [("5h", String(localized: "bloque 5h"), f.block, f.blockReset, f.blockResetAt), ("7d", String(localized: "semana"), f.week, f.weekReset, f.weekResetAt)] {
            guard let v = value else { continue }
            defer { lastSeen[key] = v }
            guard let before = lastSeen[key] else { continue }       // al arrancar no se avisa de lo que ya había
            guard warnings, let t = [95, 80].first(where: { before < $0 && v >= $0 }) else { continue }
            let known = resetAt != nil
            let note: String
            if key == "5h" { note = (t >= 95 ? String(localized: "Casi sin aliento") : String(localized: "Aliento por debajo del 20 %")) + (known ? String(localized: " · vuelve en \(reset)") : "") }
            else { note = t >= 95 ? String(localized: "Semana casi agotada") : String(localized: "Semana por debajo del 20 %") }
            warn = (Date().addingTimeInterval(6), "límite", label, "\(v)%", note)
        }
    }

    // Aviso de 6 s que no es del plan (el disco se fue con sesiones dentro).
    func alert(tag: String, label: String, value: String, note: String) {
        warn = (Date().addingTimeInterval(6), tag, label, value, note)
    }
    // Sesiones con su carpeta en el disco y actividad en la última media hora.
    func sessionsInside(_ v: Vault) -> Int {
        let now = Date()
        return sessions.values.filter { v.contains($0.cwd) && now.timeIntervalSince($0.lastEvent) < 1800 }.count
    }

    static func firstWords(_ p: String, max: Int = 6) -> String {
        let w = p.replacingOccurrences(of: "\n", with: " ").split(separator: " ").prefix(max).joined(separator: " ")
        return w.count > 48 ? String(w.prefix(48)) + "…" : w
    }
    static func hace(_ t: String) -> String { String(localized: "hace \(t)") }
    static func ago(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m" : "\(s / 3600)h"
    }
}
