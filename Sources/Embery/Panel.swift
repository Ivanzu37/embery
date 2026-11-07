import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Vista: String, CaseIterable { case foco, hogar, estadisticas, ajustes }

struct PanelVista: View {
    @Bindable var m: Embery
    var hueco: Hueco?
    let lumenFoco: Buho, lumenHogar: Buho
    let plegar: () -> Void
    @State private var vista = Vista.foco
    @State private var encima: Vista?
    @State private var ancla: String?
    @Namespace private var ns

    private let iconos: [Vista: (String, String)] = [.foco: ("eye", String(localized: "Foco")), .hogar: ("house", String(localized: "Hogar")), .estadisticas: ("chart.bar", String(localized: "Estadísticas")), .ajustes: ("gearshape", String(localized: "Ajustes"))]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                // La activa se abre en píldora con su nombre; las otras quedan en icono.
                ForEach(Vista.allCases, id: \.self) { v in
                    let on = vista == v
                    Button { ir(v) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: iconos[v]!.0).font(.system(size: 16, weight: .regular))
                            if on {
                                Text(iconos[v]!.1).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).fixedSize()
                                    .transition(.opacity.animation(.easeOut(duration: 0.25)))
                            }
                        }
                        .foregroundStyle(on || encima == v ? Color.texto : Color.ter)
                        .padding(.leading, on ? 10 : 0).padding(.trailing, on ? 12 : 0)
                        .frame(minWidth: 36, minHeight: 36)
                        .background { if on { Capsule().fill(Color.capsula).matchedGeometryEffect(id: "pestana", in: ns) } }
                    }.buttonStyle(Hunde()).help(iconos[v]!.1).accessibilityLabel(iconos[v]!.1)
                        .onHover { encima = $0 ? v : encima == v ? nil : encima }
                }
                Spacer()
                HStack(spacing: 5) { Destello(); Text("\(m.cuentas.saldo)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.luz).contentTransition(.numericText()) }
                    .padding(.trailing, 4).animation(muelle, value: m.cuentas.saldo)
                Button(action: plegar) {
                    Image(systemName: m.ajustes.lado == "izq" ? "chevron.left" : "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ter).frame(width: 28, height: 28)
                }.buttonStyle(Hunde()).help(String(localized: "Plegar")).accessibilityLabel(String(localized: "Plegar panel"))
            }.padding(EdgeInsets(top: 12, leading: 12, bottom: 8, trailing: 12))
            .opacity(m.bienvenida ? 0.35 : 1).allowsHitTesting(!m.bienvenida).animation(salida(0.3), value: m.bienvenida)

            ScrollViewReader { lector in
                ScrollView(showsIndicators: false) {
                    Group {
                        switch vista {
                        case .foco: FocoVista(m: m, lumen: lumenFoco)
                        case .hogar: HogarVista(m: m, lumen: lumenHogar)
                        case .estadisticas: EstadisticasVista(m: m, hueco: hueco) { ir(.ajustes, ancla: "integraciones") }
                        case .ajustes: AjustesVista(m: m)
                        }
                    }.padding(.horizontal, 12).padding(.bottom, 12)
                    .transition(entra(m.reducir))
                    .id(vista)
                }
                .onChange(of: ancla) {
                    guard let a = ancla else { return }
                    // La vista nueva tiene que estar puesta antes de desplazarse a ella.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation(salida()) { lector.scrollTo(a, anchor: .top) }; ancla = nil }
                }
            }
        }
        .foregroundStyle(Color.texto)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }

    // Cambiar de pestaña con el cierre de foco abierto equivale a Omitir.
    private func ir(_ v: Vista, ancla a: String? = nil) {
        if v != vista { m.cerrar(nota: nil) }
        withAnimation(muelleForma.sinMovimiento(m.reducir)) { vista = v }
        ancla = a
    }
}

// MARK: Foco

struct FocoVista: View {
    @Bindable var m: Embery
    let lumen: Buho
    @State private var apps: [NSRunningApplication] = []
    @State private var proyectos: [ProyectoFoco] = []

    var body: some View {
        VStack(spacing: 10) {
            tarjetaLumen
            if m.bienvenida && m.foco == nil { BienvenidaVista(m: m, lumen: lumen).transition(entra(m.reducir)) }
            else if let f = m.foco { enSesion(f).transition(.opacity) }
            else if let c = m.cierre { CierreVista(m: m, s: c).transition(entra(m.reducir)) }
            else { preparar.transition(entra(m.reducir)) }
        }
        .animation(salida().sinMovimiento(m.reducir), value: m.bienvenida ? 3 : m.foco == nil ? (m.cierre == nil ? 0 : 2) : 1)
    }

