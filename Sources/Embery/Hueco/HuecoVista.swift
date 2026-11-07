// Embery · el Hueco en pantalla: una forma negra que sale del notch, con la luz fría de Embery dentro.
// Medidas, estados y tiempos: handoff de H3 en planes/2026-10-17-fusion-hueco.md.
import AppKit
import SwiftUI

// La curva de la maqueta: llega suave y sin rebote.
private let RESORTE = Animation.spring(response: 0.55, dampingFraction: 0.9)
private let ANCHO_ABIERTO = 760.0, OREJA = 10.0

// Negro con las orejas cóncavas del notch real donde toca la barra; el rectángulo incluye las orejas.
struct FormaHueco: Shape {
    var radio: Double
    var animatableData: Double { get { radio } set { radio = newValue } }
    func path(in r: CGRect) -> Path {
        let x0 = r.minX + OREJA, x1 = r.maxX - OREJA, rr = min(radio, (x1 - x0) / 2, r.height - OREJA)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: x0, y: r.minY + OREJA), control: CGPoint(x: x0, y: r.minY))
        p.addLine(to: CGPoint(x: x0, y: r.maxY - rr))
        p.addQuadCurve(to: CGPoint(x: x0 + rr, y: r.maxY), control: CGPoint(x: x0, y: r.maxY))
        p.addLine(to: CGPoint(x: x1 - rr, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: x1, y: r.maxY - rr), control: CGPoint(x: x1, y: r.maxY))
        p.addLine(to: CGPoint(x: x1, y: r.minY + OREJA))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: x1, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct HuecoVista: View {
    let h: Hueco
    let m: Embery
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var brillo = 0.0

    var body: some View {
        let v = h.vista, n = h.notch
        ZStack(alignment: .top) {
            if v == .abierto {
                PestanasHueco(h: h, m: m)
                    .padding(.top, n.height + 8).padding(.horizontal, 18).padding(.bottom, 18)
                    .frame(width: ANCHO_ABIERTO)
                    // Entra cuando la forma ya ha crecido; al cerrar se va al instante, antes de que la forma encoja.
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.3).delay(reducir ? 0 : 0.25)),
                                            removal: .opacity.animation(.easeOut(duration: 0.1))))
            } else if v == .scriptorium {
                TiraScriptorium(h: h)
                    .frame(width: ancho(v, n), height: alto(v, n))
                    .transition(.opacity.animation(.easeOut(duration: 0.2)))
            } else {
                Alas(h: h, m: m, vista: v)
                    .frame(width: ancho(v, n), height: alto(v, n))
                    .transition(.opacity.animation(.easeOut(duration: 0.2)))
            }
        }
        .padding(.horizontal, OREJA)
        // Nada asoma fuera del negro mientras la forma cambia de tamaño.
        .clipShape(FormaHueco(radio: radio(v)))
        .background(FormaHueco(radio: radio(v)).fill(Color.black)
            .shadow(color: Color.luz.opacity(0.35 * brillo), radius: 13))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { h.marco = $0 }
        .animation(reducir ? nil : RESORTE, value: v)
        .animation(reducir ? nil : RESORTE, value: h.feed.block)
        .animation(reducir ? nil : RESORTE, value: h.mesas)
        .animation(reducir ? nil : RESORTE, value: lineasNota)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: h.feed.doneId) { _, id in if !id.isEmpty, !h.callando { destello() } }
        .onChange(of: v) { _, nueva in if nueva == .espera { destello() } }
        .accessibilityElement(children: v == .abierto || v == .permiso || v == .nota || v == .carpeta ? .contain : .combine)
        .accessibilityLabel(etiqueta(v))
        .accessibilityAction { h.abierto.toggle() }
        .overlay(alignment: .topLeading) { tarjetaMesa(v) }
    }

    // Debajo de la sala, alineada con el taburete de la mesa y sujeta a los bordes con 8 pt.
    @ViewBuilder private func tarjetaMesa(_ v: Hueco.Vista) -> some View {
        GeometryReader { g in
            if v == .scriptorium, let i = h.tarjetaMesa, i < h.fichas.count {
                let r = h.marco, u = r.height / 110, x = r.minX + OREJA + (Double(i) * Scriptorium.modulo + 92) * u
                TarjetaMesa(h: h, m: m, ficha: h.fichas[i])
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { h.marcoTarjeta = $0 }
                    .offset(x: clamp(x, 8, g.size.width - 252), y: r.maxY + 8)
                    .transition(reducir ? .opacity : .opacity.combined(with: .offset(y: 4)))
                    .id(i)
            }
        }
        .animation(salida(Dura.cuerpo), value: h.tarjetaMesa)
    }

    private func destello() {
        guard !reducir else { return }
        brillo = 1
        withAnimation(.easeOut(duration: Dura.destello)) { brillo = 0 }
    }

    private var lineasNota: Int { min(4, h.borrador.components(separatedBy: "\n").count) }

    private func etiqueta(_ v: Hueco.Vista) -> String {
        switch v {
        case .abierto: String(localized: "El Hueco")
        case .scriptorium: h.resumenSala
        case .permiso: String(localized: "Claude pide permiso: \(h.feed.permTool) \(h.feed.permCommand)")
        case .espera: String(localized: "Te esperan: \(h.espera?.texto ?? "")")
        case .nota: String(localized: "Nota rápida")
        default: String(localized: "Abrir el Hueco")
        }
    }

    // Lo que asoma a cada lado del notch, estado por estado (tabla de la especificación v5).
    private func ala(_ v: Hueco.Vista) -> Double {
        switch v {
        // medido a 12 pt: «proyecto · 3 conversaciones» 189, «1 conversación · 1 permiso» 152, «proyecto · 12:33» 120 (+21 de márgenes)
        case .trabajo: 210
        case .espera: 180
        case .hecho: 150
        case .nivel: 160
        case .permiso: 190
        case .aviso, .nota: 170
        case .carpeta: 160
        case .archivo: 60
        default: 0
        }
    }
    private func ancho(_ v: Hueco.Vista, _ n: CGSize) -> Double {
        switch v {
        case .abierto: ANCHO_ABIERTO
        case .scriptorium: max(Scriptorium.ancho(mesas: h.mesas), n.width + 140)
        default: n.width + 2 * ala(v)
        }
    }
    private func alto(_ v: Hueco.Vista, _ n: CGSize) -> Double {
        switch v {
        case .reposo: (h.feed.block == nil && h.avanceFoco == nil) || !h.hilo ? n.height : n.height + 6
        case .permiso: n.height + 46
        case .archivo: n.height + 60
        case .carpeta: n.height + 68
        case .nota: n.height + 84 + Double(lineasNota - 1) * 16
        case .scriptorium: n.height + 78
        default: n.height
        }
    }
    private func radio(_ v: Hueco.Vista) -> Double {
        switch v {
        case .abierto: 28
        case .permiso, .archivo, .carpeta, .nota, .scriptorium: 22
        default: 14
        }
    }
}

