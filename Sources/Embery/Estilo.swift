import SwiftUI
import AppKit

extension Color {
    init(hex: String, _ a: Double = 1) { let c = Col(hex); self.init(.sRGB, red: c.r / 255, green: c.g / 255, blue: c.b / 255, opacity: a) }
    init(_ r: Double, _ g: Double, _ b: Double) { self.init(.sRGB, red: r, green: g, blue: b) }
    static let tarjeta = Color(hex: "#141416"), tarjeta2 = Color(hex: "#1d1d20"), linea = Color.white.opacity(0.07)
    static let texto = Color(hex: "#f5f5f7"), sec = Color(hex: "#8e8e93"), ter = Color(hex: "#808086")
    static let luz = Color(hex: "#d2e4ff"), luzOn = Color(hex: "#a9c6ff")
    static let capsula = Color(hex: "#1f1f22"), hundido = Color(hex: "#0f0f11"), apagado = Color(hex: "#39393d")
    static let velo = Color.white.opacity(0.04), luzTenue = Color.luz.opacity(0.12), tinta = Color(hex: "#0d1424")
    // El único color de aviso de la app: solo cuando Claude pide permiso.
    static let aviso = Color(hex: "#f0c48e")
}

enum Radio {
    static let tarjeta = 22.0, tarjetaHueco = 18.0, caja = 14.0, fila = 10.0, etiqueta = 7.0
}

enum Tipo {
    static func cifra(_ t: Double) -> Font { .system(size: t, weight: .semibold, design: .rounded).monospacedDigit() }
    static let fila = Font.system(size: 13), sub = Font.system(size: 11.5), mono = Font.system(size: 11.5, design: .monospaced)
    static let chip = Font.system(size: 11, weight: .medium), pie = Font.system(size: 11)
}

// Tres curvas y nada más (sistema v5 · Movimiento).
// Interacción: lo que se pulsa se hunde y vuelve con rebote.
let muelle = Animation.spring(response: 0.45, dampingFraction: 0.55)
// Formas que cambian de tamaño o de sitio: Hueco, píldoras, cartel, ancho del Scriptorium.
let muelleForma = Animation.spring(response: 0.55, dampingFraction: 0.9)
func salida(_ d: Double = 0.4) -> Animation { .easeOut(duration: d) }

enum Dura {
    static let resalte = 0.2, cuerpo = 0.25, entra = 0.4, altura = 0.5, intencion = 0.35
    static let destello = 1.6, respira = 4.2, respiraLenta = 7.0, latido = 2.4
}

// Reducir movimiento: nada se desplaza ni late; lo que aparece funde 0,2 s y las medidas cambian en seco.
extension Animation {
    func sinMovimiento(_ reducir: Bool, funde: Bool = true) -> Animation? { reducir ? (funde ? .easeOut(duration: Dura.resalte) : nil) : self }
}

struct Hunde: ButtonStyle {
    var escala = 0.92
    func makeBody(configuration c: Configuration) -> some View {
        c.label.contentShape(Rectangle()).scaleEffect(c.isPressed ? escala : 1)
            .animation(c.isPressed ? .easeOut(duration: 0.1) : muelle, value: c.isPressed)
    }
}

struct Principal: ButtonStyle {
    var alto = 50.0
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: alto > 40 ? 15 : 13, weight: .semibold)).foregroundStyle(Color.tinta)
            .frame(maxWidth: .infinity).frame(height: alto)
            .background(Capsule().fill(LinearGradient(colors: [Color(hex: "#dfe9ff"), Color(hex: "#a9c6ff")], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
            .contentShape(Capsule())
            .scaleEffect(c.isPressed ? 0.96 : 1)
            .animation(c.isPressed ? .easeOut(duration: 0.1) : muelle, value: c.isPressed)
    }
}

struct Secundario: ButtonStyle {
    var alto = 46.0
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: alto > 40 ? 13 : 12.5, weight: .semibold)).foregroundStyle(Color.texto)
            .frame(maxWidth: .infinity).frame(height: alto)
            .background(Capsule().fill(Color.capsula))
            .contentShape(Capsule())
            .scaleEffect(c.isPressed ? 0.96 : 1)
            .animation(c.isPressed ? .easeOut(duration: 0.1) : muelle, value: c.isPressed)
    }
}

