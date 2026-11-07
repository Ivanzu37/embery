// Embery · el calendario de tokens. Lee las conversaciones de Claude Code (~/.claude/projects/*/*.jsonl) a trozos:
// de cada archivo, solo lo nuevo desde la última vez. Cuenta cada respuesta una vez (el mismo mensaje sale en una
// línea por bloque, todas con el mismo `usage`: sumarlas lo inflaba ×2–8) y suma entrada + escritura de caché + salida,
// sin las lecturas de caché, como el dashboard. Sin subagentes (isSidechain).
// Lo contado vive en EMBERY_DIR/tokens.json: Claude Code borra las conversaciones a los 30 días; Embery no olvida.
import Foundation

final class TokenLedger {
    struct FileState: Codable {
        var offset: UInt64 = 0
        var lastId = "", lastN = 0, lastDay = ""   // el último mensaje contado: sus líneas pueden seguir en la próxima lectura
        var days: [String: Int] = [:]
    }
    struct Store: Codable {
        var files: [String: FileState] = [:]
        var archive: [String: Int] = [:]           // días de conversaciones que Claude Code ya borró
    }

    private let root: String
    private let storeURL: URL
    private var store = Store()
    private let queue = DispatchQueue(label: "embery.tokens", qos: .utility)
    private var busy = false
    private(set) var days: [String: Int] = [:]     // total por día (yyyy-MM-dd), en el hilo principal
    private(set) var version = 0
    private var lastScan = Date.distantPast

    init(root: String = NSHomeDirectory() + "/.claude/projects",
         store: URL = URL(fileURLWithPath: EMBERY_DIR).appendingPathComponent("tokens.json")) {
        self.root = root; storeURL = store
        if let d = try? Data(contentsOf: store), let s = try? JSONDecoder().decode(Store.self, from: d) {
            self.store = s; days = TokenLedger.total(s)
        }
    }

    // Solo si hace más de `age` s de la última lectura (al abrir el panel); el motor la pide cada 5 min.
    func scan(ifOlderThan age: TimeInterval = 0, done: (() -> Void)? = nil) {
        guard !busy, Date().timeIntervalSince(lastScan) >= age else { return }
        busy = true; lastScan = Date()
        queue.async { [self] in
            var s = store
            let changed = TokenLedger.update(&s, root: root)
            if changed, let d = try? JSONEncoder().encode(s) { try? d.write(to: storeURL, options: .atomic) }
            let t = TokenLedger.total(s)
            DispatchQueue.main.async { [self] in
                store = s; busy = false
                if t != days { days = t; version &+= 1 }
                done?()
            }
        }
    }

    // Síncrono, para los tests.
    func scanNow() { _ = TokenLedger.update(&store, root: root); days = TokenLedger.total(store); version &+= 1 }

    static func total(_ s: Store) -> [String: Int] {
        var t = s.archive
        for f in s.files.values { for (d, n) in f.days { t[d, default: 0] += n } }
        return t.filter { $0.value > 0 }
    }

    // Lee lo nuevo de cada archivo. Devuelve si cambió algo.
    static func update(_ s: inout Store, root: String) -> Bool {
        let fm = FileManager.default
        // Sin la carpeta (otro HOME, disco sin permiso) no se archiva nada: al volver se contaría todo dos veces.
        guard let dirs = try? fm.contentsOfDirectory(atPath: root) else { return false }
        // También las de los subagentes, que Claude Code guarda en subcarpetas de cada conversación.
        var paths: [String] = []
        for dir in dirs {
            let p = root + "/" + dir
            for f in (fm.enumerator(atPath: p)?.allObjects as? [String]) ?? [] where f.hasSuffix(".jsonl") { paths.append(p + "/" + f) }
        }
        var changed = false
        let present = Set(paths)
        for (p, f) in s.files where !present.contains(p) {   // borrada por Claude Code: sus días se quedan
            for (d, n) in f.days { s.archive[d, default: 0] += n }
            s.files[p] = nil; changed = true
        }
        for p in paths {
            guard let size = (try? fm.attributesOfItem(atPath: p))?[.size] as? UInt64 else { continue }
            var f = s.files[p] ?? FileState()
            if size < f.offset { f = FileState() }   // reescrita: se cuenta de nuevo
            guard size > f.offset, let h = FileHandle(forReadingAtPath: p) else { continue }
            defer { try? h.close() }
            try? h.seek(toOffset: f.offset)
            guard let data = try? h.readToEnd(), let end = data.lastIndex(of: 0x0A) else { continue }   // solo líneas enteras
            read(data[data.startIndex...end], into: &f)
            f.offset += UInt64(end - data.startIndex + 1)
            s.files[p] = f; changed = true
        }
        return changed
    }

    private static let usageKey = Data("\"usage\"".utf8)
    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static let isoPlain = ISO8601DateFormatter()
    static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    static func read(_ data: Data.SubSequence, into f: inout FileState) {
        for line in data.split(separator: 0x0A) where line.range(of: usageKey) != nil {
            guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  o["type"] as? String == "assistant",   // los subagentes (isSidechain) también gastan
                  let m = o["message"] as? [String: Any], let u = m["usage"] as? [String: Any],
                  let ts = o["timestamp"] as? String, let date = iso.date(from: ts) ?? isoPlain.date(from: ts) else { continue }
            let n = ["input_tokens", "cache_creation_input_tokens", "output_tokens"].reduce(0) { $0 + ((u[$1] as? NSNumber)?.intValue ?? 0) }
            let id = m["id"] as? String ?? o["uuid"] as? String ?? ""
            let day = dayFormat.string(from: date)
            if !id.isEmpty && id == f.lastId { f.days[f.lastDay, default: 0] -= f.lastN }   // otra línea del mismo mensaje: vale la última
            f.days[day, default: 0] += n
            f.lastId = id; f.lastN = n; f.lastDay = day
        }
    }

    // 2,3M · 850k · 420
    static func short(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if n >= 1000 { return "\(n / 1000)k" }
        return "\(n)"
    }
}
