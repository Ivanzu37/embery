import AppKit
import Observation
import Sparkle

// Actualizaciones con Sparkle: el appcast vive en el repo (SUFeedURL) y cada DMG va firmado con la clave EdDSA (SUPublicEDKey).
// La búsqueda programada no roba el foco: el aviso espera detrás, como los demás avisos de Embery.
@Observable
final class Actualizar: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Actualizar()

    private(set) var puedeBuscar = false
    @ObservationIgnored private var controlador: SPUStandardUpdaterController!
    @ObservationIgnored private var observa: NSKeyValueObservation?

    override init() {
        super.init()
        // Fuera de un .app (swift run, pruebas) no hay Info.plist con el feed: Sparkle no arranca.
        let enApp = Bundle.main.bundlePath.hasSuffix(".app")
        controlador = SPUStandardUpdaterController(startingUpdater: enApp, updaterDelegate: nil, userDriverDelegate: self)
        sola = controlador.updater.automaticallyChecksForUpdates
        observa = controlador.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] u, _ in
            DispatchQueue.main.async { self?.puedeBuscar = enApp && u.canCheckForUpdates }
        }
    }

    var sola = false { didSet { controlador.updater.automaticallyChecksForUpdates = sola } }

    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–" }

    func buscar() {
        NSApp.activate()
        controlador.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }
}