// Lo que asoma a los lados del notch con el Hueco cerrado y, en los estados con cuerpo, lo que cuelga debajo.
private struct Alas: View {
    let h: Hueco
    let m: Embery
    let vista: Hueco.Vista
    @Environment(\.accessibilityReduceMotion) private var reducir

    var body: some View {
        let n = h.notch, f = h.feed
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                switch vista {
                case .trabajo:
                    Orbe(respira: true); Text(h.actividad.texto).foregroundStyle(Color.sec)
                    Spacer(minLength: n.width)
                    Text(lado(h.proyecto, f.working == 1 ? String(localized: "1 conversación") : String(localized: "\(f.working) conversaciones"))).foregroundStyle(Color.sec)
                case .permiso:
                    PuntoAviso(); Text("Permiso")
                    Spacer(minLength: n.width)
                    TimelineView(.periodic(from: .now, by: 1)) { c in
                        Text(lado(f.permProject, f.permSince.map { hace($0, c.date) } ?? "")).foregroundStyle(Color.sec).truncationMode(.tail)
                    }
                case .hecho:
                    Orbe(respira: false); Text("Hecho")
                    Spacer(minLength: n.width)
                    Text(lado(f.doneProject, f.doneTime)).foregroundStyle(Color.sec)
                case .espera:
                    Orbe(respira: false).opacity(0.6); Text("Te esperan")
                    Spacer(minLength: n.width)
                    Text(h.espera?.texto ?? "").foregroundStyle(Color.sec)
                case .aviso:
                    if f.warnTag == "disco" { Image(systemName: "externaldrive").foregroundStyle(Color.sec); Text(f.warnLabel) }
                    else { Text("\(f.warnLabel) · \(f.warnValue)") }
                    Spacer(minLength: n.width)
                    Text(f.warnNote).foregroundStyle(Color.sec).truncationMode(.tail)
                case .nivel:
                    if let l = h.nivel {
                        Image(systemName: l.kind == .brightness ? "sun.max.fill" : l.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        Spacer(minLength: n.width)
                        // barra + cifra + márgenes = 148 pt, dentro del ala de 160: nada se mete bajo el notch físico
                        Barrita(v: l.muted ? 0 : l.value, ancho: 72)
                        Text(l.muted ? String(localized: "silencio") : "\(l.percent) %").foregroundStyle(Color.sec).monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                case .archivo:
                    Text(String(localized: "Nido")); Spacer(minLength: n.width)
                    Text(h.arrastrados == 1 ? String(localized: "1 archivo") : String(localized: "\(h.arrastrados) archivos")).foregroundStyle(Color.sec)
                case .carpeta:
                    Text("Carpeta"); Spacer(minLength: n.width)
                    Text(h.carpeta?.lastPathComponent ?? "").foregroundStyle(Color.sec).truncationMode(.middle)
                case .nota:
                    Text(String(localized: "Nota rápida")); Spacer(minLength: n.width)
                    Text(m.destinoNota).foregroundStyle(Color.sec).truncationMode(.middle)
                default:
                    Spacer(minLength: 0)
                }
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.texto).lineLimit(1)
            .padding(.horizontal, 14).frame(height: n.height)
            .contentShape(Rectangle())
            // Con cuerpo, el panel no se abre al pasar: se abre con un clic aquí arriba.
            .onTapGesture { if !h.abrePorEncima, vista != .nota { h.abierto = true } }

            switch vista {
            case .permiso:
                PermisoFila(h: h, f: f, teclas: true).padding(.horizontal, 14).transition(cuerpo)
            case .archivo:
                VStack(spacing: 4) {
                    Gota(cuenta: h.gotas)
                    Text("Suelta para guardar en el Nido").font(.system(size: 11.5)).foregroundStyle(Color.sec)
                }.padding(.top, 6).transition(cuerpo)
            case .carpeta:
                Zonas(h: h).padding(.horizontal, 14).padding(.top, 4).transition(cuerpo)
            case .nota:
                NotaRapida(h: h, m: m).padding(.horizontal, 14).padding(.top, 2).transition(cuerpo)
            case .reposo where h.hilo:
                Spacer(minLength: 0)
                // En foco, el hilo es el avance de la sesión; si no, lo que queda del bloque de 5 h.
                if let a = h.avanceFoco {
                    Capsule().fill(Color.luz.opacity(0.85)).frame(width: max(4, (n.width - 40) * clamp(a, 0, 1)), height: 2).padding(.bottom, 3)
                } else if let b = f.block {
                    Capsule().fill(Color.luz.opacity(0.55)).frame(width: max(4, (n.width - 40) * Double(100 - b) / 100), height: 2).padding(.bottom, 3)
                }
            default:
                EmptyView()
            }
            Spacer(minLength: 0)
        }
    }