// Terminar: hay que mantenerlo pulsado 1 s; se llena mientras tanto. Un clic suelto avisa con «Mantén pulsado».
struct Mantener: View {
    var alto = 46.0
    let accion: () -> Void
    @State private var desde: Date?
    @State private var lleno = 0.0
    @State private var aviso = false
    @State private var plazo: DispatchWorkItem?

    var body: some View {
        Text(aviso ? String(localized: "Mantén pulsado") : String(localized: "Terminar"))
            .font(.system(size: alto > 40 ? 13 : 12.5, weight: .semibold)).foregroundStyle(Color.texto)
            .frame(maxWidth: .infinity).frame(height: alto)
            .background(GeometryReader { g in
                ZStack(alignment: .leading) {
                    Color.capsula
                    Color.luz.opacity(0.22).frame(width: g.size.width * lleno)
                }.clipShape(Capsule())
            })
            .contentShape(Capsule())
            .scaleEffect(desde != nil ? 0.96 : 1)
            .animation(muelle, value: desde != nil)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if desde == nil { pulsar() } }
                .onEnded { _ in soltar() })
            .accessibilityElement().accessibilityLabel(String(localized: "Terminar, mantén pulsado")).accessibilityAddTraits(.isButton)
            .accessibilityAction { accion() }
    }
    private func pulsar() {
        desde = Date(); aviso = false
        withAnimation(.linear(duration: 1)) { lleno = 1 }
        // El final va con temporizador; la animación solo pinta el relleno.
        let p = DispatchWorkItem { desde = nil; lleno = 0; accion() }
        plazo = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: p)
    }
    private func soltar() {
        guard let d = desde else { return }
        plazo?.cancel(); plazo = nil
        if Date().timeIntervalSince(d) < 0.25 {
            aviso = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { aviso = false }
        }
        desde = nil
        withAnimation(.easeOut(duration: 0.2)) { lleno = 0 }
    }
}

struct Tarjeta: ViewModifier {
    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: Radio.tarjeta, style: .continuous).fill(Color.tarjeta))
            .overlay(RoundedRectangle(cornerRadius: Radio.tarjeta, style: .continuous).strokeBorder(Color.linea))
            .clipShape(RoundedRectangle(cornerRadius: Radio.tarjeta, style: .continuous))
    }
}
extension View { func tarjeta() -> some View { modifier(Tarjeta()) } }

// Filas con una línea fina entre cada una, como las tarjetas de ajustes.
struct Filas<C: View>: View {
    @ViewBuilder let contenido: C
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: contenido) { vistas in
                ForEach(Array(vistas.enumerated()), id: \.offset) { i, v in
                    if i > 0 { Rectangle().fill(Color.linea).frame(height: 1) }
                    v
                }
            }
        }.padding(.vertical, 4).tarjeta()
    }
}

struct Fila<D: View>: View {
    let titulo: String
    var sub: String?
    var monoSub = false
    @ViewBuilder var derecha: D
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(titulo).font(.system(size: 13))
                if let sub { Text(sub).font(monoSub ? .system(size: 11.5, design: .monospaced) : .system(size: 11.5)).foregroundStyle(Color.sec) }
            }
            Spacer(minLength: 0)
            derecha
        }.padding(.horizontal, 14).padding(.vertical, 11).frame(minHeight: 44)
    }
}

struct Interruptor: View {
    @Binding var on: Bool
    var body: some View {
        Button { withAnimation(muelle) { on.toggle() } } label: {
            Capsule().fill(on ? Color.luzOn : Color.apagado).frame(width: 38, height: 23)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 19, height: 19).shadow(color: .black.opacity(0.3), radius: 1.5, y: 1).padding(2)
                }
        }.buttonStyle(Hunde(escala: 0.94)).accessibilityAddTraits(.isToggle).accessibilityValue(on ? "Sí" : "No")
    }
}

