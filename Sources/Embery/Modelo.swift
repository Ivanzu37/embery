import AppKit
import Observation
import ServiceManagement

// Estado de toda la app: datos guardados, la sesión de foco en curso y el estado de Lumen que sale de ellos.

struct Foco {
    var id = UUID()             // el de su Sesion: el apunte en curso y la sesión final son la misma
    var modo: Modo
    var inicio = Date()
    var segundos = 0.0          // de foco real, sin pausas ni descansos
    var ronda = 1
    var rondas: Int
    var duracion: Double        // segundos por ronda; en cronómetro no se usa
    var descanso: Double
    var enDescanso = 0.0        // segundos que quedan de descanso entre rondas
    var pausada = false
    var pausas = 0
    var bloqueos = 0
    var app: NSRunningApplication?
    var appNombre: String?
    var tarea: String
    var proyecto: ProyectoFoco?
    var segundosRonda: Double { segundos - Double(ronda - 1) * duracion }
}

struct ProyectoFoco: Equatable { var nombre: String; var carpeta: URL? }

@Observable
final class Embery {
    var datos = Almacen.cargar() { didSet { Almacen.guardar(datos) } }
    var foco: Foco?
    var respiracion: Respiracion?   // la del Hueco (Calma)
    var previa: Respiracion?        // las tres antes de un foco
    var dormidoPausa = false        // Pausa de verdad: volviste al Mac antes de que acabara el descanso
    var paisajeSonando: String?
    @ObservationIgnored let paisajes = Paisajes()
    @ObservationIgnored let siguiente = Siguiente()
    @ObservationIgnored let canto = Canto()
    @ObservationIgnored var paisajePorFoco = false
    var finHasta = Date.distantPast
    var plegado = true
    var aviso: String?
    var avisoMin: Int?              // minutos que quedan de bloqueo, en la píldora (solo temporizador)
    var esperando = 0               // conversaciones de Claude que piden permiso durante el foco
    var bovedaDesconectada = false
    var modo: Modo = .temporizador
    var appElegida: NSRunningApplication?
    var proyecto: ProyectoFoco?     // el que se pondrá a la próxima sesión
    var proyectoAMano = false       // elegido en el menú: no lo pisa la detección hasta la próxima sesión
    var pasoBienvenida = 1
    var bienvenida: Bool { ajustes.bienvenidaVista != true }
    var cierre: Sesion?             // la que acaba de terminar, mientras se pregunta qué has hecho
    var sinCommit: (archivos: Int, carpeta: URL)?   // cambios sin commit en su proyecto
    var ahora = Date()
    @ObservationIgnored var alCambiarEstado: (Estado, Estado) -> Void = { _, _ in }
    @ObservationIgnored var alBloquear: () -> Void = {}
    @ObservationIgnored var alTerminar: (Bool) -> Void = { _ in }
    @ObservationIgnored var alEmpezar: () -> Void = {}
    @ObservationIgnored let bloqueo = Bloqueo()
    @ObservationIgnored private var ultimoTic = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var faseAntes = -1
    @ObservationIgnored private var ultimoApunte = 0.0
    @ObservationIgnored private var retomable: Sesion?
    // Lo pone la app: vuelve a registrar el atajo de la nota y dice si macOS lo aceptó.
    @ObservationIgnored var alCambiarAtajo: () -> Bool = { true }

    // Si otra app ya tiene el atajo, se queda el de antes.
    func ponerAtajo(_ a: AtajoTeclas) -> Bool {
        let antes = ajustes.atajoNota
        ajustes.atajoNota = a == .deSerie ? nil : a
        if alCambiarAtajo() { return true }
        ajustes.atajoNota = antes; _ = alCambiarAtajo()
        return false
    }
    @ObservationIgnored private var descansoDesde: Double?
    @ObservationIgnored private var estadoAntes: Estado = .reposo
    @ObservationIgnored private var avisoHasta = Date.distantPast
    @ObservationIgnored private var enCurso: Set<UUID> = []
    @ObservationIgnored private let colaRegistro = DispatchQueue(label: "embery.registro")
    @ObservationIgnored private var ultimoProyecto = 0.0
    @ObservationIgnored private var ultimoBloqueo = (nombre: "", t: -1e9)
    @ObservationIgnored private var ultimaBoveda = -1e9
    @ObservationIgnored private var bloqueoAvisado = false