    // El cuerpo entra tras las alas (sube 6 pt) y se va antes de que encoja la forma.
    private var cuerpo: AnyTransition {
        .asymmetric(insertion: reducir ? .opacity.animation(.easeOut(duration: 0.2))
                        : .opacity.combined(with: .offset(y: -6)).animation(.easeOut(duration: 0.3).delay(0.2)),
                    removal: .opacity.animation(.easeOut(duration: 0.1)))
    }
    private func lado(_ a: String, _ b: String) -> String { [a, b].filter { !$0.isEmpty }.joined(separator: " · ") }
}

func hace(_ d: Date, _ ahora: Date = Date()) -> String {
    let s = max(0, Int(ahora.timeIntervalSince(d)))
    return s < 60 ? String(localized: "hace \(s) s") : s < 3600 ? String(localized: "hace \(s / 60) min") : String(localized: "hace \(s / 3600) h")
}

// Herramienta, comando y los dos botones; en el Hueco cerrado y bajo la conversación que espera.
private struct PermisoFila: View {
    let h: Hueco
    let f: Feed
    var teclas = false
    var body: some View {
        HStack(spacing: 8) {
            if h.yaNoEspera == f.permId {
                Text("Claude ya no espera").font(.system(size: 11.5)).foregroundStyle(Color.sec)
                Spacer(minLength: 0)
            } else {
                Text(f.permTool).font(Tipo.chip).lineLimit(1).padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Color.capsula))
                Text(f.permCommand).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color.sec)
                    .lineLimit(1).truncationMode(.tail).help(f.permCommand)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Denegar") { h.responder(f.permId, permitir: false) }
                    .buttonStyle(Pastilla()).keyboardShortcut(teclas ? KeyboardShortcut.cancelAction : nil)
                    .accessibilityHint(String(localized: "Claude no podrá usar \(f.permTool)"))
                Button("Permitir") { h.responder(f.permId, permitir: true) }
                    .buttonStyle(Pastilla(luz: true)).keyboardShortcut(teclas ? KeyboardShortcut(.return, modifiers: .command) : nil)
                    .accessibilityHint(String(localized: "Claude sigue con \(f.permTool)"))
            }
        }
        .frame(height: 38)
        .animation(.easeOut(duration: 0.2), value: h.yaNoEspera)
    }
}

// Cápsula de 24 pt para los botones del permiso.
struct Pastilla: ButtonStyle {
    var luz = false
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 11.5, weight: .semibold)).foregroundStyle(luz ? Color.tinta : Color.texto)
            .padding(.horizontal, 12).frame(height: 24)
            .background(Capsule().fill(luz ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#dfe9ff"), .luzOn], startPoint: .top, endPoint: .bottom))
                                        : AnyShapeStyle(Color.capsula)))
            .contentShape(Capsule())
            .scaleEffect(c.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: c.isPressed)
    }
}