// Selector de varias opciones: una píldora se desliza hasta la elegida.
struct Segmento<T: Hashable>: View {
    let opciones: [(T, String)]
    @Binding var valor: T
    var mini = false
    var marcas: Set<T> = []   // punto ámbar junto al nombre (un permiso que espera)
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 0) {
            ForEach(opciones, id: \.0) { (v, nombre) in
                Button {
                    withAnimation(muelleForma) { valor = v }
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                } label: {
                    HStack(spacing: 6) {
                        Text(nombre).lineLimit(1).fixedSize()   // en inglés el segmento corto partía las palabras
                        if marcas.contains(v) { Circle().fill(Color.aviso).frame(width: 6, height: 6) }
                    }
                        .font(.system(size: mini ? 12 : 12.5, weight: .medium))
                        .foregroundStyle(valor == v ? Color.texto : Color.sec)
                        .frame(maxWidth: mini ? nil : .infinity).padding(.horizontal, mini ? 10 : 0).padding(.vertical, mini ? 4 : 8)
                        .background {
                            if valor == v { RoundedRectangle(cornerRadius: mini ? 7 : 11, style: .continuous).fill(Color(hex: mini ? "#2a2a2e" : "#26262a")).matchedGeometryEffect(id: "pildora", in: ns) }
                        }
                }.buttonStyle(Hunde())
            }
        }
        .padding(mini ? 2 : 3)
        .background(RoundedRectangle(cornerRadius: mini ? 9 : 14, style: .continuous).fill(Color(hex: "#111113")))
        .overlay { if !mini { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.linea) } }
    }
}

struct Chip: View {
    let texto: String
    let on: Bool
    var body: some View {
        Text(texto).font(.system(size: 12, weight: .medium)).foregroundStyle(on ? Color.luz : Color.sec).fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(on ? Color.luzTenue : Color(hex: "#202024")))
            .overlay(Capsule().strokeBorder(on ? Color.luz.opacity(0.3) : .clear))
    }
}

struct Destello: View {
    var color = Color.luz
    var tam = 13.0
    var body: some View { Image(systemName: "sparkle").font(.system(size: tam, weight: .bold)).foregroundStyle(color) }
}

func svg(_ s: String) -> NSImage { NSImage(data: Data(s.utf8)) ?? NSImage() }

// Lumen dibujado por código en una vista de AppKit, con su propio ritmo de pantalla.
final class LumenNSView: NSView {
    let buho: Buho
    var escena: EscenaHogar?
    var alTocar: () -> Void = {}
    private var link: CADisplayLink?
    private var antes: CFTimeInterval = 0
    private var raton = NSPoint(x: -1, y: -1)

    init(_ buho: Buho) { self.buho = buho; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() {
        link?.invalidate(); link = nil; antes = 0
        // Atado a la pantalla, no a la ventana: el panel nace sin tamaño y un enlace atado a él no llega a latir.
        if window != nil { link = (NSScreen.screens.first ?? NSScreen.main!).displayLink(target: self, selector: #selector(paso)); link?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60); link?.add(to: .main, forMode: .common) }
    }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); buho.redimensionar(s.width, s.height) }
    @objc private func paso(_ l: CADisplayLink) {
        // Con el panel plegado no se anima: no lo ve nadie.
        guard window?.isVisible == true else { antes = 0; return }
        let dt = antes == 0 ? 1.0 / 60 : min(0.05, l.timestamp - antes); antes = l.timestamp
        // Lumen sigue el cursor esté donde esté, como en el prototipo.
        let m = NSEvent.mouseLocation
        if m != raton, let w = window { raton = m; let q = convert(w.convertPoint(fromScreen: m), from: nil); buho.mirar(q.x, q.y) }
        buho.actualizar(dt)
        escena?.paso(dt)
        needsDisplay = true
    }
    override func draw(_ r: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let l = Lienzo(c)
        // El hogar va en su lienzo de 340 × 300, detrás y delante de Lumen.
        guard let e = escena else { buho.dibujar(l); return }
        let sx = bounds.width / HW, sy = bounds.height / HH
        l.save(); l.scale(sx, sy); e.fondo(l); l.restore()
        buho.dibujar(l)
        l.save(); l.scale(sx, sy); e.frente(l); l.restore()
    }
    override func mouseDown(with e: NSEvent) { buho.tocar(); Sonido.tocar(.lumen); alTocar() }
}

struct LumenVista: NSViewRepresentable {
    let buho: Buho
    var escena: EscenaHogar?
    func makeNSView(context: Context) -> LumenNSView { let v = LumenNSView(buho); v.escena = escena; return v }
    func updateNSView(_ v: LumenNSView, context: Context) {}
}
