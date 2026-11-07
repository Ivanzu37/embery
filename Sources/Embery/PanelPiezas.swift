import SwiftUI
import AppKit

// Piezas del panel v5: cierre de foco, Jornada de Claude, Por proyecto e Integraciones.

func entra(_ reducir: Bool) -> AnyTransition { reducir ? .opacity : .opacity.combined(with: .offset(y: 8)) }

// «6 h 50», «40 min».
func horasMin(_ minutos: Double) -> String {
    let m = Int(minutos.rounded())
    return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) min"
}

let degradadoLuz = LinearGradient(colors: [Color(hex: "#9fc0ff"), .white], startPoint: .leading, endPoint: .trailing)

struct Barra: View {
    let valor: Double
    var alto = 4.0
    var relleno: AnyShapeStyle = AnyShapeStyle(degradadoLuz)
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.linea)
                Capsule().fill(relleno).frame(width: g.size.width * min(1, max(0, valor)))
            }
        }.frame(height: alto)
    }
}

struct Etiqueta: View {
    let texto: String
    var mayusculas = false
    var body: some View {
        Text(mayusculas ? texto.uppercased() : texto)
            .font(.system(size: mayusculas ? 10.5 : 11, weight: mayusculas ? .semibold : .medium)).tracking(mayusculas ? 0.2 : 0)
            .foregroundStyle(Color.sec).lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, mayusculas ? 2 : 1)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: "#202024")))
    }
}

// Punto de estado: luz con halo si está bien, gris si no.
struct PuntoEstado: View {
    let bien: Bool
    var body: some View {
        Circle().fill(bien ? Color.luz : Color(hex: "#3a3a3e")).frame(width: 7, height: 7)
            .shadow(color: bien ? Color.luz.opacity(0.8) : .clear, radius: 4)
    }
}

// Fila suelta de aviso, debajo de una tarjeta.
struct Aviso<D: View>: View {
    let texto: String
    @ViewBuilder var derecha: D
    var body: some View {
        HStack(spacing: 8) {
            PuntoEstado(bien: false)
            Text(texto).font(.system(size: 12)).foregroundStyle(Color.sec).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            derecha
        }.padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: Radio.caja, style: .continuous).fill(Color.velo))
    }
}
extension Aviso where D == EmptyView { init(texto: String) { self.init(texto: texto) { EmptyView() } } }

// MARK: Cierre de foco