// Dos sitios donde soltar una carpeta: el Nido o una conversación nueva de Claude Code.
private struct Zonas: View {
    let h: Hueco
    var body: some View {
        HStack(spacing: 8) {
            zona(0, "tray.and.arrow.down", String(localized: "Guardar en el Nido"), String(localized: "queda a mano en el Hueco"))
            zona(1, "terminal", String(localized: "Abrir Claude Code aquí"), h.carpeta.map { String(localized: "una conversación nueva en \($0.lastPathComponent)") } ?? String(localized: "una conversación nueva en la carpeta"))
        }.frame(height: 52)
    }
    private func zona(_ i: Int, _ icono: String, _ t: String, _ sub: String) -> some View {
        let on = h.zona == i
        return HStack(spacing: 9) {
            Image(systemName: icono).font(.system(size: 14))
            VStack(alignment: .leading, spacing: 1) {
                Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(on ? Color.luz : Color.texto)
                Text(sub).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(on ? Color.texto : Color.sec)
        .padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.luz.opacity(on ? 0.04 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Color.luz.opacity(0.55) : Color.linea))
        .animation(.easeOut(duration: Dura.resalte), value: on)
    }
}

// ⌃⌥N: una caja que cuelga del notch. ↩ guarda, ⇧↩ salta de línea, esc cierra sin perder el texto.
private struct NotaRapida: View {
    @Bindable var h: Hueco
    let m: Embery
    @FocusState private var enfocado: Bool
    @State private var guardada = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(localized: "Apunta lo que sea…"), text: $h.borrador, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...4)
                .focused($enfocado)
                .padding(.horizontal, 11).frame(minHeight: 34)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.capsula))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.luz.opacity(enfocado ? 0.45 : 0)))
                .onKeyPress(.return, phases: .down) { k in
                    if k.modifiers.contains(.shift) { h.borrador += "\n"; return .handled }
                    guardar(); return .handled
                }
                .onKeyPress(.escape) { h.cerrarNota(); return .handled }
            HStack {
                if guardada { Text("\(Text("Guardada").fontWeight(.semibold)) en \(m.ajustes.entrada)").foregroundStyle(Color.luz) }
                else if m.destinoListo { Text(String(localized: "↩ guarda · ⇧↩ salto de línea")) }
                else { Text(String(localized: "se guardará al elegir la bóveda")) }
                Spacer()
                Text("esc cierra")
            }.font(.system(size: 11)).foregroundStyle(Color.sec).animation(.easeOut(duration: 0.2), value: guardada)
        }
        .onAppear { h.escribiendo = true; DispatchQueue.main.async { enfocado = true } }
        .onDisappear { h.escribiendo = false }
    }

    private func guardar() {
        guard !guardada, !h.borrador.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        m.capturar(h.borrador); Sonido.tocar(.gota)
        guardada = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { h.borrador = ""; guardada = false; h.cerrarNota() }
    }
}

private struct Orbe: View {
    let respira: Bool
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var dentro = false
    var body: some View {
        Circle().fill(RadialGradient(colors: [.white, .luz, .luzOn.opacity(0.25)], center: UnitPoint(x: 0.38, y: 0.34), startRadius: 0, endRadius: 7))
            .frame(width: 14, height: 14)
            .scaleEffect(respira ? (dentro ? 1.04 : 0.94) : 1).brightness(respira ? (dentro ? 0.06 : -0.1) : 0)
            .onAppear {
                guard respira, !reducir else { return }
                withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) { dentro = true }
            }
    }
}

private struct PuntoAviso: View {
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var late = false
    var body: some View {
        Circle().fill(Color.aviso).frame(width: 9, height: 9)
            .opacity(reducir ? 1 : late ? 1 : 0.45)
            .shadow(color: Color.aviso.opacity(late ? 0.35 : 0), radius: 10)
            .onAppear {
                guard !reducir else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { late = true }
            }
    }
}

// La gota de luz que cae al Nido mientras sostienes el archivo encima.
private struct Gota: View {
    let cuenta: Int
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var cae = false
    var body: some View {
        Ellipse().fill(RadialGradient(colors: [.white, .luz, .luzOn.opacity(0.4)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 9))
            .frame(width: 12, height: 16)
            .offset(y: cae ? 10 : -4).opacity(cae ? 0.2 : 1).scaleEffect(cae ? 0.85 : 0.65)
            .onAppear {
                guard !reducir else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) { cae = true }
            }
    }
}

struct Barrita: View {
    let v: Double
    var ancho = 36.0
    var body: some View {
        Capsule().fill(Color.white.opacity(0.1)).frame(width: ancho, height: 4)
            .overlay(alignment: .leading) { Capsule().fill(Color.luz).frame(width: ancho * clamp(v, 0, 1)) }
    }
}

// MARK: Panel abierto

// Trabajo: Conversaciones, Aliento y Nido a la izquierda; Proyectos recientes y Huella a la derecha.
struct PanelHueco: View {
    let h: Hueco
    @Bindable var m: Embery
    var body: some View {
        let proyectos = m.activo(.vscode) && !m.editores.isEmpty
        HStack(alignment: .top, spacing: 10) {
            if h.claude {
                VStack(spacing: 10) { Conversaciones(h: h, m: m); Aliento(f: h.feed); Nido(h: h) }
                    .frame(width: IZQUIERDA)
            }
            VStack(spacing: 10) {
                if proyectos { ProyectosTarjeta(h: h, m: m) }
                if h.claude { Huella(dias: h.dias) }
            }.frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color.texto)
    }
}

struct Raya: Shape {
    func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: r.minX, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
}

