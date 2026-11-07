import AppKit

// Proyectos de VS Code y Cursor sin permiso de Accesibilidad: cada carpeta abierta deja en
// workspaceStorage/<hash>/workspace.json su «folder»; la fecha de lo que hay dentro dice cuándo se usó.

enum Editor: String, CaseIterable {
    case vscode, cursor

    var bundle: String { self == .vscode ? "com.microsoft.VSCode" : "com.todesktop.230313mzl4w4u92" }
    var carpeta: String { self == .vscode ? "Code" : "Cursor" }
    var nombre: String { self == .vscode ? "VS Code" : "Cursor" }
    var instalado: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil }

    var workspaceStorage: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(carpeta)/User/workspaceStorage", isDirectory: true)
    }
}

enum EditorRecientes {
    struct Proyecto: Equatable { var carpeta: URL; var usado: Date; var nombre: String { carpeta.lastPathComponent } }

    // De la más reciente a la más antigua; solo carpetas locales que siguen existiendo, sin repetir.
    static func leer(_ storage: URL, cuantos: Int = 4) -> [Proyecto] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil) else { return [] }
        var todos: [Proyecto] = []
        for d in dirs {
            guard let data = try? Data(contentsOf: d.appendingPathComponent("workspace.json")),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let s = o["folder"] as? String, let u = URL(string: s), u.isFileURL,
                  fm.fileExists(atPath: u.path) else { continue }
            let hijos = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let usado = hijos.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max() ?? .distantPast
            todos.append(Proyecto(carpeta: u.standardizedFileURL, usado: usado))
        }
        var vistos = Set<String>()
        return Array(todos.sorted { $0.usado > $1.usado }.filter { vistos.insert($0.carpeta.path).inserted }.prefix(cuantos))
    }

    static func recientes(_ editores: [Editor], cuantos: Int = 4) -> [Proyecto] {
        let todos = editores.flatMap { leer($0.workspaceStorage, cuantos: cuantos) }.sorted { $0.usado > $1.usado }
        var vistos = Set<String>()
        return Array(todos.filter { vistos.insert($0.carpeta.path).inserted }.prefix(cuantos))
    }

    // El proyecto activo: el editor está delante y su carpeta es la última que se tocó.
    // shortcut: con varias ventanas abiertas puede elegir la que no está delante; si molesta, título por Accesibilidad.
    static func activo(_ editores: [Editor]) -> Proyecto? {
        guard let b = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              let e = editores.first(where: { $0.bundle == b }) else { return nil }
        return leer(e.workspaceStorage, cuantos: 1).first
    }

    static func abrir(_ carpeta: URL, con e: Editor = .vscode) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-b", e.bundle, carpeta.path]
        try? p.run()
    }
}
