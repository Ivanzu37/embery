// Embery · pestañas del Hueco: Hoy (Pendientes, Nota rápida, Lo siguiente, Notas recientes), Trabajo y Calma (Respirar, Canto, Paisajes).
import AppKit
import SwiftUI

// Columnas del panel abierto (724 pt útiles): 1,15 a 1, como en la maqueta. Los campos de texto no las descuadran.
let IZQUIERDA = 382.0

enum PestanaHueco: String { case hoy, trabajo, calma
    var nombre: String { switch self { case .hoy: String(localized: "Hoy"); case .trabajo: String(localized: "Trabajo"); case .calma: String(localized: "Calma") } }
}

extension Embery {
    func pestanas(claude: Bool) -> [PestanaHueco] {
        var p: [PestanaHueco] = []
        if activo(.captura) || activo(.tres) || activo(.siguiente) || activo(.notas) { p.append(.hoy) }
        // Trabajo existe con Claude Code (Conversaciones, Nido) o con los proyectos de VS Code.
        if claude || (activo(.vscode) && !editores.isEmpty) { p.append(.trabajo) }
        if activo(.respirar) || activo(.paisajes) || activo(.canto) { p.append(.calma) }
        return p
    }

    var destinoNota: String {
        switch ajustes.capturaDestino ?? "boveda" {
        case "notas": String(localized: "a Notas")
        case "carpeta": ajustes.capturaCarpeta.map { String(localized: "a \(URL(fileURLWithPath: $0).lastPathComponent)") } ?? String(localized: "elige carpeta en Ajustes")
        default: ajustes.boveda.isEmpty ? String(localized: "elige bóveda en Ajustes") : "\(URL(fileURLWithPath: ajustes.boveda).lastPathComponent) › \(ajustes.entrada)"
        }
    }
    var destinoListo: Bool {
        switch ajustes.capturaDestino ?? "boveda" {
        case "notas": true
        case "carpeta": ajustes.capturaCarpeta != nil
        default: !ajustes.boveda.isEmpty
        }
    }
}

struct PestanasHueco: View {
    let h: Hueco
    @Bindable var m: Embery
    @FocusState private var campo: String?

    var body: some View {
        let lista = m.pestanas(claude: h.claude)
        // La última que dejaste abierta es la que vuelve.
        let actual = lista.first { $0.rawValue == m.ajustes.pestanaHueco } ?? lista.first
        VStack(spacing: 10) {
            if lista.count > 1, let a = actual {
                Segmento(opciones: lista.map { ($0, $0.nombre) }, valor: Binding(get: { a }, set: { m.ajustes.pestanaHueco = $0.rawValue }), mini: true,
                         marcas: h.feed.permId.isEmpty ? [] : [.trabajo])
                    .fixedSize()
            }
            switch actual {
            case .hoy?: Hoy(h: h, m: m, campo: $campo)
            case .calma?: Calma(m: m)
            case .trabajo?: PanelHueco(h: h, m: m)
            case nil:
                Text(String(localized: "Enciende módulos en Ajustes → Módulos")).font(.system(size: 12)).foregroundStyle(Color.sec).padding(.vertical, 20)
            }
        }
        .foregroundStyle(Color.texto)
        .onChange(of: campo) { _, c in h.escribiendo = c != nil }
        .onExitCommand { campo = nil; h.abierto = false }
    }
}

// MARK: Hoy

private struct Hoy: View {
    let h: Hueco
    @Bindable var m: Embery
    var campo: FocusState<String?>.Binding
    var body: some View {
        let izq = m.activo(.tres) || m.activo(.captura), der = m.activo(.siguiente) || m.activo(.notas)
        HStack(alignment: .top, spacing: 10) {
            if izq {
                VStack(spacing: 10) {
                    if m.activo(.tres) { PendientesTarjeta(h: h, m: m, campo: campo) }
                    if m.activo(.captura) { CapturaTarjeta(m: m, campo: campo) }
                }.frame(width: der ? IZQUIERDA : nil).frame(maxWidth: .infinity)
            }
            if der {
                VStack(spacing: 10) {
                    if m.activo(.siguiente) { SiguienteTarjeta(s: m.siguiente) }
                    if m.activo(.notas) { NotasTarjeta(m: m) }
                }.frame(maxWidth: .infinity)
            }
        }
    }
}