// Vacío de una tarjeta: 12 en sec y una segunda línea 11 en ter.
struct Vacio: View {
    let t: String
    var sub = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 12)).foregroundStyle(Color.sec)
            if !sub.isEmpty { Text(sub).font(.system(size: 11)).foregroundStyle(Color.ter) }
        }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
    }
}

func titulo(_ t: String, _ sub: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(t).font(.system(size: 12.5, weight: .semibold))
        Spacer(minLength: 6)
        Text(sub).font(.system(size: 11)).foregroundStyle(Color.sec).lineLimit(1)
    }
}

extension View {
    func cajaHueco() -> some View { padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).tarjeta() }
}

private struct Conversaciones: View {
    let h: Hueco
    @Bindable var m: Embery
    var body: some View {
        let filas = h.feed.rows
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titulo(String(localized: "Conversaciones"), filas.isEmpty ? "" : filas.count == 1 ? String(localized: "1 activa") : String(localized: "\(filas.count) activas"))
                Button(m.ajustes.scriptoriumAbierto == true ? String(localized: "Cerrar el Scriptorium") : String(localized: "Abrir el Scriptorium")) {
                    m.ajustes.scriptoriumAbierto = !(m.ajustes.scriptoriumAbierto ?? false)
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.luz)
            }.padding(.bottom, 4)
            if filas.isEmpty {
                Vacio(t: String(localized: "Nada en marcha"), sub: String(localized: "Las conversaciones de Claude Code salen aquí"))
            }
            ForEach(Array(filas.enumerated()), id: \.element.id) { i, r in
                if i > 0 { Rectangle().fill(Color.linea).frame(height: 1) }
                FilaConversacion(r: r) { h.live.focus(r.id) }
                // La que espera lleva debajo su permiso, separado por una línea discontinua.
                if r.id == h.feed.permId {
                    Raya().stroke(Color.linea, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
                    PermisoFila(h: h, f: h.feed)
                }
            }
        }.cajaHueco()
    }
}

private struct FilaConversacion: View {
    let r: Row
    let ir: () -> Void
    @State private var encima = false
    var body: some View {
        Button(action: ir) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.title.isEmpty ? r.project : r.title).font(.system(size: 13)).lineLimit(1)
                    Text("\(r.project) · \(r.model) · \(Text(r.status).foregroundColor(r.kind == .perm ? .aviso : .sec))")
                        .font(.system(size: 11)).foregroundStyle(Color.sec).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let c = r.ctx { Barrita(v: Double(c) / 100) }
                Text(r.ctx.map { "\($0)%" } ?? r.tokens.map { TokenLedger.short($0) } ?? "—")
                    .font(.system(size: 12)).monospacedDigit().frame(width: 34, alignment: .trailing)
                Text("›").font(.system(size: 13)).foregroundStyle(Color.ter).opacity(encima ? 1 : 0)
            }
            .padding(.vertical, 8).padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(encima ? 0.03 : 0)))
            .padding(.horizontal, -6)
        }
        .buttonStyle(Hunde(escala: 0.98))
        .onHover { encima = $0 }
        .animation(.easeOut(duration: 0.2), value: encima)
        .accessibilityLabel("\(r.title.isEmpty ? r.project : r.title), \(r.status)")
        .accessibilityHint(String(localized: "Lleva a la conversación"))
    }
}