struct CierreVista: View {
    @Bindable var m: Embery
    let s: Sesion
    @State private var linea = ""
    @State private var verCommit = false
    @FocusState private var enfocado: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(localized: "¿Qué has hecho?")).font(.system(size: 17, weight: .semibold, design: .rounded)).fixedSize()
                Spacer(minLength: 0)
                Text("\(duracion(Double(s.minutos))) · \(s.proyecto ?? s.tarea)").font(.system(size: 12)).foregroundStyle(Color.sec).lineLimit(1)
            }
            HStack(spacing: 8) {
                TextField("", text: $linea, prompt: Text(String(localized: "Una línea para el registro")).foregroundColor(.ter))
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($enfocado).onSubmit(guardar)
                    .onChange(of: linea) { if linea.count > 120 { linea = String(linea.prefix(120)) } }
                Text("opcional").font(Tipo.pie).foregroundStyle(Color.ter)
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: Radio.caja, style: .continuous).fill(Color.hundido))
            .overlay(RoundedRectangle(cornerRadius: Radio.caja, style: .continuous).strokeBorder(enfocado ? Color.luz.opacity(0.35) : Color.linea))

            if verCommit, let c = m.sinCommit { commit(c.archivos, c.carpeta).transition(entra(m.reducir)) }

            HStack(spacing: 4) {
                Button("Guardar", action: guardar).buttonStyle(Principal(alto: 44))
                Button { m.cerrar(nota: nil) } label: {
                    Text("Omitir").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.sec).padding(.horizontal, 10).frame(height: 44)
                }.buttonStyle(Hunde()).keyboardShortcut(.cancelAction)
            }
            Text(pie).font(Tipo.sub).foregroundStyle(Color.sec)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16)).tarjeta()
        .animation(salida().sinMovimiento(m.reducir), value: verCommit && m.sinCommit != nil)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { enfocado = true }
            // Primero se lee la pregunta; el aviso entra un poco después.
            DispatchQueue.main.asyncAfter(deadline: .now() + Dura.entra + Dura.cuerpo) { verCommit = true }
        }
    }

    private func guardar() { m.cerrar(nota: linea) }

    private var pie: String {
        let a = m.ajustes
        guard a.registrar else { return String(localized: "Se guarda con la sesión") }
        guard Boveda.disponible(a.boveda) else { return String(localized: "La bóveda no está: se guardará cuando vuelva") }
        return String(localized: "Se guarda con la sesión en \(URL(fileURLWithPath: a.boveda).lastPathComponent)")
    }

    private func commit(_ n: Int, _ carpeta: URL) -> some View {
        let editor = m.editores.first ?? .vscode
        return HStack(spacing: 10) {
            Circle().fill(Color.luz).frame(width: 7, height: 7).shadow(color: Color.luz.opacity(0.8), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(carpeta.lastPathComponent).font(.system(size: 12, weight: .semibold))
                Text(n == 1 ? "1 archivo sin commit" : "\(n) archivos sin commit").font(.system(size: 12)).foregroundStyle(Color.sec)
            }
            Spacer(minLength: 0)
            Button { EditorRecientes.abrir(carpeta, con: editor) } label: {
                Text("\(editor.nombre) ›").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.luz)
            }.buttonStyle(Hunde())
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Radio.caja, style: .continuous).fill(Color.velo))
    }
}

// MARK: Jornada de Claude

struct JornadaTarjeta: View {
    @Bindable var m: Embery
    let hueco: Hueco?
    let activar: () -> Void
    @State private var semana = false
    @State private var cuentas: [Bool: Jornada] = [:]

    static var detectado: Bool { FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.claude/projects") }

    var body: some View {
        let apagado = !(m.ajustes.claudeCode ?? true)
        let j = cuentas[semana] ?? Jornada(), alguna = (cuentas[true]?.conversaciones ?? 0) > 0
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Jornada de Claude").font(.system(size: 13.5, weight: .semibold))
                Spacer()
                if !apagado && alguna { Segmento(opciones: [(false, String(localized: "Hoy")), (true, String(localized: "Semana"))], valor: $semana, mini: true) }
            }
            if apagado {
                vacio(String(localized: "Claude Code está apagado.")) {
                    Button(action: activar) { Text("Activarlo en Ajustes › Integraciones").foregroundStyle(Color.luz) }.buttonStyle(.plain)
                }
            } else if j.conversaciones == 0 {
                vacio(semana ? String(localized: "Sin conversaciones esta semana.") : String(localized: "Sin conversaciones hoy.")) { Text(String(localized: "Abre Claude Code y aquí verás su jornada.")) }
            } else {
                HStack(spacing: 8) {
                    cifra(String(localized: "Conversaciones"), "\(j.conversaciones)")
                    cifra(String(localized: "Horas"), horasMin(j.segundos / 60))
                    cifra(String(localized: "Tokens"), TokenLedger.short(j.tokens))
                }
                let total = max(1, j.herramientas.reduce(0) { $0 + $1.veces })
                VStack(spacing: 8) {
                    ForEach(j.herramientas.prefix(4), id: \.nombre) { h in
                        let parte = Double(h.veces) / Double(total)
                        HStack(spacing: 8) {
                            // Las de un MCP llevan delante «mcp__servidor__»: basta con el nombre.
                            Text(h.nombre.components(separatedBy: "__").last ?? h.nombre)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced)).lineLimit(1).frame(width: 52, alignment: .leading)
                            Barra(valor: parte, alto: 5)
                            Text("\(Int((parte * 100).rounded())) %").font(.system(size: 12)).foregroundStyle(Color.sec).monospacedDigit().frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16)).tarjeta()
        .animation(.easeOut(duration: 0.6), value: semana)
        .task(id: apagado) {
            guard !apagado else { return }
            while !Task.isCancelled {
                let dias = hueco?.dias ?? [:], c = m.cuentas, hoy = c.cal.startOfDay(for: Date()), lunes = c.semana[0]
                let r = await Task.detached(priority: .utility) {
                    [Jornada.calcular(desde: hoy, tokensPorDia: dias), Jornada.calcular(desde: lunes, tokensPorDia: dias)]
                }.value
                withAnimation(.easeOut(duration: 0.6)) { cuentas = [false: r[0], true: r[1]] }
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    private func cifra(_ rotulo: String, _ valor: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rotulo).font(.system(size: 11)).foregroundStyle(Color.sec).lineLimit(1).minimumScaleFactor(0.85)
            Text(valor).font(Tipo.cifra(19)).contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Radio.caja, style: .continuous).fill(Color.velo))
    }