    private var tarjetaLumen: some View {
        let n = m.necesidades
        return ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: "#121214"), Color(hex: "#101218")], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(170 / 255, 200 / 255, 1).opacity(0.09), .clear], center: UnitPoint(x: 0.5, y: 0.8), startRadius: 0, endRadius: 170)
            // Encuadrado para que la etapa ancestral no toque el título de la tarjeta.
            LumenVista(buho: lumen).opacity(m.plegado ? 0 : 1).animation(m.plegado ? .easeOut(duration: 0.1) : .easeIn(duration: 0.35).delay(0.45), value: m.plegado)
                .accessibilityLabel(String(localized: "Lumen")).accessibilityHint(String(localized: "Tócalo y da la vuelta a la cabeza"))
            HStack(alignment: .firstTextBaseline) {
                Text(m.humor.0).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(m.humor.1).font(.system(size: 12)).foregroundStyle(Color.sec)
            }.padding(.horizontal, 16).padding(.top, 14).allowsHitTesting(false)
            if !m.bienvenida { VStack { Spacer()
                HStack(spacing: 6) {
                    necesidad(String(localized: "Luz"), n.luz, LinearGradient(colors: [Color(hex: "#9fc0ff"), .white], startPoint: .leading, endPoint: .trailing))
                    necesidad(String(localized: "Sueño"), n.sueno, LinearGradient(colors: [Color(hex: "#8e9bb8")], startPoint: .leading, endPoint: .trailing))
                    necesidad(String(localized: "Ánimo"), n.animo, LinearGradient(colors: [Color(hex: "#b9addf")], startPoint: .leading, endPoint: .trailing))
                }.padding(12)
            }.allowsHitTesting(false) }
        }
        .frame(height: m.foco == nil && !m.bienvenida ? 262 : 300)
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: m.foco == nil)
        .tarjeta()
    }

    private func necesidad(_ nombre: String, _ v: Int, _ c: LinearGradient) -> some View {
        VStack(spacing: 5) {
            HStack { Text(nombre); Spacer(); Text("\(v)%").fontWeight(.semibold).foregroundStyle(Color.texto) }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(c).frame(width: g.size.width * Double(v) / 100).animation(.easeOut(duration: 0.6), value: v)
                }
            }.frame(height: 4)
        }
        .font(.system(size: 11)).foregroundStyle(Color.sec)
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial).opacity(0.5))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private var preparar: some View {
        VStack(spacing: 10) {
            Segmento(opciones: [(Modo.temporizador, String(localized: "Temporizador")), (.cronometro, String(localized: "Cronómetro")), (.app, String(localized: "App"))], valor: $m.modo)
            opciones
            Filas {
                if m.etiquetar { filaProyecto }
                Fila(titulo: String(localized: "Bloquear distracciones"), sub: String(localized: "\(m.datos.bloqueos.count) apps y webs de tu lista")) { Interruptor(on: $m.datos.ajustes.bloquear) }
            }
            if let r = m.previa { PreviaVista(m: m, r: r).padding(.horizontal, 6) } else {
                Button("Concentrarse") { m.empezar() }.buttonStyle(Principal())
                    .disabled(m.modo == .app && m.appElegida == nil).opacity(m.modo == .app && m.appElegida == nil ? 0.5 : 1)
            }
            let c = m.cuentas
            HStack {
                Text("Hoy \(Text(duracion(c.hoyMin)).foregroundColor(.texto).fontWeight(.semibold))")
                Spacer()
                Text(c.sesiones(c.hoy).count == 1 ? String(localized: "1 sesión") : String(localized: "\(c.sesiones(c.hoy).count) sesiones"))
                Spacer()
                Text("Racha \(Text(c.racha == 1 ? String(localized: "1 día") : String(localized: "\(c.racha) días")).foregroundColor(.texto).fontWeight(.semibold))")
            }.font(.system(size: 12)).foregroundStyle(Color.sec).padding(.horizontal, 10).padding(.top, 4)
        }
    }

    @ViewBuilder private var opciones: some View {
        switch m.modo {
        case .temporizador:
            Filas {
                Fila(titulo: String(localized: "Duración")) {
                    HStack(spacing: 6) {
                        ForEach([25, 50, 90], id: \.self) { d in
                            Button { withAnimation(muelle) { m.datos.ajustes.duracionMin = d } } label: { Chip(texto: "\(d)", on: m.ajustes.duracionMin == d) }.buttonStyle(Hunde())
                        }
                        Menu {
                            ForEach([15, 20, 30, 40, 45, 60, 75, 120], id: \.self) { d in Button(String(localized: "\(d) min")) { m.datos.ajustes.duracionMin = d } }
                        } label: { Chip(texto: [25, 50, 90].contains(m.ajustes.duracionMin) ? "···" : "\(m.ajustes.duracionMin)", on: ![25, 50, 90].contains(m.ajustes.duracionMin)) }
                            .menuStyle(.button).buttonStyle(Hunde()).menuIndicator(.hidden).fixedSize()
                    }
                }
                Fila(titulo: String(localized: "Descanso y rondas")) {
                    Menu {
                        Picker("Descanso", selection: $m.datos.ajustes.descansoMin) { ForEach([5, 10, 15, 20], id: \.self) { Text("\($0) min").tag($0) } }
                        Picker(String(localized: "Rondas"), selection: $m.datos.ajustes.rondas) { ForEach(1...6, id: \.self) { Text($0 == 1 ? String(localized: "1 ronda") : String(localized: "\($0) rondas")).tag($0) } }
                    } label: { Text("\(m.ajustes.descansoMin) min · \(m.ajustes.rondas) \(m.ajustes.rondas == 1 ? String(localized: "ronda") : String(localized: "rondas"))").foregroundStyle(Color.sec) }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
                filaTarea
            }
        case .cronometro:
            Filas {
                Fila(titulo: String(localized: "Sin límite"), sub: String(localized: "Para cuando tú quieras; su luz sigue subiendo")) { EmptyView() }
                filaTarea
            }
        case .app:
            Filas {
                ForEach(apps, id: \.processIdentifier) { a in
                    let elegida = m.appElegida?.processIdentifier == a.processIdentifier
                    Button { withAnimation(muelle) { m.appElegida = a } } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: a.icon ?? NSImage()).resizable().frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.localizedName ?? "App").font(.system(size: 13))
                                if elegida { Text("Cuenta solo mientras la usas").font(.system(size: 11.5)).foregroundStyle(Color.sec) }
                            }
                            Spacer()
                            Chip(texto: elegida ? String(localized: "Elegida") : String(localized: "Elegir"), on: elegida)
                        }.padding(.horizontal, 14).padding(.vertical, 9).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(Hunde(escala: 0.98))
                }
            }
            .onAppear(perform: cargarApps)
        }
    }

    private var filaProyecto: some View {
        Fila(titulo: String(localized: "Proyecto"), sub: m.proyecto == nil ? String(localized: "Se etiqueta solo con VS Code") : String(localized: "Lo lee de VS Code")) {
            Menu {
                ForEach(proyectos, id: \.nombre) { p in Button(p.nombre) { m.elegirProyecto(p) } }
                if !proyectos.isEmpty { Divider() }
                Button("Ninguno") { m.elegirProyecto(nil) }
            } label: {
                HStack(spacing: 6) {
                    if let p = m.proyecto {
                        Text(p.nombre).foregroundStyle(Color.luz).lineLimit(1)
                        if !m.proyectoAMano { Etiqueta(texto: String(localized: "Auto"), mayusculas: true) }
                    } else { Text("Ninguno ›").foregroundStyle(Color.sec) }
                }.font(.system(size: 13))
            }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
        .task { cargarProyectos() }
    }

    // Los proyectos de esta semana: los que VS Code tocó y los que ya llevan sesiones.
    private func cargarProyectos() {
        let eds = m.editores, c = m.cuentas, lunes = c.semana[0]
        let deSesiones = c.semana.flatMap { c.sesiones($0) }.compactMap(\.proyecto)
        m.detectarProyecto()
        DispatchQueue.global(qos: .utility).async {
            let vistos = EditorRecientes.recientes(eds, cuantos: 8).filter { $0.usado >= lunes }.map { ProyectoFoco(nombre: $0.nombre, carpeta: $0.carpeta) }
            var nombres = Set<String>()
            let todos = (vistos + deSesiones.map { ProyectoFoco(nombre: $0, carpeta: nil) }).filter { nombres.insert($0.nombre).inserted }
            DispatchQueue.main.async { proyectos = todos }
        }
    }

    private var filaTarea: some View {
        Fila(titulo: String(localized: "Tarea")) {
            TextField("Tarea", text: $m.datos.ajustes.tarea).textFieldStyle(.plain).multilineTextAlignment(.trailing).foregroundStyle(Color.sec).frame(maxWidth: 150)
        }
    }

    private func cargarApps() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && $0.bundleIdentifier != "com.apple.finder" }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        if let e = m.appElegida, !apps.contains(e) { m.appElegida = nil }
    }

    private func enSesion(_ f: Foco) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(m.relojTexto).font(.system(size: 54, weight: .semibold, design: .rounded)).monospacedDigit().tracking(-1)
                Text(m.relojSub).font(.system(size: 12.5)).foregroundStyle(Color.sec)
            }.padding(.top, 4)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.tarjeta2)
                    Capsule().fill(LinearGradient(colors: [Color(hex: "#9fc0ff"), .white], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * m.progreso(f)).shadow(color: Color(190 / 255, 215 / 255, 1).opacity(0.55), radius: 6)
                }
            }.frame(height: 5).padding(.horizontal, 6)
            HStack(spacing: 14) {
                Text("Luz \(Text("+\(Int(f.segundos / 60)) min").foregroundColor(.luz).fontWeight(.semibold))")
                Text("Destellos \(Text("+\(Int(f.segundos / 60))").foregroundColor(.luz).fontWeight(.semibold))")
                Text("Bloqueo \(Text(m.bloqueando ? String(localized: "activo") : String(localized: "en pausa")).foregroundColor(m.bloqueando ? .luzOn : .sec).fontWeight(.semibold))")
            }.font(.system(size: 12)).foregroundStyle(Color.sec)
            HStack(spacing: 8) {
                Button(f.pausada ? "Seguir" : "Pausa") { m.pausar() }.buttonStyle(Secundario())
                Mantener { m.terminar() }
            }
        }
    }
}

