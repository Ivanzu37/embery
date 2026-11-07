// Embery · la jornada de Claude: de las mismas conversaciones que lee TokenLedger, cuántas hubo, cuántas horas
// activas (sin los huecos de más de 30 min) y qué herramientas usó. Los tokens salen de TokenLedger.days.
import Foundation

struct Jornada: Equatable {
    var conversaciones = 0
    var segundos = 0.0
    var herramientas: [(nombre: String, veces: Int)] = []
    var tokens = 0

    static func == (a: Jornada, b: Jornada) -> Bool {
        a.conversaciones == b.conversaciones && a.segundos == b.segundos && a.tokens == b.tokens
            && a.herramientas.map(\.nombre) == b.herramientas.map(\.nombre) && a.herramientas.map(\.veces) == b.herramientas.map(\.veces)
    }

    static let hueco: TimeInterval = 1800
    private static let marca = Data("\"timestamp\"".utf8)

    // Lento con muchas conversaciones: llamar fuera del hilo principal.
    static func calcular(desde: Date, hasta: Date = Date(), root: String = NSHomeDirectory() + "/.claude/projects",
                         tokensPorDia: [String: Int] = [:]) -> Jornada {
        let fm = FileManager.default
        var j = Jornada(), usos: [String: Int] = [:]
        for dir in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            let carpeta = root + "/" + dir
            for f in (try? fm.contentsOfDirectory(atPath: carpeta)) ?? [] where f.hasSuffix(".jsonl") {
                let p = carpeta + "/" + f
                // Un archivo que no se tocó desde el inicio del periodo no tiene mensajes dentro.
                guard let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date, m >= desde,
                      let data = fm.contents(atPath: p) else { continue }
                var horas: [Date] = [], vistas = Set<String>()
                for line in data.split(separator: 0x0A) where line.range(of: marca) != nil {
                    guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let tipo = o["type"] as? String, tipo == "user" || tipo == "assistant",
                          o["isSidechain"] as? Bool != true,
                          let ts = o["timestamp"] as? String,
                          let d = TokenLedger.iso.date(from: ts) ?? TokenLedger.isoPlain.date(from: ts),
                          d >= desde, d <= hasta else { continue }
                    horas.append(d)
                    guard tipo == "assistant", let msg = o["message"] as? [String: Any], let c = msg["content"] as? [[String: Any]] else { continue }
                    for b in c where b["type"] as? String == "tool_use" {
                        guard let nombre = b["name"] as? String, vistas.insert(b["id"] as? String ?? UUID().uuidString).inserted else { continue }
                        usos[nombre, default: 0] += 1
                    }
                }
                guard !horas.isEmpty else { continue }
                j.conversaciones += 1
                j.segundos += activo(horas)
            }
        }
        j.herramientas = usos.map { ($0.key, $0.value) }.sorted { $0.veces != $1.veces ? $0.veces > $1.veces : $0.nombre < $1.nombre }
        var dia = Calendar.current.startOfDay(for: desde)
        while dia <= hasta {
            j.tokens += tokensPorDia[TokenLedger.dayFormat.string(from: dia)] ?? 0
            dia = Calendar.current.date(byAdding: .day, value: 1, to: dia)!
        }
        return j
    }

    // Suma de los tramos entre mensajes seguidos; un hueco de más de 30 min no cuenta.
    static func activo(_ horas: [Date]) -> TimeInterval {
        let h = horas.sorted()
        return zip(h, h.dropFirst()).reduce(0) { s, par in
            let d = par.1.timeIntervalSince(par.0)
            return d > hueco ? s : s + d
        }
    }
}
