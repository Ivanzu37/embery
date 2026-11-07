// Embery · el Scriptorium en pantalla: la sala que cuelga del notch y la tarjeta de cada mesa.
import AppKit
import SwiftUI

struct TiraScriptorium: View {
    let h: Hueco
    @Environment(\.accessibilityReduceMotion) private var reducir

    var body: some View { SalaVista(sala: h.sala, reducir: reducir) }
}

// La sala en una vista de AppKit con su propio ritmo: 30 fps si alguna mesa trabaja o se mueve, 10 en reposo.
// Con «Reducir movimiento» no hay bucle: cuando algo cambia, la escena se asienta de golpe y se pinta una vez.
final class SalaNSView: NSView {
    let sala: Scriptorium
    var reducir = false { didSet { if reducir != oldValue { sala.sucio = true } } }
    private var link: CADisplayLink?
    private var antes: CFTimeInterval = 0
    private var ritmo: Float = 0

    init(_ sala: Scriptorium) { self.sala = sala; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    // Sin ratón: la ventana del Hueco decide (abrir desde el notch, tarjeta de mesa desde la sala).
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        link?.invalidate(); link = nil; antes = 0; ritmo = 0; sala.sucio = true
        if window != nil { link = (NSScreen.screens.first ?? NSScreen.main!).displayLink(target: self, selector: #selector(paso)); link?.add(to: .main, forMode: .common) }
    }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); needsDisplay = true }
    @objc private func paso(_ l: CADisplayLink) {
        guard window?.isVisible == true else { antes = 0; return }
        let dt = antes == 0 ? 1.0 / 30 : min(0.05, l.timestamp - antes); antes = l.timestamp
        let r: Float = reducir || !sala.trabaja ? 10 : 30
        if r != ritmo { ritmo = r; l.preferredFrameRateRange = CAFrameRateRange(minimum: r, maximum: r, preferred: r) }
        if reducir {
            if sala.sucio { sala.asentar(); needsDisplay = true }
            return
        }
        sala.actualizar(dt)
        needsDisplay = true
    }
    override func draw(_ r: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext, bounds.height > 0 else { return }
        let u = bounds.height / 110, l = Lienzo(c)
        l.save(); l.scale(u, u)
        sala.pintar(l, ancho: bounds.width / u, escala: u)
        l.restore()
    }
}

struct SalaVista: NSViewRepresentable {
    let sala: Scriptorium
    let reducir: Bool
    func makeNSView(context: Context) -> SalaNSView { let v = SalaNSView(sala); v.reducir = reducir; return v }
    func updateNSView(_ v: SalaNSView, context: Context) { v.reducir = reducir }
}

// La tarjeta de una mesa: nombre, tareas, contexto, bloque y ayudantes, y el camino a la conversación.
struct TarjetaMesa: View {
    let h: Hueco
    let m: Embery
    let ficha: FichaMesa

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ficha.viva ? ficha.nombre : String(localized: "Sin conversación")).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.texto).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Text(sub).font(.system(size: 11)).foregroundStyle(Color.sec).lineLimit(1)
            }
            if ficha.viva {
                tareas
                VStack(spacing: 0) {
                    dato(String(localized: "Contexto"), ficha.ctx.map { Double($0) / 100 }, contexto)
                    dato(String(localized: "Bloque 5 h"), h.feed.block.map { Double($0) / 100 }, bloque)
                    if ficha.ayudantes > 0 { dato(String(localized: "Ayudantes"), nil, "\(ficha.ayudantes)") }
                }
                Rectangle().fill(Color.linea).frame(height: 1)
                Button { ir() } label: {
                    HStack { Text(String(localized: "Ir a la conversación")); Spacer(); Text("↗") }.font(.system(size: 11)).foregroundStyle(Color.luz).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(width: 244, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radio.tarjetaHueco, style: .continuous).fill(Color.tarjeta))
        .overlay(RoundedRectangle(cornerRadius: Radio.tarjetaHueco, style: .continuous).strokeBorder(Color.linea))
        .accessibilityElement(children: .contain)
    }

    private var sub: String {
        guard ficha.viva else { return ficha.id == nil ? String(localized: "duerme") : String(localized: "se fue") }
        let archivo = m.ajustes.archivoEnTarjeta == true && !ficha.archivo.isEmpty && ["hojea", "escribe"].contains(ficha.actividad)
        return archivo ? "\(ficha.actividad) · \(ficha.archivo)" : ficha.actividad
    }

    @ViewBuilder private var tareas: some View {
        if ficha.tareas.isEmpty {
            Text("Sin tareas").font(.system(size: 11)).foregroundStyle(Color.ter)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(ficha.tareas.prefix(6).enumerated()), id: \.offset) { _, t in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(t.estado == .hecha ? "✓" : t.estado == .curso ? "→" : "·")
                            .foregroundStyle(t.estado == .hecha ? Color.luzOn : t.estado == .curso ? Color.luz : Color.ter).frame(width: 9)
                        Text(t.texto).strikethrough(t.estado == .hecha)
                            .foregroundStyle(t.estado == .hecha ? Color.ter : t.estado == .curso ? Color.texto : Color.sec).lineLimit(1)
                    }
                }
                if ficha.tareas.count > 6 { Text(String(localized: "+\(ficha.tareas.count - 6) más")).foregroundStyle(Color.ter).padding(.leading, 15) }
            }.font(.system(size: 11))
        }
    }

    private var contexto: String {
        guard let c = ficha.ctx else { return "—" }
        return c >= 85 ? String(localized: "\(c) % · compacta pronto") : "\(c) %"
    }
    private var bloque: String {
        guard let b = h.feed.block else { return "—" }
        return "\(b) % · " + (h.feed.blockResetAt.map { Registro.fecha($0, "H:mm") } ?? "—")
    }

    private func dato(_ etiqueta: String, _ v: Double?, _ valor: String) -> some View {
        HStack(spacing: 8) {
            Text(etiqueta).foregroundStyle(Color.ter).frame(width: 66, alignment: .leading).lineLimit(1)
            if let v { Barrita(v: v, ancho: 48) }
            Spacer(minLength: 0)
            Text(valor).foregroundStyle(Color.texto).lineLimit(1).monospacedDigit()
        }
        .font(.system(size: 11)).frame(minHeight: 18)
        .accessibilityElement(children: .combine)
    }

    private func ir() {
        guard let id = ficha.id, let s = h.live.sessions[id] else { return }
        h.tarjetaMesa = nil
        Focus.go(s)
    }
}