func duracion(_ min: Double) -> String {
    let m = Int(min.rounded())
    return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
}

// MARK: Hogar

private let ICONO_HOJA = ##"<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 12 12"><path d="M1 11C1 5 5 1 11 1 11 7 7 11 1 11Z" fill="#56785f"/></svg>"##
private let ICONO_FLOR = ##"<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 12 12"><g fill="#dfe8f8"><circle cx="6" cy="3" r="2"/><circle cx="9" cy="6" r="2"/><circle cx="6" cy="9" r="2"/><circle cx="3" cy="6" r="2"/></g><circle cx="6" cy="6" r="1.4" fill="#a9c6ff"/></svg>"##
private let ICONO_LUCI = ##"<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 12 12"><circle cx="6" cy="6" r="5" fill="#d2e4ff" opacity=".2"/><circle cx="6" cy="6" r="2" fill="#fff"/></svg>"##

let DIBUJOS: [String: String] = [
    "luciernagas": ##"<svg xmlns="http://www.w3.org/2000/svg" width="30" height="40" viewBox="0 0 30 40"><rect x="6" y="9" width="18" height="26" rx="6" fill="#d2e4ff" fill-opacity=".08" stroke="#5a6680" stroke-width="2"/><rect x="9" y="4" width="12" height="5" rx="2" fill="#5a6680"/><circle cx="12" cy="20" r="3" fill="#e6f0ff" opacity=".25"/><circle cx="12" cy="20" r="1.3" fill="#fff"/><circle cx="18" cy="27" r="3" fill="#e6f0ff" opacity=".25"/><circle cx="18" cy="27" r="1.3" fill="#fff"/><circle cx="15" cy="15" r="1" fill="#fff" opacity=".8"/></svg>"##,
    "musgo": ##"<svg xmlns="http://www.w3.org/2000/svg" width="44" height="30" viewBox="0 0 44 30"><ellipse cx="22" cy="21" rx="18" ry="6" fill="#2f4639"/><ellipse cx="16" cy="17" rx="10" ry="6" fill="#4a6b59"/><ellipse cx="28" cy="16" rx="11" ry="7" fill="#56785f"/><ellipse cx="25" cy="12" rx="6" ry="3" fill="#7a9a84" opacity=".7"/></svg>"##,
    "nido": ##"<svg xmlns="http://www.w3.org/2000/svg" width="46" height="30" viewBox="0 0 46 30"><path d="M4 13 C6 25 40 25 42 13 Z" fill="#4a3f36"/><ellipse cx="23" cy="13" rx="19" ry="5" fill="#2a241f"/><path d="M5 15 C14 19 30 19 41 14 M7 19 C16 22 30 22 39 18 M10 13 l9 5 M27 18 l9 -5" stroke="#6b5a4b" stroke-width="1.3" fill="none" stroke-linecap="round"/></svg>"##,
    "seta": ##"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="34" viewBox="0 0 40 34"><g fill="#9aa6bc"><path d="M12 32 Q14 24 13 18 h2 Q16 24 15 32Z"/><path d="M22 32 Q25 22 23 13 h2.5 Q27 22 25 32Z"/><path d="M30 32 Q32 26 31 22 h2 Q34 26 33 32Z"/></g><g fill="#c6d4ec"><path d="M8 19 a6 4 0 0 1 12 0Z"/><path d="M16 14 a8 5.5 0 0 1 16 0Z"/><path d="M27.5 22.5 a4.5 3 0 0 1 9 0Z"/></g><circle cx="24" cy="10" r="10" fill="#d2e4ff" opacity=".08"/></svg>"##,
    "campanilla": ##"<svg xmlns="http://www.w3.org/2000/svg" width="30" height="42" viewBox="0 0 30 42"><path d="M15 1v6" stroke="#8a96ae" stroke-width="1"/><ellipse cx="15" cy="8" rx="8" ry="2.2" fill="#5a6680"/><g fill="#dfe8f8" fill-opacity=".45"><rect x="8.5" y="11" width="2.4" height="17" rx="1.2"/><rect x="12.5" y="11" width="2.4" height="23" rx="1.2"/><rect x="16.5" y="11" width="2.4" height="20" rx="1.2"/><rect x="20.5" y="11" width="2.4" height="15" rx="1.2"/></g></svg>"##,
    "guirnalda": ##"<svg xmlns="http://www.w3.org/2000/svg" width="48" height="30" viewBox="0 0 48 30"><path d="M2 6 Q24 30 46 6" fill="none" stroke="#8a96ae" stroke-width="1"/><g fill="#ecf4ff"><ellipse cx="9" cy="13" rx="1.8" ry="2.4"/><ellipse cx="17" cy="18.5" rx="1.8" ry="2.4"/><ellipse cx="25" cy="20.5" rx="1.8" ry="2.4"/><ellipse cx="33" cy="18" rx="1.8" ry="2.4"/><ellipse cx="40" cy="12.5" rx="1.8" ry="2.4"/></g><g fill="#d2e4ff" opacity=".12"><circle cx="17" cy="18.5" r="5"/><circle cx="33" cy="18" r="5"/></g></svg>"##,
    "farolillo": ##"<svg xmlns="http://www.w3.org/2000/svg" width="30" height="42" viewBox="0 0 30 42"><path d="M15 1 v6" stroke="#5a6680" stroke-width="1.5"/><rect x="9" y="6" width="12" height="3" rx="1.5" fill="#5a6680"/><ellipse cx="15" cy="22" rx="10" ry="13" fill="#dfe8f8" fill-opacity=".14" stroke="#5a6680" stroke-width="1.6"/><path d="M8 17 C12 16 18 16 22 17 M7 23 C12 22 18 22 23 23 M8 29 C12 28 18 28 22 29" stroke="#5a6680" stroke-width="1" fill="none"/><ellipse cx="15" cy="22" rx="4.5" ry="6.5" fill="#dfe8f8" opacity=".6"/><rect x="11" y="35" width="8" height="3" rx="1.5" fill="#5a6680"/></svg>"##,
]