    private func avisarPuente() {
        bloqueoAvisado = bloqueando
        Puente.avisar(bloqueando: bloqueando, webs: datos.bloqueos.compactMap(\.web))
    }

    var ajustes: Ajustes { get { datos.ajustes } set { datos.ajustes = newValue } }
    var cuentas: Cuentas { Cuentas(datos: datos, hoy: ahora) }
    var reducir: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init() {
        bloqueo.activo = { [weak self] in self?.bloqueando ?? false }
        bloqueo.lista = { [weak self] in self?.datos.bloqueos ?? [] }
        bloqueo.alBloquear = { [weak self] b in self?.bloqueado(b) }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Puente.pregunta, object: nil, queue: .main) { [weak self] _ in self?.avisarPuente() }
        dnc.addObserver(forName: Puente.sumar, object: nil, queue: .main) { [weak self] n in
            if let s = Puente.sesion(n.userInfo) { self?.datos.sesiones.append(s); self?.registrarPendientes() }
        }
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tic() }.tolerance = 0.05
        // Un apunte reciente es una caída de hace nada: el foco se retoma (retomar()). Uno viejo se cierra como sesión.
        if let s = Almacen.enCurso() {
            if Self.reciente(s) { retomable = s } else { cerrarApunte(s) }
        }
        registrarPendientes()
        escribirCapturas()
        // Al volver el disco, se escribe lo que esperaba.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            self?.registrarPendientes(); self?.escribirCapturas(); self?.mirarBoveda()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            self?.mirarBoveda()
        }
    }

    var bloqueando: Bool { guard let f = foco else { return false }; return ajustes.bloquear && !f.pausada && f.enDescanso <= 0 }

    var estado: Estado {
        if ahora < finHasta || cierre != nil { return .fin }
        if let f = foco {
            if dormidoPausa && f.enDescanso > 0 { return .dormido }
            return f.pausada || f.enDescanso > 0 ? .descanso : .foco
        }
        // Recibiendo a alguien nuevo no se duerme, aunque sea de noche.
        if bienvenida { return .reposo }
        let h = Calendar.current.component(.hour, from: ahora)
        if ajustes.seguirHora && (h >= 23 || h < 7) { return .dormido }
        if cuentas.diasSinFoco >= 3 { return .triste }
        return .reposo
    }

    var humor: (String, String) {
        let e = etapaTexto
        if bienvenida && foco == nil {
            switch pasoBienvenida {
            case 1: return (String(localized: "Hola"), String(localized: "Soy Lumen"))
            case 2: return (String(localized: "Lumen vela"), e)
            default: return (String(localized: "Casi está"), String(localized: "Lo demás es opcional"))
            }
        }
        switch estado {
        case .reposo: return (String(localized: "Lumen vela"), e)
        case .foco: return (String(localized: "Atento contigo"), String(localized: "Su luz sube"))
        case .descanso: return foco?.enDescanso ?? 0 > 0 ? (String(localized: "Descansa los ojos"), String(localized: "Estírate tú también · \(reloj(foco!.enDescanso))")) : (String(localized: "Descansa los ojos"), String(localized: "Estírate tú también"))
        case .dormido: return (String(localized: "Duerme"), String(localized: "Mañana seguimos"))
        case .triste: return (String(localized: "Te busca"), String(localized: "\(cuentas.diasSinFoco) días sin foco"))
        case .fin: return (String(localized: "Bien hecho"), String(localized: "+\(ultimaGanancia) destellos"))
        }
    }
    var ultimaGanancia = 0
    var etapaTexto: String { let h = cuentas.horasLuz; return String(localized: "\(ETAPAS[etapaPorHoras(h)].nombre) · \(Int(h)) h de luz") }

    // Necesidades: la luz sigue a la sesión o a la luz de hoy; las compras de la tienda suben luz y sueño.
    var necesidades: (luz: Int, sueno: Int, animo: Int) {
        let c = cuentas, e = estado
        var luz: Double
        if let f = foco { luz = 45 + 55 * progreso(f) } else if e == .triste || e == .dormido { luz = 15 } else { luz = 20 + 80 * min(1, c.hoyMin / Double(ajustes.objetivoMin)) }
        if c.compradoHoy("luciernagas") { luz += 30 }
        var sueno = 60.0 + (c.compradoHoy("musgo") ? 40 : 0) + (c.tiene("nido") ? 15 : 0)
        if e == .dormido { sueno = min(sueno, 40) }
        let animo = e == .triste ? 25 : min(100, 70 + c.racha * 2)
        return (Int(min(100, luz)), Int(min(100, sueno)), animo)
    }

    func progreso(_ f: Foco) -> Double {
        switch f.modo {
        case .cronometro: return min(1, f.segundos / f.duracion)
        default: return min(1, f.segundos / (f.duracion * Double(f.rondas)))
        }
    }
    // Lo que muestra el reloj grande: lo que queda de la ronda o, en cronómetro y en App, lo que llevas.
    var relojTexto: String {
        guard let f = foco else { return "" }
        if f.enDescanso > 0 { return reloj(f.enDescanso) }
        return f.modo == .temporizador ? reloj(max(0, f.duracion - f.segundosRonda)) : reloj(f.segundos)
    }
    var relojSub: String {
        guard let f = foco else { return "" }
        let nombres = [f.tarea, f.proyecto?.nombre ?? ""].filter { !$0.isEmpty }
        let tarea = nombres.isEmpty ? String(localized: "Foco") : nombres.joined(separator: " · ")
        switch f.modo {
        case .temporizador: return f.enDescanso > 0 ? String(localized: "Descanso · luego ronda \(f.ronda + 1) de \(f.rondas)") : String(localized: "\(tarea) · ronda \(f.ronda) de \(f.rondas)")
        case .cronometro: return String(localized: "\(tarea) · cronómetro")
        case .app: return String(localized: "\(f.appNombre ?? "App") · solo mientras la usas")
        }
    }
    // El nombre que enseña el borde al empezar: la tarea o, sin ella, el proyecto.
    var nombreCorto: String {
        guard let f = foco else { return "" }
        let t = f.tarea.trimmingCharacters(in: .whitespaces), n = t.isEmpty ? f.proyecto?.nombre ?? "" : t
        return n.count > 24 ? String(n.prefix(23)) + "…" : n
    }
    // Lo que falta para que se acabe el bloqueo de esta ronda, en minutos hacia arriba.
    var minutosBloqueo: Int? {
        guard let f = foco, f.modo == .temporizador else { return nil }
        return max(1, Int((max(0, f.duracion - f.segundosRonda) / 60).rounded(.up)))
    }
    // Ajustes con bóveda que no está (disco fuera o carpeta borrada). Sin bóveda no cuenta como desconectada.
    func mirarBoveda() {
        guard ajustes.registrar else { if bovedaDesconectada { bovedaDesconectada = false }; return }
        let ruta = ajustes.boveda
        // Una ruta de red caída puede tardar segundos en responder: fuera del hilo principal.
        Task.detached(priority: .utility) {
            let d = !Boveda.disponible(ruta)
            await MainActor.run { if d != self.bovedaDesconectada { self.bovedaDesconectada = d } }
        }
    }
    // Minutos del cartel de la rama.
    var minutosCartel: Int {
        guard let f = foco else { return 0 }
        return min(99, Int((f.modo == .temporizador ? max(0, f.duracion - f.segundosRonda) : f.segundos) / 60))
    }
    func reloj(_ s: Double) -> String {
        let s = Int(s.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }

    // Saltar, «Ahora no» o «Concentrarse»: la bienvenida no vuelve a salir.
    func cerrarBienvenida(concentrar: Bool) {
        datos.ajustes.bienvenidaVista = true
        guard concentrar else { return }
        modo = .temporizador
        datos.ajustes.rondas = 1
        empezar()
    }

    // Con «respirar antes de empezar», primero tres respiraciones (se pueden saltar).
    func empezar() {
        guard foco == nil, previa == nil else { return }
        if modo == .app && appElegida == nil { return }
        if cierre != nil { cerrar(nota: nil) }
        if activo(.respirar) && (ajustes.respirarAntes ?? true) && !reducir {
            previa = Respiracion(clave: PREVIA.clave, inicio: ProcessInfo.processInfo.systemUptime)
            return
        }
        arrancar()
    }
    func saltarPrevia() { guard previa != nil else { return }; previa = nil; arrancar() }

    private func arrancar() {
        guard foco == nil else { return }
        if modo == .app && appElegida == nil { return }
        let a = ajustes
        foco = Foco(modo: modo, rondas: modo == .temporizador ? a.rondas : 1, duracion: Double(a.duracionMin * 60), descanso: Double(a.descansoMin * 60),
                    app: modo == .app ? appElegida : nil, appNombre: modo == .app ? appElegida?.localizedName : nil, tarea: a.tarea,
                    proyecto: etiquetar ? proyecto : nil)
        ultimoTic = ProcessInfo.processInfo.systemUptime
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        alEmpezar()
        bloqueo.revisarAhora()
        Sonido.tocar(.foco)
        // Con el foco, el paisaje elegido sube despacio (20 s) si no sonaba ya.
        if activo(.paisajes), ajustes.paisajeConFoco ?? true, paisajeSonando == nil, let p = ajustes.paisaje {
            paisajes.tocar(p, volumen: ajustes.paisajeVolumen ?? 0.5, subida: 20); paisajeSonando = p; paisajePorFoco = true
        }
    }
    func pausar() {
        guard foco != nil else { return }
        foco!.pausada.toggle()
        if foco!.pausada { foco!.pausas += 1 }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    func terminar() {
        guard let f = foco else { return }
        foco = nil; dormidoPausa = false; descansoDesde = nil
        let s = sesion(f)
        Almacen.guardarEnCurso(nil)
        ultimaGanancia = s.destellos
        proyectoAMano = false
        // Menos de un minuto no cuenta: ni destellos ni registro.
        if s.minutos >= 1 {
            datos.sesiones.append(s)
            // Con la pregunta, la sesión ya está guardada; se registra en la bóveda cuando se contesta u omite.
            if ajustes.preguntarAlTerminar ?? true { cierre = s; mirarCommit(f.proyecto?.carpeta) } else { registrarPendientes() }
        }
        finHasta = Date().addingTimeInterval(2.6)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        if s.minutos >= 1 { Sonido.tocar(.bienHecho) }
        if paisajePorFoco { paisajePorFoco = false; paisajes.apagar(bajada: 4); paisajeSonando = nil }
        alTerminar(s.minutos >= 1)
    }

    private func cerrarApunte(_ s: Sesion) {
        if s.minutos >= 1, !datos.sesiones.contains(where: { $0.id == s.id }) { datos.sesiones.append(s) }
        Almacen.guardarEnCurso(nil)
    }

    // Tras una caída, el foco sigue donde iba: mismo id, inicio y segundos. Lo que no se apunta (pausa, descanso) empieza de cero.
    func retomar() {
        guard let s = retomable, foco == nil else { return }
        retomable = nil
        let app = s.appID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        guard let f = Self.foco(retomando: s, ajustes, app: app) else { cerrarApunte(s); return }
        foco = f
        ultimoTic = ProcessInfo.processInfo.systemUptime
        alEmpezar()
        bloqueo.revisarAhora()
    }

    // Un apunte de hace menos de 2 min es una caída de hace nada: se retoma. Uno más viejo se cierra como sesión.
    static func reciente(_ s: Sesion, ahora: Date = Date()) -> Bool { ahora.timeIntervalSince(s.fin) < 120 }

    // nil: en modo app, la app de la sesión ya no está abierta y no hay nada que retomar.
    static func foco(retomando s: Sesion, _ a: Ajustes, app: NSRunningApplication?) -> Foco? {
        if s.modo == .app && app == nil { return nil }
        var f = Foco(modo: s.modo, rondas: s.modo == .temporizador ? a.rondas : 1, duracion: Double(a.duracionMin * 60), descanso: Double(a.descansoMin * 60),
                     app: app, appNombre: s.app, tarea: s.tarea, proyecto: s.proyecto.map { ProyectoFoco(nombre: $0, carpeta: nil) })
        f.id = s.id; f.inicio = s.inicio; f.segundos = s.segundos; f.pausas = s.pausas; f.bloqueos = s.bloqueos
        if f.modo == .temporizador { f.ronda = min(f.rondas, Int(f.segundos / f.duracion) + 1) }
        return f
    }

    private func sesion(_ f: Foco) -> Sesion {
        Sesion(id: f.id, inicio: f.inicio, fin: Date(), modo: f.modo, segundos: f.segundos, pausas: f.pausas, tarea: f.tarea,
               app: f.appNombre, appID: f.app?.bundleIdentifier, bloqueos: f.bloqueos, proyecto: f.proyecto?.nombre)
    }

    // En segundo plano: la primera escritura en el disco externo espera el permiso de macOS y no debe congelar la interfaz.
    // enCurso evita escribir dos veces la misma sesión si se vuelve a llamar antes de que acabe.
    func registrarPendientes() {
        let pendientes = datos.sesiones.filter { !$0.registrada && !enCurso.contains($0.id) && $0.id != cierre?.id }, a = ajustes
        guard !pendientes.isEmpty else { return }
        enCurso.formUnion(pendientes.map(\.id))
        colaRegistro.async {
            var hechas: Set<UUID> = []
            for s in pendientes { if Registro.escribir(s, a) { hechas.insert(s.id) } else { break } }
            DispatchQueue.main.async {
                self.enCurso.subtract(pendientes.map(\.id))
                for i in self.datos.sesiones.indices where hechas.contains(self.datos.sesiones[i].id) { self.datos.sesiones[i].registrada = true }
            }
        }
    }

    // Guardar con la línea, u Omitir (nil). Cambiar de pestaña o empezar otro foco también omite.
    func cerrar(nota: String?) {
        guard let c = cierre else { return }
        let t = nota?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !t.isEmpty, let i = datos.sesiones.firstIndex(where: { $0.id == c.id }) { datos.sesiones[i].nota = String(t.prefix(120)) }
        cierre = nil; sinCommit = nil
        registrarPendientes()
    }

    private func mirarCommit(_ carpeta: URL?) {
        sinCommit = nil
        guard let carpeta, ajustes.avisarCommit ?? true, !editores.isEmpty else { return }
        let id = cierre?.id
        DispatchQueue.global(qos: .utility).async {
            let n = GitEstado.cambios(en: carpeta)
            DispatchQueue.main.async { if self.cierre?.id == id, let n, n > 0 { self.sinCommit = (n, carpeta) } }
        }
    }

    // Integraciones › VS Code: los editores que se leen (VS Code de serie, Cursor si se pide), solo los instalados.
    var editores: [Editor] {
        guard ajustes.vscode ?? Editor.vscode.instalado else { return [] }
        return [Editor.vscode, ajustes.cursor == true ? .cursor : nil].compactMap { $0 }.filter(\.instalado)
    }
    var etiquetar: Bool { (ajustes.etiquetarProyecto ?? true) && !editores.isEmpty }

    // El proyecto abierto: el editor de delante o, si no, uno que esté abierto, y su carpeta tocada más reciente.
    func detectarProyecto() {
        guard etiquetar, !proyectoAMano, foco == nil else { return }
        let delante = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let abiertos = editores.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundle).isEmpty }
        guard let e = abiertos.first(where: { $0.bundle == delante }) ?? abiertos.first else { proyecto = nil; return }
        DispatchQueue.global(qos: .utility).async {
            let p = EditorRecientes.leer(e.workspaceStorage, cuantos: 1).first.map { ProyectoFoco(nombre: $0.nombre, carpeta: $0.carpeta) }
            DispatchQueue.main.async { if !self.proyectoAMano, self.proyecto != p { self.proyecto = p } }
        }
    }
    func elegirProyecto(_ p: ProyectoFoco?) { proyecto = p; proyectoAMano = true }

    func comprar(_ a: Articulo) {
        guard cuentas.saldo >= a.precio, !(a.mueble && cuentas.tiene(a.clave)), !(!a.mueble && cuentas.compradoHoy(a.clave)) else { return }
        datos.compras.append(Compra(articulo: a.clave, fecha: Date()))
        Sonido.tocar(.tienda)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    func abrirAlIniciar(_ si: Bool) {
        ajustes.abrirAlIniciar = si
        do { if si { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { NSLog("Embery: inicio de sesión: \(error)") }
    }

    private func bloqueado(_ b: Bloqueado) {
        foco?.bloqueos += 1
        // La misma app antes de 10 s no repite la píldora: basta el destello de la rama.
        let t = ProcessInfo.processInfo.systemUptime
        if b.nombre != ultimoBloqueo.nombre || t - ultimoBloqueo.t > 10 {
            aviso = String(localized: "\(b.nombre) espera a que termines"); avisoMin = minutosBloqueo
            avisoHasta = Date().addingTimeInterval(2.6)
        }
        ultimoBloqueo = (b.nombre, t)
        Sonido.tocar(.bloqueo)
        alBloquear()
    }

    // Avanza las respiraciones: un sonido por fase y, al acabar la previa, empieza el foco.
    private func respirar(_ t: Double) {
        guard let r = previa ?? respiracion else { faseAntes = -1; return }
        if let e = r.en(t) {
            if e.fase != faseAntes { if faseAntes >= 0 || e.fase > 0 { Sonido.tocar(.respira) }; faseAntes = e.fase }
        } else {
            faseAntes = -1
            if previa != nil { previa = nil; arrancar() } else { respiracion = nil }
        }
    }

    // Pausa de verdad: pasados 15 s de descanso, si vuelves al teclado o al ratón, Lumen se duerme hasta que acabe.
    private func pausaDeVerdad(_ t: Double) {
        guard activo(.pausa), !dormidoPausa, let d = descansoDesde, t - d > 15 else { return }
        if CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) < 2 { dormidoPausa = true }
    }

    private func tic() {
        let t = ProcessInfo.processInfo.systemUptime, dt = min(5, t - ultimoTic)
        ultimoTic = t
        if bloqueando != bloqueoAvisado { avisarPuente() }
        // Una vez por segundo basta para relojes y textos; cada cambio vuelve a calcular las vistas de SwiftUI.
        let n = Date(); if Int(n.timeIntervalSince1970) != Int(ahora.timeIntervalSince1970) { ahora = n }
        if aviso != nil && ahora > avisoHasta { aviso = nil }
        respirar(t)
        // Con el panel abierto, el proyecto de VS Code se vuelve a mirar cada 5 s.
        if !plegado, foco == nil, t - ultimoProyecto >= 5 { ultimoProyecto = t; detectarProyecto() }
        if t - ultimaBoveda >= 30 { ultimaBoveda = t; mirarBoveda() }
        if var f = foco, !f.pausada {
            if f.enDescanso > 0 {
                f.enDescanso -= dt
                if f.enDescanso <= 0 { f.enDescanso = 0; f.ronda += 1; dormidoPausa = false; descansoDesde = nil }
                pausaDeVerdad(t)
            } else if f.modo == .app {
                // Solo cuenta el uso real: la app delante y alguien tocando el teclado o el ratón en el último minuto.
                let delante = NSWorkspace.shared.frontmostApplication?.processIdentifier == f.app?.processIdentifier
                let activo = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) < 60
                if delante && activo { f.segundos += dt }
            } else {
                f.segundos += dt
            }
            foco = f
            if t - ultimoApunte >= 30 { ultimoApunte = t; Almacen.guardarEnCurso(sesion(f)) }
            if f.modo == .temporizador && f.enDescanso <= 0 && f.segundosRonda >= f.duracion {
                if f.ronda >= f.rondas { foco!.segundos = f.duracion * Double(f.rondas); terminar() }
                else {
                    foco!.enDescanso = f.descanso; descansoDesde = t
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    if activo(.pausa) { aviso = String(localized: "Levántate un rato · \(Int(f.descanso / 60)) min"); avisoMin = nil; avisoHasta = Date().addingTimeInterval(4) }
                }
            }
        }
        let e = estado
        if e != estadoAntes { alCambiarEstado(e, estadoAntes); estadoAntes = e }
    }
}
