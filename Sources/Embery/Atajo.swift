import AppKit
import Carbon.HIToolbox
import SwiftUI

extension Notification.Name {
    // El atajo (⌃⌥N de serie) desde cualquier app: el Hueco abre la Nota rápida.
    static let notaRapida = Notification.Name("embery.notaRapida")
}

// Tecla y modificadores en el formato de Carbon, más cómo se escriben para enseñarlos.
struct AtajoTeclas: Codable, Equatable {
    var tecla: Int
    var mods: Int
    var texto: String
    static let deSerie = AtajoTeclas(tecla: kVK_ANSI_N, mods: controlKey | optionKey, texto: "⌃⌥N")

    init(tecla: Int, mods: Int, texto: String) { self.tecla = tecla; self.mods = mods; self.texto = texto }
    // Hace falta ⌘, ⌃ o ⌥: con solo ⇧ (o nada) se comería esa tecla en todas las apps.
    init?(_ e: NSEvent) {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !f.isDisjoint(with: [.command, .control, .option]), let c = Self.nombre(e), !c.isEmpty else { return nil }
        tecla = Int(e.keyCode)
        mods = (f.contains(.command) ? cmdKey : 0) | (f.contains(.option) ? optionKey : 0) | (f.contains(.control) ? controlKey : 0) | (f.contains(.shift) ? shiftKey : 0)
        texto = (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "") + (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "") + c
    }

    // Lo que se escribe para la tecla. Flechas, F1–F20 y las de control llegan como caracteres internos de AppKit,
    // que se verían como un cuadro: se nombran aquí. nil: una tecla sin nombre, mejor no usarla de atajo.
    private static func nombre(_ e: NSEvent) -> String? {
        let especiales = [kVK_Space: "Espacio", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
                          kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                          kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟"]
        if let n = especiales[Int(e.keyCode)] { return n }
        guard let c = e.charactersIgnoringModifiers?.uppercased(), let u = c.unicodeScalars.first else { return nil }
        if (0xF704...0xF717).contains(u.value) { return "F\(u.value - 0xF703)" }
        if (0xF700...0xF8FF).contains(u.value) || u.properties.generalCategory == .control { return nil }
        return c
    }
}

// Clic y pulsa la combinación; esc cancela. `poner` devuelve false si otra app ya tiene ese atajo.
struct GrabadorAtajo: View {
    let actual: String
    let poner: (AtajoTeclas) -> Bool
    @State private var escuchando = false
    @State private var ocupado = false
    @State private var monitor: Any?

    var body: some View {
        Button(escuchando ? String(localized: "Pulsa el atajo…") : ocupado ? String(localized: "Ocupado · \(actual)") : actual) { escuchando ? parar() : escuchar() }
            .buttonStyle(.plain).foregroundStyle(escuchando ? Color.sec : Color.luz).font(.system(size: 12.5))
            .help(String(localized: "Clic y pulsa la combinación, con ⌘, ⌃ o ⌥; esc cancela"))
            .onDisappear(perform: parar)
    }
    private func escuchar() {
        escuchando = true; ocupado = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode != UInt16(kVK_Escape) {
                guard let a = AtajoTeclas(e) else { return nil }
                ocupado = !poner(a)
            }
            parar(); return nil
        }
    }
    private func parar() {
        escuchando = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// Atajo global con RegisterEventHotKey: no necesita el permiso de Accesibilidad y no ve otras teclas.
final class Atajo {
    private var ref: EventHotKeyRef?
    private var manejador: EventHandlerRef?
    private let aviso: Notification.Name

    init?(tecla: Int = kVK_ANSI_N, modificadores: Int = controlKey | optionKey, aviso: Notification.Name = .notaRapida) {
        self.aviso = aviso
        var tipo = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let yo = Unmanaged.passUnretained(self).toOpaque()
        let ok = InstallEventHandler(GetApplicationEventTarget(), { _, _, dato in
            guard let dato else { return OSStatus(eventNotHandledErr) }
            let a = Unmanaged<Atajo>.fromOpaque(dato).takeUnretainedValue()
            NotificationCenter.default.post(name: a.aviso, object: nil)
            return noErr
        }, 1, &tipo, yo, &manejador)
        let id = EventHotKeyID(signature: OSType(0x456D_6279), id: 1)   // 'Emby'
        // Otra app con el mismo atajo lo tiene reservado: sin atajo, la Nota rápida sigue en el Hueco.
        guard ok == noErr, RegisterEventHotKey(UInt32(tecla), UInt32(modificadores), id, GetApplicationEventTarget(), 0, &ref) == noErr else {
            if let manejador { RemoveEventHandler(manejador) }
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let manejador { RemoveEventHandler(manejador) }
    }
}