struct HogarVista: View {
    @Bindable var m: Embery
    let lumen: Buho
    @State private var escena = EscenaHogar()
    @State private var encima = false

    var body: some View {
        let c = m.cuentas, d = datos
        VStack(spacing: 10) {
            // En el hogar se posa en la rama; la escena se dibuja en la misma vista, detrás y delante de él.
            LumenVista(buho: lumen, escena: escena).accessibilityLabel(String(localized: "Lumen en su rama"))
                .frame(height: HH).tarjeta()
                .overlay { huecos(c) }
                .onHover { v in withAnimation(m.reducir ? nil : .easeOut(duration: 0.4)) { encima = v } }
                .onAppear { escena.d = d }
                .onChange(of: m.ahora) { escena.d = datos }
                .onChange(of: m.datos.compras.count) { escena.d = datos }

            HStack {
                dato(d.hojas, String(localized: "hojas"), String(localized: "Las hojas crecen con tus horas de luz")) { Image(nsImage: svg(ICONO_HOJA)) }
                Spacer()
                dato(d.flores, String(localized: "flores"), String(localized: "Una flor por cada día de racha")) { Image(nsImage: svg(ICONO_FLOR)) }
                Spacer()
                dato(d.luciernagas, String(localized: "luciérnagas"), String(localized: "Las luciérnagas son tu luz de hoy")) { Image(nsImage: svg(ICONO_LUCI)) }
            }.font(.system(size: 11.5)).foregroundStyle(Color.sec).padding(.horizontal, 8).padding(.top, 2)

            Text("Tienda").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sec).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.top, 6)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(TIENDA, id: \.clave) { articulo($0) }
            }
        }
    }

    private var datos: DatosHogar {
        let c = m.cuentas
        return DatosHogar(estado: m.estado, horas: c.horasLuz, racha: c.racha, hoy: c.hoyMin / Double(m.ajustes.objetivoMin),
                          tiene: Set(TIENDA.filter { $0.mueble && c.tiene($0.clave) }.map(\.clave)), reducir: m.reducir)
    }

    private func dato(_ n: Int, _ nombre: String, _ ayuda: String, @ViewBuilder icono: () -> some View) -> some View {
        HStack(spacing: 6) { icono(); Text("\(Text("\(n)").foregroundColor(.texto).fontWeight(.semibold)) \(nombre)") }
            .help(ayuda).accessibilityElement(children: .combine)
    }

    // Los huecos libres solo se ven con el ratón encima de la escena, para no ensuciarla.
    private func huecos(_ c: Cuentas) -> some View {
        GeometryReader { g in
            let sx = g.size.width / HW, sy = g.size.height / HH
            ForEach(MUEBLES_HOGAR.filter { !c.tiene($0.clave) }, id: \.clave) { h in
                Text("+").font(.system(size: 13)).foregroundStyle(Color(210, 228, 255).opacity(0.5))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color(210, 228, 255).opacity(0.28), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5])))
                    .help(TIENDA.first { $0.clave == h.clave }?.nombre ?? "")
                    .position(x: h.x * sx, y: h.y * sy)
            }
            .opacity(encima ? 1 : 0)
        }
    }

    private func articulo(_ a: Articulo) -> some View {
        let c = m.cuentas, hecho = a.mueble ? c.tiene(a.clave) : c.compradoHoy(a.clave), falta = a.precio - c.saldo, puede = falta <= 0 && !hecho
        return VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "#1b1b1e")).frame(height: 54).overlay(Image(nsImage: svg(DIBUJOS[a.clave]!)))
            VStack(alignment: .leading, spacing: 1) {
                Text(a.nombre).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(a.efecto).font(.system(size: 11.5)).foregroundStyle(Color.sec)
            }
            Spacer(minLength: 0)
            Button { withAnimation(m.reducir ? nil : muelle) { m.comprar(a) } } label: {
                HStack(spacing: 4) {
                    if hecho { Text(a.mueble ? String(localized: "Colocado") : String(localized: "Hoy ya")) }
                    else if falta > 0 { Text("Faltan"); Destello(color: .sec, tam: 10); Text("\(falta)") }
                    else { Destello(tam: 10); Text("\(a.precio)") }
                }.font(.system(size: 12.5, weight: .semibold)).foregroundStyle(puede ? Color.luz : Color.sec)
                    .frame(maxWidth: .infinity).frame(height: 30)
                    .background(Capsule().fill(hecho ? Color.clear : puede ? Color.luzTenue : Color(hex: "#1b1b1e")))
                    .overlay(Capsule().strokeBorder(hecho ? Color.linea : .clear))
            }.buttonStyle(Hunde()).disabled(!puede)
        }.padding(12).frame(maxHeight: .infinity, alignment: .top).tarjeta()
    }
}

