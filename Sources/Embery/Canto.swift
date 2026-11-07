import AppKit
import Observation

// Canto: lo que suena en Música o Spotify, por AppleScript (MediaRemote está cerrado a apps de terceros).
// Solo pregunta a las apps que ya están abiertas y solo mientras la tarjeta se ve.
@Observable
final class Canto {
    enum App: String, CaseIterable {
        case musica = "com.apple.Music", spotify = "com.spotify.client"
        var nombre: String { self == .musica ? String(localized: "Música") : String(localized: "Spotify") }
    }
    struct Pista: Equatable {
        var app: App
        var titulo, artista: String
        var posicion, duracion: Double
        var sonando: Bool
        var id: String
    }

    private(set) var pista: Pista?
    private(set) var caratula: NSImage?
    let espectro = Espectro()

    @ObservationIgnored private var reloj: Timer?
    @ObservationIgnored private var caratulaDe = ""
    @ObservationIgnored private var guiones: [App: NSAppleScript] = [:]
    // NSAppleScript se usa siempre desde la misma cola: no es seguro entre hilos.
    @ObservationIgnored private let cola = DispatchQueue(label: "embery.canto")

    func mirar(_ visible: Bool) {
        reloj?.invalidate(); reloj = nil
        if visible {
            leer()
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.leer() }
            RunLoop.main.add(t, forMode: .common)
            reloj = t
        }
        espectro.encender(visible && pista?.sonando == true)
    }

    func control(_ orden: String) {
        guard let app = pista?.app, abierta(app) else { return }
        cola.async {
            var e: NSDictionary?
            NSAppleScript(source: "tell application id \"\(app.rawValue)\" to \(orden)")?.executeAndReturnError(&e)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.leer() }
        }
    }

    private func abierta(_ a: App) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: a.rawValue).isEmpty }

    private func leer() {
        // Nunca se lanza una app: si no está abierta no se le pregunta (ni se compila su guion).
        let abiertas = App.allCases.filter(abierta)
        cola.async {
            let pistas = abiertas.compactMap { a in self.salida(a).flatMap { Canto.leer($0, app: a) } }
            DispatchQueue.main.async { self.poner(Canto.elegir(pistas)) }
        }
    }

    private func poner(_ p: Pista?) {
        if p != pista { pista = p }
        espectro.encender(reloj != nil && p?.sonando == true)
        guard let p, p.id != caratulaDe else { if p == nil { caratulaDe = ""; caratula = nil }; return }
        caratulaDe = p.id
        cola.async {
            let img = self.cargarCaratula(p.app)
            DispatchQueue.main.async { if self.caratulaDe == p.id { self.caratula = img } }
        }
    }

    private func salida(_ a: App) -> String? {
        if guiones[a] == nil { guiones[a] = NSAppleScript(source: Canto.guion(a)) }
        var e: NSDictionary?
        return guiones[a]?.executeAndReturnError(&e).stringValue
    }

    private func cargarCaratula(_ a: App) -> NSImage? {
        var e: NSDictionary?
        switch a {
        case .musica:
            let d = NSAppleScript(source: "tell application id \"\(a.rawValue)\" to get data of artwork 1 of current track")?.executeAndReturnError(&e)
            return d.flatMap { NSImage(data: $0.data) }
        case .spotify:
            let u = NSAppleScript(source: "tell application id \"\(a.rawValue)\" to get artwork url of current track")?.executeAndReturnError(&e).stringValue
            guard let u, let url = URL(string: u), url.scheme == "https", let d = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: d)
        }
    }

    // Campos separados por el carácter 31 (separador de unidad), que no aparece en títulos.
    static func guion(_ a: App) -> String {
        let id = a == .musica ? "persistent ID" : "id"
        return """
        if application id "\(a.rawValue)" is not running then return "stopped"
        tell application id "\(a.rawValue)"
            try
                set e to player state as string
                if e is "stopped" then return e
                set t to current track
                set s to character id 31
                return e & s & (name of t) & s & (artist of t) & s & (player position as string) & s & (duration of t as string) & s & (\(id) of t)
            on error
                return "stopped"
            end try
        end tell
        """
    }

    // La salida de `guion`. Los números llegan con la coma del idioma («21,345») y Spotify da la duración en ms.
    static func leer(_ s: String, app: App) -> Pista? {
        let c = s.components(separatedBy: "\u{1F}")
        guard c.count >= 6, c[0] == "playing" || c[0] == "paused" else { return nil }
        let num = { (t: String) in Double(t.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let dur = num(c[4]) / (app == .spotify ? 1000 : 1)
        return Pista(app: app, titulo: c[1], artista: c[2], posicion: min(max(0, num(c[3])), dur), duracion: dur,
                     sonando: c[0] == "playing", id: c[5...].joined(separator: "\u{1F}"))
    }

    // Si hay dos, manda la que suena; si ninguna suena, la primera en pausa.
    static func elegir(_ p: [Pista]) -> Pista? { p.first(where: \.sonando) ?? p.first }

    static func tiempo(_ s: Double) -> String { let t = Int(s); return "\(t / 60):" + String(format: "%02d", t % 60) }
}