private struct Aliento: View {
    let f: Feed
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                limite(String(localized: "Aliento"), String(localized: "bloque 5 h"), f.block, f.blockResetAt == nil ? f.blockReset : String(localized: "vuelve en \(f.blockReset)"))
                limite(String(localized: "Semana"), String(localized: "7 días"), f.week, f.weekResetAt == nil ? f.weekReset : String(localized: "se renueva el \(f.weekReset)"))
            }
            titulo("", String(localized: "hace 24 h → ahora")).overlay(alignment: .leading) { Text(String(localized: "Aliento · últimas 24 h")).font(.system(size: 11)).foregroundStyle(Color.sec) }
                .padding(.top, 12)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(f.curve.enumerated()), id: \.offset) { _, v in
                    // Sin uso, la barra queda a 2 pt y 25 %: se ve la forma de la curva.
                    RoundedRectangle(cornerRadius: 1).fill(Color.luz.opacity((v ?? 0) > 0 ? 0.35 : 0.25 * 0.35))
                        .frame(height: max(2, (v ?? 0) * 0.34))
                }
            }.frame(height: 34).padding(.top, 6)
        }.cajaHueco()
    }

    private func limite(_ t: String, _ sub: String, _ usado: Int?, _ nota: String) -> some View {
        let queda = usado.map { max(0, 100 - $0) }
        return VStack(alignment: .leading, spacing: 0) {
            titulo(t, sub)
            Text(queda.map { $0 == 1 ? String(localized: "queda 1 %") : String(localized: "quedan \($0) %") } ?? "—")
                .font(.system(size: 18, weight: .semibold)).monospacedDigit().padding(.top, 2)
            Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(LinearGradient(colors: [Color(hex: "#8fb3ff"), .white], startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * Double(queda ?? 0) / 100)
                    }
                }.padding(.vertical, 6)
            Text(nota).font(.system(size: 11)).foregroundStyle(Color.sec).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Nido: View {
    let h: Hueco
    @State private var copiado = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titulo(String(localized: "Nido"), String(localized: "\(h.archivos.count) de \(Shelf.max)"))
                if !h.archivos.isEmpty {
                    Button(copiado ? String(localized: "Copiadas") : String(localized: "Copiar rutas")) {
                        h.nido.copyPaths(); Sonido.tocar(.gota); copiado = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiado = false }
                    }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.luz)
                    .help(String(localized: "Copia las rutas, una por línea, para pegarlas en Claude Code"))
                }
            }.padding(.bottom, 8)
            if h.archivos.isEmpty {
                Text("Arrastra archivos al Hueco").font(.system(size: 11.5)).foregroundStyle(Color.sec)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(h.archivos, id: \.self) { u in
                        HStack(spacing: 6) {
                            Image(nsImage: Shelf.icon(u))
                            Text(Shelf.shortName(u)).lineLimit(1)
                        }
                        .font(.system(size: 11.5)).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: "#1f1f22")))
                        .overlay {
                            DragSource(url: u, began: { h.sacando = true }, ended: { p in
                                h.sacando = false
                                if !h.marcoPantalla.contains(p) { h.sacar(u) }
                            })
                        }
                        .accessibilityLabel(u.lastPathComponent)
                    }
                }
            }
            if let r = h.raices {
                HStack(spacing: 6) {
                    Circle().fill(h.disco ? Color.luz : Color.sec).frame(width: 6, height: 6)
                    Text(h.disco ? String(localized: "Raíces · \(r.name) montado") : String(localized: "Sin raíces · \(r.name) no está montado"))
                }.font(.system(size: 11)).foregroundStyle(Color.sec).padding(.top, 10)
            }
        }.cajaHueco()
    }
}

struct Huella: View {
    let dias: [String: Int]
    var body: some View {
        let hoy = Date(), cal = Calendar.current
        // 13 semanas por columnas; la última celda es hoy.
        let valores = (0..<91).map { i in dias[TokenLedger.dayFormat.string(from: cal.date(byAdding: .day, value: i - 90, to: hoy)!)] ?? 0 }
        let tope = max(1, valores.max() ?? 1)
        VStack(alignment: .leading, spacing: 0) {
            titulo(String(localized: "Huella"), String(localized: "\(TokenLedger.short(valores[90])) hoy · 13 semanas")).padding(.bottom, 8)
            HStack(spacing: 0) {
                ForEach(0..<13, id: \.self) { c in
                    if c > 0 { Spacer(minLength: 3) }
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { f in
                            let i = c * 7 + f, v = Double(valores[i]) / Double(tope)
                            RoundedRectangle(cornerRadius: 3).fill(v > 0 ? Color.luz.opacity([0.12, 0.24, 0.4, 0.62][min(3, Int(v * 4))]) : Color.white.opacity(0.05))
                                .frame(width: 11, height: 11)
                                .overlay { if i == 90 { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.5), lineWidth: 1) } }
                        }
                    }
                }
            }
        }
        .cajaHueco()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Huella: \(TokenLedger.short(valores[90])) tokens hoy"))
    }
}

// MARK: Ventana

// Recibe los archivos que sueltas sobre el Hueco.
final class HuecoHost: NSHostingView<HuecoVista> {
    weak var hueco: Hueco?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Una carpeta sobre la zona de Claude Code vale aunque el Nido esté lleno.
    private var acepta: Bool { hueco.map { $0.claude && ($0.nido.room > 0 || ($0.carpeta != nil && $0.zona == 1)) } ?? false }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { mirarZona(s); return acepta ? .copy : [] }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { mirarZona(s); return acepta ? .copy : [] }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        guard let h = hueco, acepta,
              let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        if let c = h.carpeta, h.zona == 1 { h.abrirClaude(c) } else { h.recibir(urls) }
        return true
    }
    // Zona bajo el cursor: la mitad izquierda del cuerpo es el Nido, la derecha Claude Code. La fila de arriba no cambia nada.
    private func mirarZona(_ s: NSDraggingInfo) {
        guard let h = hueco, h.carpeta != nil else { return }
        let p = convert(s.draggingLocation, from: nil), y = isFlipped ? p.y : bounds.height - p.y
        guard y > h.marco.minY + h.notch.height else { return }
        let z = p.x < h.marco.midX ? 0 : 1
        if z != h.zona { h.zona = z }
    }
}