// MARK: Estadísticas

struct EstadisticasVista: View {
    @Bindable var m: Embery
    var hueco: Hueco?
    var aIntegraciones: () -> Void = {}
    private let letras = ["L", "M", "X", "J", "V", "S", "D"]

    var body: some View {
        let c = m.cuentas, dif = c.hoyMin - c.ayerMin, semana = c.semana, horas = semana.map { c.minutos($0) / 60 }
        let maximo = max(1, horas.max() ?? 1), h = c.horasLuz, i = etapaPorHoras(h), sig = i + 1 < ETAPAS.count ? ETAPAS[i + 1] : nil
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hoy").foregroundStyle(Color.sec)
                Text(duracion(c.hoyMin)).font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-0.7)
                if c.sesiones(c.hoy).isEmpty { Text(String(localized: "Aún nada hoy")).font(.system(size: 12)).foregroundStyle(Color.sec) } else {
                    Text("\(Text(dif >= 0 ? String(localized: "▲ \(duracion(dif)) más que ayer") : String(localized: "▼ \(duracion(-dif)) menos que ayer")).foregroundColor(.luzOn).fontWeight(.medium))\(Text(String(localized: " · \(c.sesiones(c.hoy).count) sesiones")).foregroundColor(.sec))").font(.system(size: 12))
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).tarjeta()

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("\(c.racha)").font(.system(size: 20, weight: .semibold))
                    Text(String(localized: "días de racha")).font(.system(size: 12)).foregroundStyle(Color.sec).lineLimit(1).fixedSize()
                }
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        let dia = semana[d], esHoy = c.cal.isDate(dia, inSameDayAs: c.hoy), hubo = !c.sesiones(dia).isEmpty
                        VStack(spacing: 2) {
                            Destello(color: esHoy ? .white : hubo ? .luzOn : Color(hex: "#2a2a2e"), tam: 13)
                            Text(letras[d]).font(.system(size: 10)).foregroundStyle(Color.ter)
                        }.frame(width: 20, height: 30)
                    }
                }
            }.padding(.horizontal, 16).padding(.vertical, 14).tarjeta()

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Esta semana").font(.system(size: 13.5, weight: .semibold)); Spacer()
                    Text(duracion(horas.reduce(0, +) * 60)).font(.system(size: 12)).foregroundStyle(Color.sec)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<7, id: \.self) { d in
                        let esHoy = c.cal.isDate(semana[d], inSameDayAs: c.hoy)
                        VStack(spacing: 6) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(esHoy ? AnyShapeStyle(LinearGradient(colors: [.white, .luzOn], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color(hex: "#2a2a2e")))
                                .frame(height: max(4, horas[d] / maximo * 70))
                                .shadow(color: esHoy ? Color(170 / 255, 200 / 255, 1).opacity(0.35) : .clear, radius: 7)
                            Text(letras[d]).font(.system(size: 10.5)).foregroundStyle(esHoy ? Color.texto : Color.ter)
                        }
                    }
                }.frame(height: 96).padding(.top, 12)
            }.padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16)).tarjeta()

            let porProyecto = c.porProyecto(semana)
            if !porProyecto.isEmpty { PorProyecto(filas: porProyecto) }

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Lumen \(ETAPAS[i].nombre.lowercased())").font(.system(size: 13.5, weight: .semibold)); Spacer()
                    Text(sig.map { String(localized: "\(Int(h)) h de luz · faltan \(Int(($0.desde - h).rounded(.up))) h") } ?? String(localized: "\(Int(h)) h de luz")).font(.system(size: 12)).foregroundStyle(Color.sec)
                }
                let tramo: Double = sig.map { (h - ETAPAS[i].desde) / ($0.desde - ETAPAS[i].desde) } ?? 0
                let avance = (Double(i) + tramo) / Double(ETAPAS.count - 1)
                ZStack(alignment: .top) {
                    GeometryReader { g in
                        let ancho = g.size.width - 56
                        Capsule().fill(Color(hex: "#2a2a2e")).frame(width: ancho, height: 3).offset(x: 28, y: 14)
                        Capsule().fill(LinearGradient(colors: [.luzOn, .white], startPoint: .leading, endPoint: .trailing)).frame(width: ancho * avance, height: 3).offset(x: 28, y: 14)
                    }
                    HStack {
                        ForEach(0..<ETAPAS.count, id: \.self) { j in
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(j == i ? AnyShapeStyle(LinearGradient(colors: [.white, .luzOn], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color(hex: j < i ? "#1a2233" : "#1d1d20")))
                                    Circle().strokeBorder(Color(hex: j == i ? "#e6efff" : j < i ? "#a9c6ff" : "#2a2a2e"), lineWidth: 2)
                                    if j <= i { Destello(color: j == i ? Color(hex: "#0d1424") : .luzOn, tam: 11) }
                                }.frame(width: 31, height: 31).shadow(color: j == i ? Color(170 / 255, 200 / 255, 1).opacity(0.6) : .clear, radius: 7)
                                Text(ETAPAS[j].nombre).font(.system(size: 10.5)).foregroundStyle(j <= i ? Color.texto : Color.ter)
                            }.frame(width: 56)
                            if j < ETAPAS.count - 1 { Spacer(minLength: 0) }
                        }
                    }
                }.padding(EdgeInsets(top: 14, leading: 0, bottom: 8, trailing: 0))
            }.padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)).tarjeta()

            if JornadaTarjeta.detectado && (m.ajustes.jornadaClaude ?? true) { JornadaTarjeta(m: m, hueco: hueco, activar: aIntegraciones) }
            // Con Claude Code conectado, su Huella (tokens por día) también vive aquí.
            if let h = hueco { Huella(dias: h.dias) }

            Text("Cuaderno").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sec).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.top, 6)
            let ultimas = Array(m.datos.sesiones.suffix(8).reversed())
            if ultimas.isEmpty {
                Text(String(localized: "Aún no hay sesiones.\nLa primera empieza en Foco.")).multilineTextAlignment(.center).font(.system(size: 12)).foregroundStyle(Color.sec).frame(maxWidth: .infinity).padding(16).tarjeta()
            } else {
                Filas {
                    ForEach(ultimas) { s in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(s.app.map { "\($0) (app)" } ?? s.tarea).font(.system(size: 13)).lineLimit(1)
                                    if let p = s.proyecto { Etiqueta(texto: p) }
                                }
                                Text("\(Text(verbatim: "\(Registro.fecha(s.inicio, "dd/MM HH:mm")) · \(duracion(Double(s.minutos)))\(s.nota == nil ? "" : " · ")"))\(Text(verbatim: s.nota ?? "").foregroundColor(Color.texto.opacity(0.8)))")
                                    .font(.system(size: 11.5)).foregroundStyle(Color.sec).lineLimit(1).truncationMode(.tail)
                            }
                            Spacer(minLength: 0)
                            HStack(spacing: 3) { Destello(tam: 10); Text("\(s.destellos)") }.foregroundStyle(Color.luz).monospacedDigit()
                        }.padding(.horizontal, 14).padding(.vertical, 11).frame(minHeight: 44)
                    }
                }
            }
        }
    }
}