private struct CapturaTarjeta: View {
    @Bindable var m: Embery
    var campo: FocusState<String?>.Binding
    @State private var texto = ""
    @State private var guardado = false

    var body: some View {
        let espera = m.datos.capturas?.count ?? 0
        VStack(alignment: .leading, spacing: 8) {
            titulo(String(localized: "Nota rápida"), m.destinoNota)
            TextField(String(localized: "Apunta lo que sea…"), text: $texto, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...4)
                .focused(campo, equals: "captura").onSubmit(guardar)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.capsula))
            HStack {
                Text(guardado ? String(localized: "Guardada") : m.destinoListo ? String(localized: "↩ guarda · también con \((m.ajustes.atajoNota ?? .deSerie).texto) desde cualquier app") : String(localized: "se guardará al elegir la bóveda"))
                    .foregroundStyle(guardado ? Color.luz : Color.sec)
                Spacer()
                if espera > 0 { Text(espera == 1 ? String(localized: "1 en espera") : String(localized: "\(espera) en espera")).foregroundStyle(Color.sec) }
            }.font(.system(size: 11)).lineLimit(1).animation(.easeOut(duration: 0.2), value: guardado)
        }.cajaHueco()
    }
    private func guardar() {
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        m.capturar(texto); texto = ""; guardado = true
        Sonido.tocar(.gota)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { guardado = false }
    }
}

// Pendientes de hoy: las casillas de la nota diaria; sin bóveda (o sin nota de hoy), una lista en la app.
private struct PendientesTarjeta: View {
    let h: Hueco
    @Bindable var m: Embery
    var campo: FocusState<String?>.Binding
    @State private var lectura = Pendientes.Lectura.app
    @State private var nueva = ""

    var body: some View {
        let items = lectura.casillas.map { $0.map { Pendientes.Item(texto: $0.texto, hecha: $0.hecha, casilla: $0) } }
            ?? m.tresHoy.items.enumerated().filter { !$0.element.texto.isEmpty }.map { Pendientes.Item(texto: $0.element.texto, hecha: $0.element.hecha, indice: $0.offset) }
        let enNota = lectura.casillas != nil
        VStack(alignment: .leading, spacing: 0) {
            titulo(String(localized: "Pendientes de hoy"), items.isEmpty ? (enNota ? String(localized: "nota diaria") : String(localized: "en la app"))
                   : String(localized: "\(items.filter(\.hecha).count) de \(items.count) · \(enNota ? String(localized: "nota diaria") : String(localized: "en la app"))")).padding(.bottom, 4)
            if case .fuera(let disco) = lectura {
                Vacio(t: String(localized: "No llego a la nota de hoy"), sub: String(localized: "\(disco) no está montado"))
            } else if items.isEmpty {
                Vacio(t: String(localized: "Nada pendiente hoy"), sub: enNota || !m.ajustes.boveda.isEmpty ? "" : String(localized: "Con una bóveda elegida salen las casillas de tu nota diaria"))
            }
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                if i > 0 { Rectangle().fill(Color.linea).frame(height: 1) }
                FilaPendiente(it: it, foco: m.foco, empezar: { m.ajustes.tarea = it.texto; m.empezar() }, ver: { h.verFoco() }) { marcar(it) }
            }
            TextField(enNota ? String(localized: "Añadir a la nota de hoy…") : String(localized: "Añadir una pendiente…"), text: $nueva)
                .textFieldStyle(.plain).font(.system(size: 12.5)).focused(campo, equals: "pendiente").onSubmit(anadir)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.capsula))
                .padding(.top, 6)
        }
        .cajaHueco()
        .task(id: m.ajustes.boveda + m.ajustes.patronDiaria) {
            while !Task.isCancelled { await leer(); try? await Task.sleep(for: .seconds(30)) }
        }
    }

    private func leer() async {
        let a = m.ajustes
        let l = await Task.detached(priority: .userInitiated) { Pendientes.leer(a) }.value
        if l != lectura { lectura = l }
    }

    private func marcar(_ it: Pendientes.Item) {
        if let c = it.casilla {
            // Al momento en pantalla; el archivo se escribe aparte y se vuelve a leer.
            if case .nota(var cs) = lectura, let i = cs.firstIndex(of: c) { cs[i].hecha.toggle(); withAnimation(muelle) { lectura = .nota(cs) } }
            let a = m.ajustes
            Task { _ = await Task.detached { Boveda.marcar(c, !c.hecha, a) }.value; await leer() }
        } else if let i = it.indice {
            withAnimation(muelle) { m.cambiarTres(i) { $0.hecha.toggle() } }
        }
    }

    private func anadir() {
        let t = nueva.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        nueva = ""
        if lectura.casillas != nil {
            let a = m.ajustes
            Task { _ = await Task.detached { Boveda.anadir(t, a) }.value; await leer() }
        } else {
            m.anadirPendiente(t)
        }
    }
}

