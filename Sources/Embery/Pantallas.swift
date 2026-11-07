import AppKit

// Ajustes → General → Pantalla. Se guarda el UUID de la pantalla, que no cambia al reconectarla ni al reordenarlas.
enum Pantallas {
    // Copia del ajuste para que las coordenadas no necesiten el modelo; la pone la app al arrancar y al cambiarlo.
    nonisolated(unsafe) static var elegida: String?

    static func id(_ s: NSScreen) -> String? {
        guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let u = CGDisplayCreateUUIDFromDisplayID(n)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, u) as String
    }

    // La elegida si está conectada; si no (o en Automática), la del notch; si no hay, la principal (la primera).
    static func indice(elegida: String?, ids: [String?], notch: [Bool]) -> Int {
        if let e = elegida, let i = ids.firstIndex(of: e) { return i }
        return notch.firstIndex(of: true) ?? 0
    }

    static var actual: NSScreen {
        let s = NSScreen.screens
        guard !s.isEmpty else { return NSScreen.main! }
        return s[indice(elegida: elegida, ids: s.map(id), notch: s.map { $0.safeAreaInsets.top > 0 })]
    }

    static var opciones: [(id: String, nombre: String)] { NSScreen.screens.compactMap { s in id(s).map { ($0, s.localizedName) } } }
}
