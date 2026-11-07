// Embery · el uso del plan desde Claude desktop.
// La app guarda cada 5–15 min el % usado de cada límite (sin horas de reinicio) en plan-usage-history.json.
// Aquí se lee ese historial y se deducen los reinicios, solo cuando se puede:
// · el bloque se renueva 5 h después de empezar a gastar, pero ese gasto puede venir de claude.ai o del móvil;
//   solo se estima si el historial acota el inicio a menos de 30 min o un turno de Claude Code cae dentro.
//   (Comprobado el 2026-09-30: el bloque real reinició a las 22:30, sin actividad local que lo delatara.)
// · la semana se renueva cada 7 días exactos; la mejor fuente es una hora exacta anterior de Claude Code (ver Live).
import Foundation

struct UsageSample {
    var at: Date
    var org: String?
    var used: [String: Double]   // fh = bloque 5 h · sd = semana · so / sn = semana Opus / Sonnet
}

struct WindowReading {
    var used: Double
    var resetsAt: Date?
    var at: Date
    var exact: Bool              // true: la hora de reinicio la dio Claude Code; false: deducida del historial
}

enum PlanUsage {
    static let file = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json"))
    static let blockLength: TimeInterval = 5 * 3600
    static let weekLength: TimeInterval = 7 * 86400

    // Historial ordenado; nil si el archivo falta o tiene un formato que no conocemos (mejor "—" que adivinar).
    static func read() -> [UsageSample]? { (try? Data(contentsOf: file)).flatMap(parse) }

    static func parse(_ data: Data) -> [UsageSample]? {
        guard data.count < 4 << 20,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = (root["version"] as? NSNumber)?.intValue, version == 1 || version == 2,
              let list = root["samples"] as? [[String: Any]] else { return nil }
        var out: [UsageSample] = []
        for entry in list {
            guard let ms = (entry["t"] as? NSNumber)?.doubleValue, ms.isFinite, ms > 0 else { continue }
            let values = version == 1 ? entry : (entry["u"] as? [String: Any] ?? [:])
            var used: [String: Double] = [:]
            for key in ["fh", "sd", "so", "sn"] {
                guard let n = values[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { continue }
                used[key] = min(100, max(0, n.doubleValue))
            }
            out.append(UsageSample(at: Date(timeIntervalSince1970: ms / 1000), org: entry["org"] as? String, used: used))
        }
        return out.sorted { $0.at < $1.at }
    }

    // La organización con la que entra Claude Code (solo ese campo de ~/.claude.json, nada de credenciales).
    static func claudeCodeOrg() -> String? {
        let url = URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent(".claude.json"))
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any] else { return nil }
        return account["organizationUuid"] as? String
    }

    // Curva de las últimas `hours` horas en `bins` tramos: el máximo de `key` en cada tramo; nil = sin lecturas.
    static func curve(_ all: [UsageSample], org: String?, key: String = "fh", hours: Double = 24, bins: Int = 72,
                      now: Date = Date()) -> [Double?] {
        let mine = all.filter { (org == nil || $0.org == nil || $0.org == org) && $0.used[key] != nil }
        let span = hours * 3600, start = now.addingTimeInterval(-span), step = span / Double(bins)
        var out = [Double?](repeating: nil, count: bins)
        for s in mine where s.at > start && s.at <= now {
            let i = min(bins - 1, Int(s.at.timeIntervalSince(start) / step))
            out[i] = max(out[i] ?? 0, s.used[key]!)
        }
        return out
    }

    static func topOfHourUTC(_ d: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.dateInterval(of: .hour, for: d)?.start ?? d
    }

    // Bloque y semana a partir del historial. `prompts` son los inicios de turno vistos por los hooks:
    // afinan cuándo empezó a gastarse el bloque.
    static func estimate(_ all: [UsageSample], org: String?, prompts: [Date], now: Date = Date())
        -> (block: WindowReading?, week: WindowReading?) {
        // si la app está en otra cuenta que Claude Code, sus límites no son los nuestros
        let mine = all.filter { org == nil || $0.org == nil || $0.org == org }
        guard let latest = mine.last(where: { $0.used["fh"] != nil || $0.used["sd"] != nil }),
              latest.at <= now.addingTimeInterval(300), now.timeIntervalSince(latest.at) < weekLength else { return (nil, nil) }
        let history = mine.filter { $0.org == latest.org }
        let age = now.timeIntervalSince(latest.at)

        var block: WindowReading?
        if let used = latest.used["fh"], age < blockLength {
            let reset = used > 0 ? blockReset(history, prompts: prompts) : nil
            if reset.map({ $0 > now }) ?? (age < 86400) {
                block = WindowReading(used: used, resetsAt: reset, at: latest.at, exact: false)
            }
        }
        var week: WindowReading?
        if let used = latest.used["sd"] {
            let reset = weekReset(history, key: "sd", after: latest.at)
            if reset.map({ $0 > now }) ?? (age < 86400) {
                week = WindowReading(used: used, resetsAt: reset, at: latest.at, exact: false)
            }
        }
        return (block, week)
    }

    // El bloque empezó donde arranca la racha actual de lecturas > 0 (una bajada también es renovación).
    private static func blockReset(_ h: [UsageSample], prompts: [Date]) -> Date? {
        let runs = h.enumerated().filter { $0.element.used["fh"] != nil }.map(\.element)
        guard var i = runs.indices.last else { return nil }
        while i > 0, let prev = runs[i - 1].used["fh"], let cur = runs[i].used["fh"],
              prev > 0, prev <= cur + 1, runs[i].at.timeIntervalSince(runs[i - 1].at) < blockLength {
            i -= 1
        }
        let firstSeen = runs[i].at
        let floor = i > 0 ? runs[i - 1].at : firstSeen.addingTimeInterval(-blockLength)
        if let prompt = prompts.filter({ $0 > floor && $0 <= firstSeen }).min() {
            return prompt.addingTimeInterval(blockLength)          // un turno de Claude Code abrió el bloque
        }
        guard firstSeen.timeIntervalSince(floor) <= 1800 else { return nil }   // inicio sin acotar: no se sabe
        return firstSeen.addingTimeInterval(blockLength)           // el más tardío posible: no promete antes de tiempo
    }

    // La semana se renueva 7 días después de la última caída que vio el historial.
    private static func weekReset(_ h: [UsageSample], key: String, after reading: Date) -> Date? {
        let s = h.filter { $0.used[key] != nil }
        guard s.count > 1 else { return nil }
        for j in stride(from: s.count - 1, through: 1, by: -1) {
            guard let before = s[j - 1].used[key], let after = s[j].used[key], after + 1 < before else { continue }
            let nextHour = topOfHourUTC(s[j - 1].at).addingTimeInterval(3600)
            var moment = min(nextHour, s[j].at)
            while moment <= reading { moment.addTimeInterval(weekLength) }
            return moment
        }
        return nil
    }
}