enum Pendientes {
    struct Item { var texto: String; var hecha: Bool; var casilla: Boveda.Casilla? = nil; var indice: Int? = nil }
    enum Lectura: Equatable {
        case app, nota([Boveda.Casilla]), fuera(String)
        var casillas: [Boveda.Casilla]? { if case .nota(let c) = self { c } else { nil } }
    }
    // Sin nota diaria de hoy, la lista de la app: añadir a un archivo que no existe lo crearía sin su plantilla.
    static func leer(_ a: Ajustes) -> Lectura {
        guard a.registrar else { return .app }
        guard Boveda.disponible(a.boveda) else {
            return .fuera(Vault.volumen(de: a.boveda).map { ($0 as NSString).lastPathComponent } ?? String(localized: "La bóveda"))
        }
        return Boveda.leerCasillas(a).map { .nota($0) } ?? .app
    }
}

private struct FilaPendiente: View {
    let it: Pendientes.Item
    let foco: Foco?
    let empezar: () -> Void
    let ver: () -> Void
    let marcar: () -> Void
    @State private var encima = false

    var body: some View {
        let atada = foco?.tarea == it.texto && !it.texto.isEmpty
        HStack(spacing: 10) {
            Button(action: marcar) {
                if atada, let f = foco {
                    Anillo(avance: f.duracion > 0 ? f.segundosRonda / f.duracion : 0)
                } else {
                    Circle().strokeBorder(it.hecha ? Color.luzOn : Color.sec, lineWidth: 1.4)
                        .overlay(Circle().fill(Color.luzOn).frame(width: 8, height: 8).scaleEffect(it.hecha ? 1 : 0.01))
                        .frame(width: 18, height: 18)
                }
            }
            .buttonStyle(Hunde())
            .accessibilityLabel(it.hecha ? String(localized: "Hecha") : String(localized: "Sin hacer")).accessibilityValue(it.texto)
            VStack(alignment: .leading, spacing: 1) {
                Text(it.texto).font(.system(size: 13)).lineLimit(1)
                    .strikethrough(it.hecha, color: Color.sec).foregroundStyle(it.hecha ? Color.sec : Color.texto)
                if atada, let f = foco { Text("En foco · \(Int(f.segundos / 60)) min").font(.system(size: 11)).foregroundStyle(Color.sec) }
            }
            Spacer(minLength: 0)
            if atada {
                Accion(texto: String(localized: "Ver foco"), fija: true, accion: ver)
            } else if !it.hecha, foco == nil {
                Accion(texto: String(localized: "Foco"), accion: empezar).opacity(encima ? 1 : 0)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(encima ? 0.03 : 0)))
        .padding(.horizontal, -6)
        .onHover { encima = $0 }
        .animation(.easeOut(duration: Dura.resalte), value: encima)
    }
}

// El avance del foco atado a una pendiente, en lugar de su casilla.
private struct Anillo: View {
    let avance: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 3.5)
            Circle().trim(from: 0, to: clamp(avance, 0, 1)).stroke(Color.luz, style: StrokeStyle(lineWidth: 3.5)).rotationEffect(.degrees(-90))
        }
        .padding(1.75).frame(width: 18, height: 18)
        .animation(.easeOut(duration: 0.6), value: avance)
        .accessibilityLabel(String(localized: "En foco"))
    }
}

// Cápsula de acción de una fila: aparece al pasar el ratón (o fija, en la fila atada al foco).
struct Accion: View {
    let texto: String
    var fija = false
    let accion: () -> Void
    var body: some View {
        Button(action: accion) {
            Text(texto).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.luz)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(fija ? Color.luz.opacity(0.1) : Color.capsula))
        }.buttonStyle(Hunde())
    }
}

