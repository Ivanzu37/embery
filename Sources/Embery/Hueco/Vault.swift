// Embery · el disco de la bóveda. La bóveda de Obsidian vive en un disco externo: sin disco no hay bóveda.
// Mira la lista de montajes del sistema (no toca el disco, así que no lo despierta): al instante con los avisos
// de montar y desmontar de macOS y, por si acaso, cada 30 s (Hueco.tick).
import AppKit

final class Vault {
    // EMBERY_VAULT en el entorno cambia el disco vigilado (para probar con una imagen de disco sin expulsar el de verdad).
    let root: String
    private(set) var present: Bool
    private(set) var since: Date?   // fuera desde (nil si ya faltaba al arrancar: no se sabe desde cuándo)
    var onChange: ((Bool) -> Void)?
    var name: String { (root as NSString).lastPathComponent }

    init(root: String) {
        self.root = root
        present = Vault.mounted(root)
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.check() }
        }
    }

    static func mounted(_ root: String) -> Bool {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        return urls.contains { $0.standardizedFileURL.path == root }
    }

    func check() {
        let now = Vault.mounted(root)
        guard now != present else { return }
        present = now; since = now ? nil : Date()
        onChange?(now)
    }

    func contains(_ path: String) -> Bool { path == root || path.hasPrefix(root + "/") }

    // El disco que vigila Raíces: el volumen externo donde está la carpeta (la bóveda de Ajustes). nil si está en el Mac.
    static func volumen(de ruta: String) -> String? {
        guard !ruta.isEmpty else { return nil }
        let c = URL(fileURLWithPath: ruta).standardizedFileURL.pathComponents
        return c.count > 2 && c[1] == "Volumes" ? "/Volumes/" + c[2] : nil
    }

    // Un archivo de un disco que no está montado no se ha borrado: sigue en custodia hasta que el disco vuelva.
    static func offline(_ u: URL) -> Bool {
        let c = u.standardizedFileURL.pathComponents   // ["/", "Volumes", "Disco", …]
        guard c.count > 2, c[1] == "Volumes" else { return false }
        return !mounted("/Volumes/" + c[2])
    }
}