    private func vacio<V: View>(_ titulo: String, @ViewBuilder _ abajo: () -> V) -> some View {
        VStack(spacing: 2) { Text(titulo); abajo() }
            .font(.system(size: 12)).foregroundStyle(Color.sec).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 18).padding(.horizontal, 16)
    }
}

// MARK: Por proyecto

struct PorProyecto: View {
    let filas: [(nombre: String?, minutos: Double)]
    var body: some View {
        let mayor = max(1, filas.map(\.minutos).max() ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Por proyecto").font(.system(size: 13.5, weight: .semibold)); Spacer()
                Text("esta semana").font(.system(size: 12)).foregroundStyle(Color.sec)
            }
            ForEach(filas.indices, id: \.self) { i in
                let f = filas[i]
                VStack(spacing: 5) {
                    HStack {
                        Text(f.nombre ?? String(localized: "Sin proyecto")).font(.system(size: 12.5, weight: f.nombre == nil ? .regular : .semibold))
                            .foregroundStyle(f.nombre == nil ? Color.sec : Color.texto).lineLimit(1)
                        Spacer()
                        Text(horasMin(f.minutos)).font(.system(size: 12.5)).foregroundStyle(Color.sec).monospacedDigit()
                    }
                    Barra(valor: f.minutos / mayor, relleno: f.nombre == nil ? AnyShapeStyle(Color(hex: "#3a3a3e")) : AnyShapeStyle(degradadoLuz))
                }
            }
        }.padding(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16)).tarjeta()
    }
}

// MARK: Ajustes › Integraciones