// Fila del Hueco con icono, título, sub, cápsula y «›» al pasar el ratón. ⌥ clic hace la acción alternativa.
struct FilaHueco: View {
    let icono: String
    let titulo: String
    let sub: String
    var accion: (String, () -> Void)?
    let abrir: (_ opcion: Bool) -> Void
    @State private var encima = false

    var body: some View {
        HStack(spacing: 10) {
            Button { abrir(NSEvent.modifierFlags.contains(.option)) } label: {
                HStack(spacing: 10) {
                    Image(systemName: icono).font(.system(size: 13)).foregroundStyle(Color.sec).frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(titulo).font(.system(size: 13)).lineLimit(1)
                        Text(sub).font(.system(size: 11)).foregroundStyle(Color.sec).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(Hunde(escala: 0.98))
            if let a = accion { Accion(texto: a.0, accion: a.1).opacity(encima ? 1 : 0) }
            Text("›").font(.system(size: 13)).foregroundStyle(Color.ter).opacity(encima ? 1 : 0)
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(encima ? 0.03 : 0)))
        .padding(.horizontal, -6)
        .onHover { encima = $0 }
        .animation(.easeOut(duration: Dura.resalte), value: encima)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titulo), \(sub)")
    }
}

// Lo leído del disco vale 30 s: abrir y cerrar el panel no vuelve a recorrer la bóveda.
// Se lee desde Task.detached: sin el cerrojo, dos lecturas a la vez corrompían `valor` y Embery caía.
final class Cache<T>: @unchecked Sendable {
    private var valor: (clave: String, fecha: Date, v: T)?
    private let cerrojo = NSLock()
    func leer(_ clave: String, _ hacer: () -> T) -> T {
        cerrojo.withLock {
            if let c = valor, c.clave == clave, Date().timeIntervalSince(c.fecha) < 30 { return c.v }
            let v = hacer(); valor = (clave, Date(), v); return v
        }
    }
}

private let cacheNotas = Cache<[Boveda.Reciente]>()
private let cacheProyectos = Cache<[(EditorRecientes.Proyecto, String?)]>()

// «ahora», «hace 12 min», «hace 3 h», «ayer» o la fecha corta.
func relativo(_ d: Date, _ ahora: Date = Date()) -> String {
    let s = ahora.timeIntervalSince(d), cal = Calendar.current
    if s < 60 { return "ahora" }
    if s < 3600 { return String(localized: "hace \(Int(s / 60)) min") }
    if cal.isDate(d, inSameDayAs: ahora) { return String(localized: "hace \(Int(s / 3600)) h") }
    if let ayer = cal.date(byAdding: .day, value: -1, to: ahora), cal.isDate(d, inSameDayAs: ayer) { return "ayer" }
    return d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_ES")))
}

private struct NotasTarjeta: View {
    @Bindable var m: Embery
    @State private var notas: [Boveda.Reciente]?

    var body: some View {
        let raiz = m.ajustes.boveda
        VStack(alignment: .leading, spacing: 0) {
            titulo(String(localized: "Notas recientes"), raiz.isEmpty ? "" : URL(fileURLWithPath: raiz).lastPathComponent).padding(.bottom, 4)
            if raiz.isEmpty {
                Vacio(t: String(localized: "Elige tu bóveda en Ajustes"), sub: String(localized: "Aquí saldrán las últimas notas que toques"))
            } else if !Boveda.disponible(raiz) {
                Vacio(t: String(localized: "Sin raíces"), sub: Vault.volumen(de: raiz).map { ($0 as NSString).lastPathComponent } ?? URL(fileURLWithPath: raiz).lastPathComponent)
            } else if let notas {
                if notas.isEmpty { Vacio(t: String(localized: "Aún no hay notas")) }
                ForEach(Array(notas.enumerated()), id: \.element.url) { i, n in
                    if i > 0 { Rectangle().fill(Color.linea).frame(height: 1) }
                    FilaHueco(icono: "doc.text", titulo: n.url.deletingPathExtension().lastPathComponent,
                              sub: [n.carpeta, relativo(n.fecha)].filter { !$0.isEmpty }.joined(separator: " · ")) { opcion in
                        if opcion { NSWorkspace.shared.activateFileViewerSelecting([n.url]) } else { Boveda.abrir(n.url) }
                    }
                }
            }
        }
        .cajaHueco()
        .task(id: raiz) {
            notas = await Task.detached(priority: .userInitiated) { cacheNotas.leer(raiz) { Boveda.recientes(raiz) } }.value
        }
    }
}