// Coloca el Hueco en el notch y decide cada fotograma si se abre, si acepta el ratón y si se esconde.
// No tiene reloj: lo mueve Delegado.paso.
final class HuecoVentana {
    let h: Hueco
    let m: Embery
    // Puede ser ventana clave para escribir en Captura y en Tres de hoy sin activar la app.
    private let panel = Flotante(nivel: NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3), clave: true)
    private var sobreDesde: Double?, fueraDesde: Double?
    private var mesaSobre: Int?, mesaDesde = 0.0, fueraMesaDesde: Double?
    private var estabaPulsado = false, cambiosArrastre = 0
    private var completa = false
    private var oculto = false
    private var comprobaciones: [DispatchWorkItem] = []
    private var leidoArrastre = -1
    // La app que tenía el teclado antes de la Nota rápida: lo recupera al cerrarla.
    private var antesDeNota: NSRunningApplication?

    init(_ h: Hueco, _ m: Embery) {
        self.h = h; self.m = m
        let host = HuecoHost(rootView: HuecoVista(h: h, m: m))
        host.hueco = h
        host.registerForDraggedTypes([.fileURL])
        panel.contentView = host
        panel.ignoresMouseEvents = true
        // Un clic en otra app quita el teclado al Hueco: deja de contar como «escribiendo» y ya se puede cerrar.
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak h] _ in h?.escribiendo = false }
        colocar()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: .notaRapida, object: nil, queue: .main) { [weak h] _ in h?.abrirNota() }
        let ws = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.programarComprobacion() }
        }
    }

    private var pantalla: NSScreen { Pantallas.actual }

    // Lo llama la app al cambiar de pantalla o de ajuste, junto al resto de ventanas.
    func colocar() {
        let s = pantalla
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            h.notch = CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
        } else {
            // Sin notch: una píldora que cuelga de la barra de menús, de su mismo alto.
            let barra = s.frame.maxY - s.visibleFrame.maxY
            h.notch = CGSize(width: 180, height: barra > 10 ? barra : 24)
        }
        let w = ANCHO_ABIERTO + 2 * OREJA + 40, alto = h.notch.height + 640
        panel.setFrame(NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - alto, width: w, height: alto), display: true)
        programarComprobacion()
    }

    // El Hueco en coordenadas de la escena (la pantalla elegida con y hacia abajo), o nil si está escondido.
    var marcoEscritorio: CGRect? {
        guard !oculto else { return nil }
        let p = pantalla, f = panel.frame, r = h.marco
        return CGRect(x: f.minX + r.minX - p.frame.minX, y: p.frame.maxY - f.maxY + r.minY, width: r.width, height: r.height)
    }

    func paso(_ ahora: Double) {
        notaYTeclado()
        let o = (completa || !h.visible) && !h.nota
        if o != oculto {
            oculto = o
            if o { h.abierto = false }
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = o ? 0.12 : 0.25; panel.animator().alphaValue = o ? 0 : 1 }
        }
        if oculto { if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }; return }
        let m = NSEvent.mouseLocation, f = panel.frame
        let p = CGPoint(x: m.x - f.minX, y: f.maxY - m.y)
        let r = h.marco
        if h.abierto { h.marcoPantalla = NSRect(x: f.minX + r.minX, y: f.maxY - r.maxY, width: r.width, height: r.height) }

        // ¿Arrastras un archivo? Botón pulsado y el portapapeles de arrastre cambió y trae archivos.
        let pulsado = NSEvent.pressedMouseButtons & 1 != 0
        var arrastra = false
        if pulsado {
            let pb = NSPasteboard(name: .drag)
            if !estabaPulsado { cambiosArrastre = pb.changeCount }
            arrastra = h.claude && !h.sacando && !completa && pb.changeCount != cambiosArrastre && pb.types?.contains(.fileURL) == true
            if arrastra, pb.changeCount != leidoArrastre {
                leidoArrastre = pb.changeCount
                let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
                h.arrastrados = urls.count
                h.carpeta = urls.first.flatMap { u in
                    let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                    return v?.isDirectory == true && v?.isPackage != true ? u : nil
                }
                h.zona = 0
            }
        }
        if !arrastra, h.carpeta != nil { h.carpeta = nil }
        estabaPulsado = pulsado
        let zona = CGRect(x: r.minX - 60, y: 0, width: r.width + 120, height: r.height + 90)
        let cerca = arrastra && zona.contains(p)
        if h.arrastrando != cerca { h.arrastrando = cerca }

        // Se abre con intención (180 ms encima) y se cierra 300 ms después de salir con 12 pt de margen.
        let dentro = !completa && !arrastra && r.insetBy(dx: -4, dy: -4).contains(p)
        // Escribiendo no se cierra al apartar el ratón; Esc o un clic fuera lo cierran.
        if h.sacando || h.escribiendo {
            fueraDesde = nil
        } else if dentro {
            fueraDesde = nil
            // Con la sala a la vista, el Hueco se abre desde el notch; la sala enseña la tarjeta de cada mesa.
            let desdeNotch = h.vista != .scriptorium || p.y - r.minY < h.notch.height
            sobreDesde = desdeNotch ? sobreDesde ?? ahora : nil
            if !h.abierto, h.abrePorEncima, let d = sobreDesde, ahora - d > 0.18 {
                // Desde «Te esperan» se abre en Trabajo.
                if h.vista == .espera { self.m.ajustes.pestanaHueco = PestanaHueco.trabajo.rawValue; h.verEspera() }
                h.abierto = true
            }
        } else {
            sobreDesde = nil
            if h.abierto && !r.insetBy(dx: -12, dy: -12).contains(p) {
                fueraDesde = fueraDesde ?? ahora
                if let d = fueraDesde, ahora - d > 0.3 { h.abierto = false; fueraDesde = nil }
            } else { fueraDesde = nil }
        }
        let enTarjeta = tarjetaMesa(p, r, ahora, dentro: dentro)
        // Fuera de la forma, el ratón pasa a lo de debajo. Cada cambio es un mensaje al servidor de ventanas.
        if h.escribiendo && !h.abierto && !h.nota { h.escribiendo = false }
        let ignora = !(dentro || cerca || enTarjeta || ((h.abierto || h.nota) && r.contains(p)))
        if panel.ignoresMouseEvents != ignora { panel.ignoresMouseEvents = ignora }
    }

    // Tarjeta de mesa: sale tras 350 ms con el ratón sobre esa mesa y se va 300 ms después de salir de la sala y de ella.
    private func tarjetaMesa(_ p: CGPoint, _ r: CGRect, _ ahora: Double, dentro: Bool) -> Bool {
        guard h.vista == .scriptorium, r.height > 0 else {
            if h.tarjetaMesa != nil { h.tarjetaMesa = nil }
            mesaSobre = nil; fueraMesaDesde = nil
            return false
        }
        let enTarjeta = h.tarjetaMesa != nil && h.marcoTarjeta.insetBy(dx: -4, dy: -4).contains(p)
        if dentro && p.y - r.minY >= h.notch.height {
            let x = (p.x - r.minX - OREJA) / (r.height / 110)
            let i = max(0, min(h.fichas.count - 1, Int(((x - 92) / Scriptorium.modulo).rounded(.down))))
            if i != mesaSobre { mesaSobre = i; mesaDesde = ahora }
            if h.tarjetaMesa != i, ahora - mesaDesde > Dura.intencion { h.tarjetaMesa = i }
            fueraMesaDesde = nil
        } else {
            mesaSobre = nil
            if enTarjeta || h.tarjetaMesa == nil { fueraMesaDesde = nil }
            else {
                fueraMesaDesde = fueraMesaDesde ?? ahora
                if let d = fueraMesaDesde, ahora - d > 0.3 { h.tarjetaMesa = nil; fueraMesaDesde = nil }
            }
        }
        return enTarjeta
    }

    // La Nota rápida toma el teclado sin activar Embery y lo devuelve al cerrarse.
    private func notaYTeclado() {
        if h.nota, !panel.isKeyWindow {
            if antesDeNota == nil { antesDeNota = NSWorkspace.shared.frontmostApplication }
            panel.ignoresMouseEvents = false
            panel.makeKey()
        } else if !h.nota, let app = antesDeNota {
            antesDeNota = nil
            if panel.isKeyWindow { panel.orderOut(nil); panel.orderFrontRegardless() }
            if app.processIdentifier != ProcessInfo.processInfo.processIdentifier { app.activate() }
        }
    }

    // Pantalla completa: se mira al cambiar de espacio o de app, y otra vez cuando acaba la animación.
    private func programarComprobacion() {
        comprobaciones.forEach { $0.cancel() }
        comprobaciones = [0, 0.7, 1.6].map { d in
            let w = DispatchWorkItem { [weak self] in self?.comprobarCompleta() }
            DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: w)
            return w
        }
    }

    private func comprobarCompleta() {
        completa = h.esconderCompleta && HuecoVentana.appEnPantallaCompleta(pantalla)
    }
    private var esconderAntes = true
    // Si cambia el ajuste, se vuelve a mirar sin esperar a cambiar de app.
    func revisarAjustes() {
        if h.esconderCompleta != esconderAntes { esconderAntes = h.esconderCompleta; programarComprobacion() }
    }

    // Comprobado en macOS 27: en pantalla completa desaparece la ventana «Menubar» del Window Server
    // (capa 24) y una ventana de otra app (capa 0) cubre la pantalla de lado a lado hasta abajo. Hacen falta las dos.
    static func appEnPantallaCompleta(_ s: NSScreen) -> Bool {
        guard let principal = NSScreen.screens.first,
              let lista = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let f = s.frame
        let t = CGRect(x: f.minX, y: principal.frame.maxY - f.maxY, width: f.width, height: f.height)
        let yo = ProcessInfo.processInfo.processIdentifier
        var barra = false, cubierta = false
        for w in lista {
            guard let bd = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  r.intersects(t), (w[kCGWindowOwnerPID as String] as? Int32) != yo else { continue }
            let capa = w[kCGWindowLayer as String] as? Int ?? -1
            if capa == Int(CGWindowLevelForKey(.mainMenuWindow)), w[kCGWindowOwnerName as String] as? String == "Window Server" { barra = true }
            if capa == 0, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
               abs(r.minX - t.minX) < 2, abs(r.width - t.width) < 2, abs(r.maxY - t.maxY) < 2, r.height >= t.height - 60 { cubierta = true }
        }
        return cubierta && !barra
    }
}