struct IntegracionesVista: View {
    @Bindable var m: Embery
    @State private var diaria = ""
    @State private var hook: Bool?
    @State private var falloHook: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: 10)) { _ in obsidian }
            claude
            vscode
        }
    }

    // MARK: Obsidian

    @ViewBuilder private var obsidian: some View {
        let a = m.ajustes, elegida = !a.boveda.isEmpty, conectada = Boveda.disponible(a.boveda), on = a.obsidian ?? elegida
        Filas {
            cabecera(String(localized: "Obsidian"), String(localized: "Registra cada sesión en tu bóveda"), bien: on && conectada, icono: iconoApp("md.obsidian", "doc.text"),
                     on: Binding(get: { on }, set: { m.datos.ajustes.obsidian = $0 }))
            if on {
                Fila(titulo: String(localized: "Bóveda"), sub: !elegida ? String(localized: "Sin elegir") : conectada ? String(localized: "● Conectada") : String(localized: "○ Desconectada")) {
                    enlace(elegida ? String(localized: "\(URL(fileURLWithPath: a.boveda).lastPathComponent) ›") : String(localized: "Elegir…"), m.elegirBoveda)
                }
                if elegida {
                    Group {
                        Fila(titulo: String(localized: "Carpeta de sesiones")) { ruta(a.carpetaSesiones + "/") { elegir(carpeta: true) { m.datos.ajustes.carpetaSesiones = $0 } } }
                        Fila(titulo: String(localized: "Carpeta de entrada"), sub: String(localized: "Para Nota rápida")) {
                            ruta(a.entrada + "/") { elegir(carpeta: true) { m.datos.ajustes.carpetaEntrada = $0 == "inbox" ? nil : $0 } }
                        }
                        Fila(titulo: String(localized: "Plantilla de la nota"), sub: String(localized: "Frontmatter y texto de cada sesión")) {
                            Menu {
                                Button(String(localized: "Elegir archivo…")) { elegir(carpeta: false) { m.datos.ajustes.plantillaSesion = $0 } }
                                Button(String(localized: "De serie")) { m.datos.ajustes.plantillaSesion = nil }
                            } label: {
                                Text("\(a.plantillaSesion.map { URL(fileURLWithPath: $0).lastPathComponent } ?? String(localized: "De serie")) ›").foregroundStyle(Color.luz)
                            }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                        }
                        Fila(titulo: String(localized: "Nota diaria"), sub: String(localized: "Casillas y línea de cada sesión")) {
                            TextField("", text: $diaria).textFieldStyle(.plain).font(Tipo.mono).foregroundStyle(Color.sec)
                                .multilineTextAlignment(.trailing).frame(maxWidth: 170)
                                .onAppear { diaria = a.patronDiaria }
                                .onSubmit(guardarDiaria)
                                .help(String(localized: "{fecha} es el día en AAAA-MM-DD; ↩ para guardar"))
                        }
                        Fila(titulo: String(localized: "Línea en la nota diaria")) { Interruptor(on: $m.datos.ajustes.lineaDiaria) }
                        Fila(titulo: String(localized: "Nota por sesión")) { Interruptor(on: $m.datos.ajustes.notaSesion) }
                    }.opacity(conectada ? 1 : 0.55).disabled(!conectada)
                }
            }
        }
        .animation(salida(Dura.altura).sinMovimiento(m.reducir, funde: false), value: on)
        if on {
            let n = m.datos.sesiones.filter { !$0.registrada }.count
            if !elegida { Aviso(texto: String(localized: "Elige la carpeta de tu bóveda para empezar a registrar.")) }
            else if !conectada {
                Aviso(texto: String(localized: "El disco no está montado.") + (n == 0 ? "" : n == 1 ? String(localized: " 1 sesión espera; se escribirá sola.") : String(localized: " \(n) sesiones esperan; se escribirán solas.")))
            }
        }
    }

    // Un patrón sin {fecha} escribiría siempre en la misma nota: se vuelve al que había.
    private func guardarDiaria() {
        let p = diaria.trimmingCharacters(in: .whitespaces)
        guard p.contains("{fecha}") || p.contains("{date}") else { diaria = m.ajustes.patronDiaria; return }
        m.datos.ajustes.notaDiaria = p == Ajustes().patronDiaria ? nil : p
    }

    // MARK: Claude Code

    @ViewBuilder private var claude: some View {
        let detectado = JornadaTarjeta.detectado, on = m.ajustes.claudeCode ?? true
        Filas {
            cabecera(String(localized: "Claude Code"), detectado ? String(localized: "Detectado") : String(localized: "No encontrado"), bien: on && detectado, icono: iconoSF("terminal"), on: opcional(\.claudeCode, true))
            if on && detectado {
                Fila(titulo: String(localized: "Jornada en Estadísticas"), sub: String(localized: "Lee sus conversaciones locales")) { Interruptor(on: opcional(\.jornadaClaude, true)) }
                Fila(titulo: String(localized: "Conversaciones en el Hueco"), sub: String(localized: "Cuenta al reabrir Embery")) { Interruptor(on: opcional(\.conversacionesHueco, true)) }
                Fila(titulo: String(localized: "Abrir conversaciones en"), sub: String(localized: "Al soltar una carpeta o desde un proyecto")) {
                    let ops = [("terminal", "Terminal"), ("iterm", "iTerm"), ("app", String(localized: "App de Claude"))]
                    Menu {
                        Picker("", selection: Binding(get: { m.ajustes.terminalClaude ?? "terminal" }, set: { m.datos.ajustes.terminalClaude = $0 == "terminal" ? nil : $0 })) {
                            ForEach(ops, id: \.0) { Text($0.1).tag($0.0) }
                        }.pickerStyle(.inline).labelsHidden()
                    } label: {
                        Text("\(ops.first { $0.0 == (m.ajustes.terminalClaude ?? "terminal") }?.1 ?? "Terminal") ›").foregroundStyle(Color.sec)
                    }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
                if let ruta = InstaladorHook.rutaHook {
                    let cmd = InstaladorHook.comando(hook: ruta), url = InstaladorHook.ajustesClaude
                    let linea = InstaladorHook.rutaEstado.map { InstaladorHook.comando(hook: $0) }
                    let conectado = InstaladorHook.lineaAjena(en: url) ? String(localized: "Conectado; los límites del plan necesitan la statusline de Embery") : String(localized: "Conectado en ~/.claude/settings.json")
                    Fila(titulo: String(localized: "Avisos y permisos"), sub: falloHook ?? (hook == true ? conectado : String(localized: "Añade embery-hook a los ajustes de Claude Code"))) {
                        enlace(hook == true ? String(localized: "Quitar") : String(localized: "Conectar…")) {
                            do {
                                if hook == true { try InstaladorHook.quitar(en: url) } else { try InstaladorHook.instalar(en: url, comando: cmd, linea: linea) }
                                falloHook = nil
                            } catch { falloHook = String(localized: "No se pudo leer settings.json: no se ha tocado") }
                            hook = InstaladorHook.instalado(en: url, comando: cmd)
                        }
                    }
                    .onAppear { hook = InstaladorHook.instalado(en: url, comando: cmd) }
                }
            }
        }.animation(salida(Dura.altura).sinMovimiento(m.reducir, funde: false), value: on)
    }

    // MARK: VS Code

    @ViewBuilder private var vscode: some View {
        let instalado = Editor.vscode.instalado, on = m.ajustes.vscode ?? instalado
        Filas {
            cabecera(String(localized: "VS Code"), instalado ? String(localized: "Detectado") : String(localized: "No encontrado"), bien: on && instalado, icono: iconoApp(Editor.vscode.bundle, "chevron.left.forwardslash.chevron.right"),
                     on: Binding(get: { on }, set: { m.datos.ajustes.vscode = $0 }))
            if on && instalado {
                Fila(titulo: String(localized: "Etiquetar con el proyecto abierto"), sub: String(localized: "La carpeta que usas en VS Code")) { Interruptor(on: opcional(\.etiquetarProyecto, true)) }
                Fila(titulo: String(localized: "Avisar de cambios sin commit"), sub: String(localized: "Si el proyecto es un repositorio")) { Interruptor(on: opcional(\.avisarCommit, true)) }
                Fila(titulo: String(localized: "Proyectos recientes en el Hueco")) { Interruptor(on: Binding(get: { m.activo(.vscode) }, set: { m.activar(.vscode, $0) })) }
                if Editor.cursor.instalado {
                    Fila(titulo: String(localized: "Incluir Cursor"), sub: String(localized: "Sus proyectos también cuentan")) { Interruptor(on: opcional(\.cursor, false)) }
                }
            }
        }.animation(salida(Dura.altura).sinMovimiento(m.reducir, funde: false), value: on)
    }

    // MARK: piezas

    private func cabecera<I: View>(_ nombre: String, _ sub: String, bien: Bool, icono: I, on: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            icono.frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: Radio.etiqueta, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(nombre).font(Tipo.fila)
                HStack(spacing: 5) { PuntoEstado(bien: bien); Text(sub).font(Tipo.sub).foregroundStyle(Color.sec) }
            }
            Spacer(minLength: 0)
            Interruptor(on: on)
        }.padding(.horizontal, 14).padding(.vertical, 11).frame(minHeight: 44)
    }

    @ViewBuilder private func iconoApp(_ bundle: String, _ sf: String) -> some View {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable()
        } else { iconoSF(sf) }
    }
    private func iconoSF(_ sf: String) -> some View {
        Color(hex: "#202024").overlay(Image(systemName: sf).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.texto))
    }

    private func enlace(_ t: String, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) { Text(t).font(.system(size: 13)).foregroundStyle(Color.luz) }.buttonStyle(.plain)
    }
    private func ruta(_ t: String, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) { Text("\(t) ›").font(Tipo.mono).foregroundStyle(Color.sec) }.buttonStyle(.plain)
    }

    private func opcional(_ k: WritableKeyPath<Ajustes, Bool?>, _ serie: Bool) -> Binding<Bool> {
        Binding(get: { m.ajustes[keyPath: k] ?? serie }, set: { m.datos.ajustes[keyPath: k] = $0 })
    }


    // Carpetas y plantilla se guardan relativas a la bóveda; lo que queda fuera de ella no vale.
    private func elegir(carpeta: Bool, _ poner: @escaping (String) -> Void) {
        let raiz = URL(fileURLWithPath: m.ajustes.boveda, isDirectory: true).standardizedFileURL
        let p = NSOpenPanel()
        p.canChooseDirectories = carpeta; p.canChooseFiles = !carpeta; p.canCreateDirectories = carpeta
        if !carpeta { p.allowedContentTypes = [.init(filenameExtension: "md")!] }
        p.directoryURL = raiz
        p.message = carpeta ? String(localized: "Elige una carpeta dentro de tu bóveda") : String(localized: "Elige la plantilla (un .md dentro de tu bóveda)")
        NSApp.activate()
        guard p.runModal() == .OK, let u = p.url?.standardizedFileURL, u.path.hasPrefix(raiz.path + "/") else { return }
        poner(String(u.path.dropFirst(raiz.path.count + 1)))
    }
}