// Proyectos recientes de VS Code (y Cursor si se pide), sin Accesibilidad: workspaceStorage por fecha.
struct ProyectosTarjeta: View {
    let h: Hueco
    @Bindable var m: Embery
    @State private var lista: [(EditorRecientes.Proyecto, String?)]?

    var body: some View {
        let eds = m.editores, editor = eds.first ?? .vscode, claude = m.ajustes.claudeCode ?? true
        VStack(alignment: .leading, spacing: 0) {
            titulo(String(localized: "Proyectos recientes"), eds.map(\.nombre).joined(separator: " · ")).padding(.bottom, 4)
            if let lista {
                if lista.isEmpty { Vacio(t: String(localized: "\(editor.nombre) no tiene proyectos recientes"), sub: String(localized: "Abre una carpeta en \(editor.nombre) y saldrá aquí")) }
                ForEach(Array(lista.enumerated()), id: \.element.0.carpeta) { i, par in
                    let p = par.0
                    if i > 0 { Rectangle().fill(Color.linea).frame(height: 1) }
                    FilaHueco(icono: "chevron.left.forwardslash.chevron.right", titulo: p.nombre,
                              sub: [abreviar(p.carpeta.path), par.1 ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                              accion: claude ? ("Claude Code", { nueva(p.carpeta) }) : nil) { opcion in
                        if opcion && claude { nueva(p.carpeta) } else { EditorRecientes.abrir(p.carpeta, con: editor) }
                    }
                }
            }
        }
        .cajaHueco()
        .task(id: eds.map(\.rawValue).joined()) {
            lista = await Task.detached(priority: .userInitiated) {
                cacheProyectos.leer(eds.map(\.rawValue).joined()) { EditorRecientes.recientes(eds).map { ($0, GitEstado.rama($0.carpeta)) } }
            }.value
        }
    }
    private func nueva(_ u: URL) { Focus.nuevaSesion(en: u, terminal: m.ajustes.terminalClaude); Sonido.tocar(.nido) }
    private func abreviar(_ p: String) -> String {
        let casa = NSHomeDirectory()
        return p.hasPrefix(casa) ? "~" + p.dropFirst(casa.count) : p
    }
}

private struct SiguienteTarjeta: View {
    let s: Siguiente
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titulo(String(localized: "Lo siguiente"), String(localized: "Calendario"))
            switch s.permiso {
            case .fullAccess:
                if let e = s.evento {
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(e.color.map { Color(cgColor: $0) } ?? Color.luz).frame(width: 7, height: 7).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.titulo).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            Text(Siguiente.cuando(e)).font(.system(size: 11.5)).foregroundStyle(Color.sec)
                        }
                    }
                } else {
                    Text(String(localized: "Nada en las próximas 36 h")).font(.system(size: 12)).foregroundStyle(Color.sec)
                }
            case .notDetermined:
                Text(String(localized: "Tu próximo evento, en una línea.")).font(.system(size: 12)).foregroundStyle(Color.sec)
                Button(String(localized: "Permitir el Calendario")) { s.pedirPermiso() }.buttonStyle(Secundario(alto: 30))
            default:
                Text("Sin acceso al Calendario. Se activa en Ajustes del Sistema → Privacidad → Calendarios.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.sec).fixedSize(horizontal: false, vertical: true)
            }
        }
        .cajaHueco()
        .onAppear { s.refrescar() }
    }
}

// MARK: Calma

private struct Calma: View {
    @Bindable var m: Embery
    var body: some View {
        let derecha = m.activo(.canto) || m.activo(.paisajes)
        HStack(alignment: .top, spacing: 10) {
            if m.activo(.respirar) { RespirarTarjeta(m: m).frame(width: derecha ? IZQUIERDA : nil).frame(maxWidth: .infinity) }
            if derecha {
                VStack(spacing: 10) {
                    if m.activo(.canto) { CantoTarjeta(c: m.canto) }
                    if m.activo(.paisajes) { PaisajesTarjeta(m: m) }
                }.frame(maxWidth: .infinity)
            }
        }
    }
}