// MARK: Ajustes

struct AjustesVista: View {
    @Bindable var m: Embery
    @State private var web = ""
    private let act = Actualizar.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            grupo(String(localized: "General"))
            Filas {
                Fila(titulo: String(localized: "Lado de la pantalla")) { Segmento(opciones: [("izq", String(localized: "Izquierda")), ("der", String(localized: "Derecha"))], valor: $m.datos.ajustes.lado, mini: true) }
                Fila(titulo: String(localized: "Pestaña del borde")) {
                    Segmento(opciones: [("rama", String(localized: "Rama")), ("lateral", "Notch")], valor: Binding(get: { m.ajustes.borde ?? "rama" }, set: { m.datos.ajustes.borde = $0 }), mini: true)
                }
                Fila(titulo: String(localized: "Pantalla"), sub: String(localized: "Automática: la del notch, si no la principal")) {
                    // Una pantalla elegida que no está conectada se guarda hasta que vuelva; mientras, manda la automática.
                    let ops = Pantallas.opciones, e = m.ajustes.pantalla
                    Menu {
                        Picker("", selection: Binding(get: { e ?? "" }, set: { m.datos.ajustes.pantalla = $0.isEmpty ? nil : $0 })) {
                            Text(String(localized: "Automática")).tag("")
                            ForEach(ops, id: \.id) { Text($0.nombre).tag($0.id) }
                        }.pickerStyle(.inline).labelsHidden()
                    } label: {
                        Text(e.map { id in ops.first { $0.id == id }?.nombre ?? String(localized: "Desconectada") } ?? String(localized: "Automática")).foregroundStyle(Color.sec)
                    }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
                Fila(titulo: String(localized: "Abrir al iniciar sesión")) { Interruptor(on: Binding(get: { m.ajustes.abrirAlIniciar }, set: { m.abrirAlIniciar($0) })) }
                Fila(titulo: String(localized: "Versión \(act.version)")) {
                    Button(String(localized: "Buscar actualizaciones…"), action: act.buscar).buttonStyle(.plain).foregroundStyle(Color.luz)
                        .font(.system(size: 12.5, weight: .medium)).disabled(!act.puedeBuscar)
                }
                Fila(titulo: String(localized: "Buscar actualizaciones sola"), sub: String(localized: "Una vez por semana, sin interrumpir")) {
                    Interruptor(on: Binding(get: { act.sola }, set: { act.sola = $0 }))
                }
            }
            grupo(String(localized: "Foco"))
            Filas {
                Fila(titulo: String(localized: "Objetivo diario"), sub: String(localized: "La pestaña del borde se llena hacia él")) {
                    menu($m.datos.ajustes.objetivoMin, [60, 90, 120, 180, 240, 300, 360]) { $0 % 60 == 0 ? "\($0 / 60) h" : "\($0 / 60) h \($0 % 60)" }
                }
                Fila(titulo: String(localized: "Duración por defecto")) { menu($m.datos.ajustes.duracionMin, [15, 20, 25, 30, 40, 45, 50, 60, 75, 90, 120]) { String(localized: "\($0) min") } }
                Fila(titulo: String(localized: "Descanso")) { menu($m.datos.ajustes.descansoMin, [5, 10, 15, 20]) { String(localized: "\($0) min") } }
                Fila(titulo: String(localized: "Rondas")) { menu($m.datos.ajustes.rondas, Array(1...6)) { "\($0)" } }
                Fila(titulo: String(localized: "Al terminar, preguntar qué has hecho"), sub: String(localized: "Una línea opcional que va al registro")) { Interruptor(on: opcional(\.preguntarAlTerminar, true)) }
            }
            grupo(String(localized: "Integraciones")).id("integraciones")
            IntegracionesVista(m: m)
            grupo(String(localized: "Bloqueo durante el foco"))
            Filas {
                ForEach(m.datos.bloqueos) { b in
                    HStack(spacing: 10) {
                        icono(b)
                        Text(b.nombre).font(.system(size: 13))
                        Spacer()
                        Button { withAnimation(muelle) { m.datos.bloqueos.removeAll { $0 == b } } } label: {
                            Image(systemName: "minus").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ter).frame(width: 28, height: 28)
                                .background(Circle().fill(Color.white.opacity(0.06)))
                        }.buttonStyle(Hunde()).accessibilityLabel(String(localized: "Quitar \(b.nombre)"))
                    }.padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 44)
                }
                HStack(spacing: 8) {
                    TextField(String(localized: "Añadir web (instagram.com)"), text: $web).textFieldStyle(.plain).foregroundStyle(Color.luz).onSubmit(anadirWeb)
                    Button(String(localized: "Añadir app…"), action: anadirApp).buttonStyle(.plain).foregroundStyle(Color.luz).font(.system(size: 12.5, weight: .medium))
                }.padding(.horizontal, 14).padding(.vertical, 11).frame(minHeight: 44)
            }
            grupo(String(localized: "Lumen"))
            Filas {
                Fila(titulo: String(localized: "Vive en el escritorio"), sub: String(localized: "Sale al plegar el panel")) { Interruptor(on: $m.datos.ajustes.espirituEscritorio) }
                Fila(titulo: String(localized: "Sigue la hora del día"), sub: String(localized: "Se despereza y duerme contigo")) { Interruptor(on: $m.datos.ajustes.seguirHora) }
            }
            grupo(String(localized: "Sonido"))
            Filas {
                Fila(titulo: String(localized: "Sonidos")) { Interruptor(on: Binding(get: { m.ajustes.sonido ?? true }, set: { m.datos.ajustes.sonido = $0 })) }
                Fila(titulo: String(localized: "Volumen")) {
                    Slider(value: Binding(get: { m.ajustes.volumen ?? 0.6 }, set: { m.datos.ajustes.volumen = $0 }), in: 0.1...1) { suelta in
                        if !suelta { Sonido.tocar(.gota) }
                    }.tint(Color.luzOn).frame(width: 140).disabled(!(m.ajustes.sonido ?? true))
                }
                Fila(titulo: String(localized: "Silencio durante el foco"), sub: String(localized: "Solo suenan el inicio y el fin")) {
                    Interruptor(on: Binding(get: { m.ajustes.silencioFoco ?? false }, set: { m.datos.ajustes.silencioFoco = $0 }))
                }
            }
            grupo(String(localized: "Módulos"))
            Filas {
                ForEach(Modulo.allCases.filter { $0 != .vscode }, id: \.self) { mod in
                    Fila(titulo: mod.nombre, sub: mod.sub) { Interruptor(on: Binding(get: { m.activo(mod) }, set: { m.activar(mod, $0) })) }
                }
            }
            if m.activo(.captura) || m.activo(.respirar) || m.activo(.scriptorium) {
                Filas {
                    if m.activo(.scriptorium) {
                        Fila(titulo: String(localized: "Nombre del archivo en la tarjeta"), sub: String(localized: "Qué lee o escribe cada mesa")) { Interruptor(on: opcional(\.archivoEnTarjeta, false)) }
                        Fila(titulo: String(localized: "Sonido del Scriptorium"), sub: String(localized: "Un roce de pluma muy bajo al empezar a escribir")) { Interruptor(on: opcional(\.sonidoScriptorium, false)) }
                    }
                    if m.activo(.captura) {
                        Fila(titulo: String(localized: "Atajo de la nota rápida"), sub: String(localized: "Desde cualquier app")) {
                            GrabadorAtajo(actual: (m.ajustes.atajoNota ?? .deSerie).texto, poner: m.ponerAtajo)
                        }
                        Fila(titulo: String(localized: "Nota rápida guarda en")) {
                            Segmento(opciones: [("boveda", String(localized: "Bóveda")), ("carpeta", String(localized: "Carpeta")), ("notas", String(localized: "Notas"))],
                                     valor: Binding(get: { m.ajustes.capturaDestino ?? "boveda" }, set: { m.ajustes.capturaDestino = $0 }), mini: true)
                        }
                        if m.ajustes.capturaDestino == "carpeta" {
                            Fila(titulo: String(localized: "Carpeta de notas rápidas"), sub: m.ajustes.capturaCarpeta.map { URL(fileURLWithPath: $0).lastPathComponent } ?? String(localized: "Sin elegir")) {
                                Button("Elegir…", action: elegirCarpetaCaptura).buttonStyle(.plain).foregroundStyle(Color.luz).font(.system(size: 12.5))
                            }
                        }
                    }
                    if m.activo(.respirar) {
                        Fila(titulo: String(localized: "Respirar antes de empezar"), sub: String(localized: "Tres respiraciones al pulsar Concentrarse")) { Interruptor(on: opcional(\.respirarAntes, true)) }
                    }
                }
            }
            grupo(String(localized: "El Hueco"))
            Filas {
                Fila(titulo: String(localized: "Mostrar el Hueco"), sub: String(localized: "Conversaciones de Claude, uso del plan y Nido")) { Interruptor(on: opcional(\.hueco, true)) }
                Fila(titulo: String(localized: "Hilo de Aliento"), sub: String(localized: "En reposo, lo que queda del bloque de 5 h")) { Interruptor(on: opcional(\.hiloAliento, true)) }
                Fila(titulo: String(localized: "Preguntar el uso a Claude"), sub: String(localized: "Si el uso del plan no llega solo, una pregunta mínima a Haiku cada 15 min (gasta un poco del plan)")) { Interruptor(on: opcional(\.consultarUso, false)) }
                Fila(titulo: String(localized: "Esconder en pantalla completa")) { Interruptor(on: opcional(\.esconderCompleta, true)) }
            }
        }
    }

    // Los ajustes nuevos son opcionales en el archivo: nil vale lo de serie.
    private func opcional(_ k: WritableKeyPath<Ajustes, Bool?>, _ serie: Bool) -> Binding<Bool> {
        Binding(get: { m.ajustes[keyPath: k] ?? serie }, set: { m.datos.ajustes[keyPath: k] = $0 })
    }
    private func grupo(_ t: String) -> some View { Text(t).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sec).padding(EdgeInsets(top: 8, leading: 8, bottom: 0, trailing: 8)) }
    private func menu(_ b: Binding<Int>, _ valores: [Int], _ texto: @escaping (Int) -> String) -> some View {
        Menu { Picker("", selection: b) { ForEach(valores, id: \.self) { Text(texto($0)).tag($0) } }.pickerStyle(.inline).labelsHidden() }
            label: { Text("\(texto(b.wrappedValue)) ›").foregroundStyle(Color.sec) }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
    @ViewBuilder private func icono(_ b: Bloqueado) -> some View {
        if let id = b.app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 26, height: 26)
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hex: "#202024")).frame(width: 26, height: 26)
                .overlay(Text(String(b.nombre.prefix(1)).uppercased()).font(.system(size: 12, weight: .bold)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        }
    }
    private func anadirWeb() {
        var w = web.trimmingCharacters(in: .whitespaces).lowercased()
        if let h = URL(string: w.contains("://") ? w : "https://" + w)?.host { w = h }
        if w.hasPrefix("www.") { w.removeFirst(4) }
        guard w.contains("."), !m.datos.bloqueos.contains(where: { $0.web == w }) else { return }
        withAnimation(muelle) { m.datos.bloqueos.append(Bloqueado(nombre: w, web: w)) }
        web = ""
    }
    private func anadirApp() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications"); p.allowedContentTypes = [.application]; p.allowsMultipleSelection = true
        NSApp.activate()
        guard p.runModal() == .OK else { return }
        for url in p.urls {
            guard let b = Bundle(url: url), let id = b.bundleIdentifier, !m.datos.bloqueos.contains(where: { $0.app == id }) else { continue }
            m.datos.bloqueos.append(Bloqueado(nombre: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), app: id))
        }
    }
    private func elegirCarpetaCaptura() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        if p.runModal() == .OK, let u = p.url { m.ajustes.capturaCarpeta = u.path }
    }
}