extension Embery {
    func elegirBoveda() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        if !ajustes.boveda.isEmpty { p.directoryURL = URL(fileURLWithPath: ajustes.boveda) }
        p.message = String(localized: "Elige la carpeta de tu bóveda (la que tiene daily-notes)")
        NSApp.activate()
        guard p.runModal() == .OK, var u = p.url else { return }
        if let s = Boveda.sugerencia(para: u, patronDiaria: ajustes.patronDiaria) {
            let aviso = NSAlert()
            aviso.messageText = String(localized: "«\(u.lastPathComponent)» no parece una bóveda")
            aviso.informativeText = s == u ? String(localized: "No tiene .obsidian ni la carpeta de notas diarias. Embery las creará aquí.")
                : String(localized: "Está dentro de «\(s.lastPathComponent)», que sí lo parece. Las notas irían a una subcarpeta.")
            if s != u { aviso.addButton(withTitle: String(localized: "Usar «\(s.lastPathComponent)»")) }
            aviso.addButton(withTitle: String(localized: "Usar esta igualmente"))
            aviso.addButton(withTitle: String(localized: "Cancelar"))
            switch aviso.runModal() {
            case .alertFirstButtonReturn: if s != u { u = s }
            case .alertSecondButtonReturn: if s != u { break } else { return }
            default: return
            }
        }
        datos.ajustes.boveda = u.path; registrarPendientes()
    }

    // Añade embery-hook (y la statusline si no hay otra) a los ajustes de Claude Code.
    func conectarClaude() throws {
        guard let ruta = InstaladorHook.rutaHook else { throw CocoaError(.fileNoSuchFile) }
        try InstaladorHook.instalar(en: InstaladorHook.ajustesClaude, comando: InstaladorHook.comando(hook: ruta),
                                    linea: InstaladorHook.rutaEstado.map { InstaladorHook.comando(hook: $0) })
    }
}