private struct RespirarTarjeta: View {
    @Bindable var m: Embery
    var body: some View {
        let clave = m.ajustes.respiracion ?? "caja", p = PATRONES.first { $0.clave == clave } ?? PATRONES[0]
        VStack(alignment: .leading, spacing: 10) {
            titulo(String(localized: "Respirar"), String(localized: "\(Int(p.duracion / 60)) min \(Int(p.duracion) % 60) s"))
            if let r = m.respiracion {
                LuzRespira(r: r).frame(maxWidth: .infinity).padding(.bottom, 18)
                Button("Parar") { m.respiracion = nil }.buttonStyle(Secundario(alto: 32))
            } else {
                Segmento(opciones: PATRONES.map { ($0.clave, $0.nombre) }, valor: Binding(get: { clave }, set: { m.ajustes.respiracion = $0 }), mini: true)
                Text(explicacion(clave)).font(.system(size: 11.5)).foregroundStyle(Color.sec).fixedSize(horizontal: false, vertical: true)
                Button("Empezar") { m.respiracion = Respiracion(clave: clave, inicio: ProcessInfo.processInfo.systemUptime) }
                    .buttonStyle(Principal(alto: 34))
            }
        }.cajaHueco()
    }
    private func explicacion(_ c: String) -> String {
        switch c {
        case "478": String(localized: "Inhala 4, sostén 7, exhala 8. Para soltar tensión.")
        case "suspiro": String(localized: "Dos inhalaciones y una exhalación larga. La forma más rápida de bajar pulsaciones.")
        default: String(localized: "Inhala, sostén, exhala y sostén, 4 s cada uno. Para centrarte.")
        }
    }
}

private struct CantoTarjeta: View {
    let c: Canto
    var body: some View {
        let p = c.pista
        VStack(alignment: .leading, spacing: 0) {
            titulo(String(localized: "Canto"), p?.app.nombre ?? "").padding(.bottom, 8)
            HStack(spacing: 10) {
                Group {
                    if p == nil { Color.capsula }
                    else if let img = c.caratula { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) }
                    else { LinearGradient(colors: [Color(hex: "#3b4a6b"), Color(hex: "#1d2233"), Color(hex: "#4a3a52")], startPoint: .topLeading, endPoint: .bottomTrailing) }
                }
                .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(p?.titulo ?? String(localized: "Nada suena")).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(p?.artista ?? String(localized: "Abre Música o Spotify")).font(.system(size: 11)).foregroundStyle(Color.sec).lineLimit(1)
                }
            }
            EspectroVista(e: c.espectro).frame(height: 40).padding(.top, 12).padding(.bottom, 8)
            HStack(spacing: 8) {
                Text(Canto.tiempo(p?.posicion ?? 0))
                GeometryReader { g in
                    Capsule().fill(Color.white.opacity(0.08))
                        .overlay(alignment: .leading) { Capsule().fill(Color.texto.opacity(0.7)).frame(width: g.size.width * avance(p)) }
                }.frame(height: 3)
                Text(Canto.tiempo(p?.duracion ?? 0))
            }.font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.sec)
            HStack(spacing: 18) {
                boton("backward.fill", String(localized: "Anterior"), 30) { c.control("previous track") }
                boton(p?.sonando == true ? "pause.fill" : "play.fill", p?.sonando == true ? String(localized: "Pausa") : String(localized: "Reproducir"), 36) { c.control("playpause") }
                boton("forward.fill", String(localized: "Siguiente"), 30) { c.control("next track") }
            }.frame(maxWidth: .infinity).padding(.top, 8)
            .disabled(p == nil).opacity(p == nil ? 0.35 : 1)
        }
        .cajaHueco()
        .onAppear { c.mirar(true) }
        .onDisappear { c.mirar(false) }
    }
    private func avance(_ p: Canto.Pista?) -> Double { guard let p, p.duracion > 0 else { return 0 }; return p.posicion / p.duracion }
    private func boton(_ icono: String, _ nombre: String, _ tam: Double, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: icono).font(.system(size: 13)).frame(width: tam, height: tam)
                .background(Circle().fill(tam > 30 ? Color(hex: "#1f1f22") : .clear))
        }.buttonStyle(Hunde()).accessibilityLabel(nombre)
    }
}

// Barras de luz a 30 fps en capas propias: redibujarlas con SwiftUI rehace el panel entero en cada fotograma.
// Quietas, y sin reloj, cuando no suena nada.
private struct EspectroVista: NSViewRepresentable {
    let e: Espectro
    func makeNSView(context: Context) -> EspectroNSView { EspectroNSView(e) }
    func updateNSView(_ v: EspectroNSView, context: Context) { v.encender(e.vivo) }
}

final class EspectroNSView: NSView {
    private let e: Espectro
    private let barras: [CAGradientLayer]
    private var link: CADisplayLink?

    init(_ e: Espectro) {
        self.e = e
        barras = (0..<Espectro.bandas).map { _ in
            let b = CAGradientLayer()
            b.colors = [NSColor.white.cgColor, NSColor(Color.luzOn).cgColor]
            b.startPoint = CGPoint(x: 0.5, y: 1); b.endPoint = CGPoint(x: 0.5, y: 0)
            b.cornerRadius = 2; b.opacity = 0.85
            return b
        }
        super.init(frame: .zero)
        wantsLayer = true
        barras.forEach { layer?.addSublayer($0) }
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    func encender(_ si: Bool) {
        guard si != (link != nil) else { return }
        link?.invalidate(); link = nil
        if si, window != nil {
            link = displayLink(target: self, selector: #selector(paso))
            link?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
            link?.add(to: .main, forMode: .common)
        }
        colocar(e.actual)
    }
    override func viewDidMoveToWindow() { link?.invalidate(); link = nil; if window != nil { encender(e.vivo) } }
    override func layout() { super.layout(); colocar(e.actual) }

    @objc private func paso(_ l: CADisplayLink) { colocar(e.paso(l.timestamp)) }

    private func colocar(_ b: [Float]) {
        let hueco = 3.0, ancho = (bounds.width - hueco * Double(b.count - 1)) / Double(b.count)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, v) in b.enumerated() {
            // Bajas: como mucho tres cuartos del alto, y nunca menos de 2 pt.
            barras[i].frame = CGRect(x: Double(i) * (ancho + hueco), y: 0, width: ancho, height: max(2, Double(v) * bounds.height * 0.75))
        }
        CATransaction.commit()
    }
}

private struct PaisajesTarjeta: View {
    @Bindable var m: Embery
    var body: some View {
        let sonando = m.paisajeSonando
        VStack(alignment: .leading, spacing: 10) {
            titulo(String(localized: "Paisajes"), sonando.flatMap { s in Paisajes.todos.first { $0.0 == s }?.1 } ?? String(localized: "En silencio"))
            FlowLayout(spacing: 6) {
                ForEach(Paisajes.todos, id: \.0) { p in
                    Button { m.alternarPaisaje(p.0) } label: { Chip(texto: p.1, on: sonando == p.0) }
                        .buttonStyle(Hunde()).accessibilityAddTraits(sonando == p.0 ? .isSelected : [])
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(Color.sec)
                Slider(value: Binding(get: { m.ajustes.paisajeVolumen ?? 0.5 }, set: { m.ajustes.paisajeVolumen = $0; m.paisajes.volumen($0) }), in: 0.05...1)
                    .tint(Color.luzOn)
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 10)).foregroundStyle(Color.sec)
            }
            HStack {
                Text("Con el foco").font(.system(size: 12))
                Spacer()
                Interruptor(on: Binding(get: { m.ajustes.paisajeConFoco ?? true }, set: { m.ajustes.paisajeConFoco = $0 }))
            }
            Text("Sube despacio al empezar un foco y se apaga solo al terminar.").font(.system(size: 11)).foregroundStyle(Color.sec)
                .fixedSize(horizontal: false, vertical: true)
        }.cajaHueco()
    }
}

// Las tres respiraciones antes de un foco, en el sitio del botón «Concentrarse».
struct PreviaVista: View {
    @Bindable var m: Embery
    let r: Respiracion
    var alto = 50.0
    var body: some View {
        HStack(spacing: 10) {
            LuzRespira(r: r, tam: alto, conTexto: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("Respira con la luz").font(.system(size: 13, weight: .semibold))
                Text("Tres veces y empezamos").font(.system(size: 11.5)).foregroundStyle(Color.sec)
            }
            Spacer(minLength: 0)
            Button("Saltar") { m.saltarPrevia() }.buttonStyle(.plain).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.luz)
        }.frame(minHeight: alto)
    }
}
