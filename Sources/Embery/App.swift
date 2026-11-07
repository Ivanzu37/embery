import AppKit
import ServiceManagement
import SwiftUI

// Arranque y ventanas: el panel lateral, la rama del borde con su cajón, el aviso de bloqueo y la escena del escritorio,
// una ventana transparente a pantalla completa donde vive el espíritu y cae la gota. Port del pegamento de embery.html.

@main
enum Arranque {
    static let delegado = Delegado()
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--exportar-sonidos"), i + 1 < args.count { Sonido.exportar(args[i + 1]); return }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegado
        app.run()
    }
}

final class Flotante: NSPanel {
    var clave = false
    override var canBecomeKey: Bool { clave }
    init(nivel: NSWindow.Level, clave: Bool = false) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.clave = clave
        isOpaque = false; backgroundColor = .clear; hasShadow = false; level = nivel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isReleasedWhenClosed = false; hidesOnDeactivate = false
    }
}

// Coordenadas del escritorio: puntos desde la esquina de arriba a la izquierda de la pantalla elegida, como en el prototipo.
private var pantalla: NSRect { Pantallas.actual.frame }
private func aCocoa(_ r: CGRect) -> NSRect { NSRect(x: pantalla.minX + r.minX, y: pantalla.maxY - r.maxY, width: r.width, height: r.height) }
private func aEscritorio(_ p: NSPoint) -> Punto { Punto(x: p.x - pantalla.minX, y: pantalla.maxY - p.y) }
// CGWindowList da los marcos con y hacia abajo desde arriba de la pantalla principal, esté donde esté la elegida.
private func deVentanas(_ x: Double, _ y: Double) -> NSPoint { NSPoint(x: x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - y) }

private let ANCHO_PANEL = 360.0, ANCHO_CAJON = 188.0, R_POSADO = 15.0

final class Delegado: NSObject, NSApplicationDelegate {
    let m = Embery()
    let rama = Rama()
    let lado = Lateral()
    let espiritu = Espiritu()
    lazy var lumenFoco = Buho(zoom: 0.92, suelo: 0.73, etapa: etapaPorHoras(m.cuentas.horasLuz))
    lazy var lumenHogar = Buho(zoom: 0.85, suelo: SUELO_HOGAR / HH, etapa: etapaPorHoras(m.cuentas.horasLuz))

    private let panel = Flotante(nivel: .floating, clave: true)
    private let tira = Flotante(nivel: .statusBar)
    private let cajon = Flotante(nivel: .statusBar, clave: true)
    private let aviso = Flotante(nivel: .statusBar)
    private let escena = Flotante(nivel: .statusBar)
    private var estado: NSStatusItem!
    private lazy var vistaEscena = EscenaNSView(self)
    private lazy var vistaRama = RamaNSView(self)

    var caida: Caida?
    var hueco: Hueco?
    private var huecoVentana: HuecoVentana?
    private var atajo: Atajo?
    private var enPanel = Punto(x: 0, y: 0)
    private var ladoAntes = ""
    private var minAntes: Int?
    private var sobreTiraDesde: Double?, fueraDesde: Double?
    private var puntos: [String: Punto] = [:]
    private var lista: [Posadero] = []
    private var refresco = 0.0
    private var dtRama = 0.0, impar = false
    private var ratonTira = Punto(x: -1000, y: -1000)
    private var cajonDesde = 0.0
    private var trabajoHasta = -1e9
    private var estadoHueco: EstadoHueco = .reposo
    private var etiquetaPendiente = false
    private var miraTrasRecoger = false
    private var cerrando = false

    var izq: Bool { m.ajustes.lado == "izq" }
    var lateral: Bool { m.ajustes.borde == "lateral" }
    var ahora: Double { ProcessInfo.processInfo.systemUptime }

    func applicationDidFinishLaunching(_ n: Notification) {
        // shortcut: Raíces toma el disco de la bóveda al arrancar; si cambias la bóveda en Ajustes, cuenta tras reabrir Embery.
        // El Hueco siempre está (se esconde en Ajustes); la parte de Claude Code se apaga en Ajustes y cuenta tras reabrir.
        // El ajuste viene encendido de serie, pero el sistema no lo sabe hasta que se registra.
        if m.ajustes.abrirAlIniciar, Bundle.main.bundlePath.hasSuffix(".app"), SMAppService.mainApp.status != .enabled { m.abrirAlIniciar(true) }
        _ = Actualizar.shared   // arranca la búsqueda programada
        Pantallas.elegida = m.ajustes.pantalla
        let h = Hueco(boveda: m.ajustes.boveda, claude: (m.ajustes.claudeCode ?? true) && (m.ajustes.conversacionesHueco ?? true)); h.arrancar(); hueco = h; huecoVentana = HuecoVentana(h, m)
        h.verFoco = { [weak self] in self?.hueco?.abierto = false; self?.plegar(false) }
        m.alCambiarAtajo = { [weak self] in
            guard let self else { return false }
            let a = self.m.ajustes.atajoNota ?? .deSerie
            self.atajo = nil   // suelta el de antes: los dos usan el mismo id
            self.atajo = Atajo(tecla: a.tecla, modificadores: a.mods)
            return self.atajo != nil
        }
        if m.activo(.captura) { _ = m.alCambiarAtajo() }
        panel.contentView = Anfitrion(rootView: PanelVista(m: m, hueco: hueco, lumenFoco: lumenFoco, lumenHogar: lumenHogar, plegar: { [weak self] in self?.plegar(true) }))
        let anfitrion = Anfitrion(rootView: CajonVista(m: m, abrir: { [weak self] in self?.plegar(false) }))
        // El tamaño lo pone colocarCajon: sin esto la vista no deja que el cajón crezca desde el notch lateral.
        anfitrion.sizingOptions = [.intrinsicContentSize]
        cajon.contentView = anfitrion
        aviso.contentView = NSHostingView(rootView: AvisoVista(m: m))
        tira.contentView = vistaRama
        escena.contentView = vistaEscena
        escena.ignoresMouseEvents = true; aviso.ignoresMouseEvents = true
        escena.orderFrontRegardless(); aviso.orderFrontRegardless()

        estado = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        estado.button?.title = "✦"
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Abrir Embery"), action: #selector(abrir), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Buscar actualizaciones…"), action: #selector(buscarActualizaciones), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        estado.menu = menu

        espiritu.redimensionar(260, 260)
        espiritu.reducir = { [weak self] in self?.m.reducir ?? false }
        espiritu.posaderos = { [weak self] in self?.lista ?? [] }
        for l in lumenes { l.setEstado(m.estado) }

        m.alCambiarEstado = { [weak self] e, antes in
            guard let self else { return }
            for l in self.lumenes { l.setEstado(e) }
            if antes == .dormido { self.lumenFoco.evento("despertar"); self.lumenHogar.evento("despertar"); self.espiritu.evento("despertar") }
        }
        m.alBloquear = { [weak self] in
            guard let self else { return }
            // Mira hacia la app bloqueada, que queda al otro lado del panel.
            let lado = self.izq ? 1.0 : -1.0
            self.lumenFoco.evento("bloqueo", lado: lado); self.lumenHogar.evento("bloqueo", lado: lado); self.espiritu.evento("bloqueo")
            self.rama.avisoT = self.ahora
        }
        m.alEmpezar = { [weak self] in
            guard let self else { return }
            self.rama.focoT = self.ahora; self.rama.nombre = self.m.nombreCorto
            // Empezado desde el panel, la etiqueta espera a que se pliegue: si no, se abriría sin que nadie la vea.
            self.etiquetaPendiente = !self.rama.nombre.isEmpty
            if self.m.plegado { self.abrirEtiqueta() }
        }
        m.alTerminar = { [weak self] _ in
            guard let self else { return }
            self.etiquetaPendiente = false
            // Con el panel abierto no se ve la rama: el Hueco enciende el permiso sin que la luz suba.
            if self.m.esperando > 0 && self.m.plegado { self.rama.esperaSube = self.ahora; self.miraTrasRecoger = true }
            self.m.esperando = 0
            self.soltarGota()
        }
        m.mirarBoveda()
        // Con «silencio durante el foco» solo suenan el inicio y el fin.
        Sonido.ajuste = { [weak self] e in
            guard let a = self?.m.ajustes, a.sonido ?? true else { return nil }
            if a.silencioFoco ?? false, self?.m.foco != nil, e != .foco, e != .bienHecho { return nil }
            if e == .pluma, !(a.sonidoScriptorium ?? false) { return nil }
            return Float(a.volumen ?? 0.6)
        }

        cambiarPantalla()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.cambiarPantalla() }
        // Arranca plegado: la luz sale de la rama.
        m.plegado = true
        tira.orderFrontRegardless()
        if m.ajustes.espirituEscritorio { espiritu.salir(puntoTira()) }
        m.retomar()
        // Instalación nueva: el panel se abre solo con la bienvenida.
        if m.bienvenida { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.plegar(false) } }
        // El vigilante que la reabre si cae con un foco en marcha. Solo la primera vez: si lo apagas en Ítems de inicio, se queda apagado.
        let guardia = SMAppService.agent(plistName: "com.ivanzu.embery.guardia.plist")
        if Bundle.main.bundlePath.hasSuffix(".app"), guardia.status == .notRegistered {
            do { try guardia.register() } catch { NSLog("Embery: vigilante: \(error)") }
        }
    }

    var lumenes: [Mascota] { [lumenFoco, lumenHogar, espiritu] }

    @objc func abrir() { plegar(false) }
    @objc func buscarActualizaciones() { Actualizar.shared.buscar() }

    // Apagar o salir con un foco en marcha: se cierra como sesión terminada para que no se pierda.
    func applicationWillTerminate(_ n: Notification) { m.terminar() }

    // MARK: Ventanas

    // Todo Embery va a la pantalla elegida: escena, aviso, panel, pestaña del borde, cajón y Hueco.
    private func cambiarPantalla() {
        Pantallas.elegida = m.ajustes.pantalla
        escena.setFrame(pantalla, display: false); vistaEscena.arrancar()
        colocarAviso()
        // La escena cambia de tamaño: el espíritu no puede quedarse fuera de ella.
        espiritu.x = min(max(espiritu.x, 40), pantalla.width - 40); espiritu.y = min(max(espiritu.y, 40), pantalla.height - 40)
        caida = nil
        colocar()
        huecoVentana?.colocar()
    }

    private func colocar() {
        ladoAntes = m.ajustes.lado
        let vis = Pantallas.actual.visibleFrame
        panel.setFrame(NSRect(x: izq ? vis.minX + 10 : vis.maxX - 10 - ANCHO_PANEL, y: vis.minY + 10, width: ANCHO_PANEL, height: vis.height - 20), display: true)
        tira.setFrame(aCocoa(marcoTira), display: true)
        colocarCajon()
    }
    // La píldora va centrada en el hueco libre (sin el panel abierto) y bajo la barra de menús. La ventana empieza 10 pt
    // más arriba para que la entrada desde y − 10 no se corte.
    private func colocarAviso() {
        let barra = max(pantalla.maxY - Pantallas.actual.visibleFrame.maxY, Pantallas.actual.safeAreaInsets.top)
        let libre = m.plegado ? 0 : ANCHO_PANEL + 10
        let cx = (izq ? libre + pantalla.width : pantalla.width - libre) / 2
        aviso.setFrame(aCocoa(CGRect(x: cx - 260, y: barra + 2, width: 520, height: 70)), display: false)
        espiritu.avisoEn = Punto(x: cx, y: barra + 31)
    }
    private func abrirEtiqueta() {
        guard etiquetaPendiente, m.foco != nil else { return }
        etiquetaPendiente = false; rama.etiquetaT = ahora
    }
    // La tira mide ANCHO y crece hacia el escritorio; el borde de la pantalla queda donde siempre.
    private var marcoTira: CGRect { CGRect(x: izq ? 0 : pantalla.width - ANCHO, y: (pantalla.height * 0.3).rounded(), width: ANCHO, height: TH) }
    private func colocarCajon() {
        guard let h = cajon.contentView?.fittingSize else { return }
        // Con el notch lateral el cajón sale pegado al borde y centrado en él; con la rama, a su lado.
        let x = lateral ? (izq ? 0 : pantalla.width - ANCHO_CAJON) : izq ? 46 : pantalla.width - 46 - ANCHO_CAJON
        let y = lateral ? marcoTira.minY + TH / 2 - h.height / 2 : marcoTira.minY + 8
        cajon.setFrame(aCocoa(CGRect(x: x, y: y, width: ANCHO_CAJON, height: h.height)), display: true)
    }
    // El negro del notch lateral crece y se convierte en el cajón.
    private func abrirCajon() {
        colocarCajon()
        cajonDesde = ahora; cerrando = false
        guard lateral, !m.reducir else { cajon.alphaValue = 1; cajon.orderFrontRegardless(); return }
        let fin = cajon.frame, t = marcoTira
        cajon.setFrame(aCocoa(CGRect(x: izq ? 0 : pantalla.width - LW, y: t.minY + LY0, width: LW, height: LH)), display: false)
        cajon.alphaValue = 0.6
        cajon.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.35; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1)
            cajon.animator().setFrame(fin, display: true); cajon.animator().alphaValue = 1
        }
    }
    // Al revés que al abrir: el cajón vuelve a encogerse en el notch; con la rama, se desvanece.
    private func cerrarCajon() {
        guard !m.reducir else { cajon.orderOut(nil); return }
        cerrando = true
        let t = marcoTira
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = lateral ? 0.28 : 0.2; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.7, 0.2)
            if lateral { cajon.animator().setFrame(aCocoa(CGRect(x: izq ? 0 : pantalla.width - LW, y: t.minY + LY0, width: LW, height: LH)), display: true) }
            cajon.animator().alphaValue = lateral ? 0.5 : 0
        }, completionHandler: { [weak self] in
            guard let self, self.cerrando else { return }
            self.cerrando = false; self.cajon.orderOut(nil)
        })
    }
    private func puntoTira() -> Punto { Punto(x: izq ? TW + 4 : pantalla.width - TW - 4, y: marcoTira.minY + 140) }

    // Plegar y desplegar: el búho se vuelve luz y sale al escritorio; al volver, la luz entra donde aparece el búho.
    func plegar(_ v: Bool) {
        guard v != m.plegado else { return }
        cerrando = false; cajon.orderOut(nil)
        let p = aEscritorio(NSPoint(x: panel.frame.midX, y: panel.frame.maxY))
        enPanel = Punto(x: p.x, y: p.y + 56 + 262 * 0.55)
        m.plegado = v
        colocarAviso()
        if v { abrirEtiqueta() }
        let dur = m.reducir ? 0 : 0.25
        if v {
            if m.ajustes.espirituEscritorio { espiritu.salir(enPanel) }
            NSAnimationContext.runAnimationGroup({ c in c.duration = dur; panel.animator().alphaValue = 0 }, completionHandler: { [weak self] in
                guard let self, self.m.plegado else { return }
                self.panel.orderOut(nil); self.tira.orderFrontRegardless()
            })
        } else {
            espiritu.volver(enPanel)
            tira.orderOut(nil)
            panel.alphaValue = 0; panel.makeKeyAndOrderFront(nil)
            // Sin esto SwiftUI enfoca el campo Tarea y lo abre seleccionado.
            DispatchQueue.main.async { self.panel.makeFirstResponder(nil) }
            NSAnimationContext.runAnimationGroup { c in c.duration = dur; panel.animator().alphaValue = 1 }
        }
    }

    // Al terminar, la gota se suelta y cae despacio; el espíritu vuela a por ella y la absorbe.
    func soltarGota() {
        // Con el panel abierto la rama no se ve: la gota vuelve a ser rocío sin caer.
        guard m.plegado else { rama.radioGota = 0; return }
        // Sin movimiento, la gota no cae: se apaga y el espíritu da su pulso de luz.
        if m.reducir { rama.radioGota = 0; if espiritu.activo { espiritu.tocar() }; return }
        var g = rama.centroGota(espiritu.t, reducir: false), t = marcoTira
        // Del notch lateral la gota sale por debajo.
        if lateral { g.x = TW - LW + 13; g.y = LY0 + LH + 4 }
        caida = Caida(x: izq ? TW - g.x : pantalla.width - TW + g.x, y: t.minY + g.y, r: max(rama.radioGota, 4), vy: 0, t0: espiritu.t, vida: 1)
        // Vuela a ponerse un poco por debajo, para que la gota le caiga encima en vez de perseguirla.
        if espiritu.activo {
            espiritu.volar(Posadero(clave: "gota", libre: true) { [weak self] in
                guard let self, let c = self.caida else { return Punto(x: self?.espiritu.x ?? 0, y: self?.espiritu.y ?? 0) }
                return Punto(x: c.x, y: min(pantalla.height - 20, c.y + 34))
            }, 1.2)
        }
    }

    // MARK: Posaderos

    // Barras de título de las ventanas que no usas (sin tapar), la barra de menús, la rama y el borde de abajo.
    // shortcut: lee los marcos con CGWindowList, sin la API de accesibilidad; basta mientras solo haga falta la barra de título.
    private func refrescarPosaderos() {
        let delante = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var encima: [CGRect] = [], nuevos: [String: Punto] = [:], claves: [(String, Double)] = []
        // La lista viene de delante hacia atrás: un punto vale si ninguna ventana anterior lo tapa.
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0, let d = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: d as CFDictionary) else { continue }
            let pid = w[kCGWindowOwnerPID as String] as? pid_t, id = w[kCGWindowNumber as String] as? Int ?? 0
            if pid != delante && pid != getpid() && r.width > 240 && r.height > 120 {
                for fx in [0.2, 0.5, 0.8] {
                    let x = r.minX + fx * r.width, borde = CGPoint(x: x, y: r.minY + 2)
                    // Solo la pantalla elegida (la escena no llega a las demás) y por debajo de su barra de menús.
                    let q = aEscritorio(deVentanas(x, r.minY - R_POSADO))
                    if !pantalla.contains(deVentanas(x, r.minY)) || q.y < 30 - R_POSADO { continue }
                    if encima.contains(where: { $0.insetBy(dx: -12, dy: -12).contains(borde) || $0.contains(CGPoint(x: x, y: r.minY - R_POSADO)) }) { continue }
                    let clave = "v\(id)-\(fx)"
                    nuevos[clave] = q; claves.append((clave, 1))
                }
            }
            encima.append(r)
        }
        if let b = estado.button?.window?.frame, pantalla.contains(NSPoint(x: b.midX, y: b.midY)) {
            nuevos["menu"] = Punto(x: b.minX - pantalla.minX - 18, y: 13); claves.append(("menu", 0.6))
        }
        if m.plegado && (!cajon.isVisible || cerrando) { nuevos["tira"] = puntoTira(); claves.append(("tira", 1)) }
        // Mientras Claude trabaja (y 90 s después, para no ir y volver entre turnos), el borde del Hueco es un posadero.
        if ahora < trabajoHasta, let r = huecoVentana?.marcoEscritorio {
            nuevos["hueco"] = Punto(x: r.maxX - 24, y: r.maxY + R_POSADO + 2); claves.append(("hueco", 0.8))
        }
        let suelo = pantalla.maxY - Pantallas.actual.visibleFrame.minY
        for fx in [0.12, 0.3, 0.48, 0.66] { let c = "abajo-\(fx)"; nuevos[c] = Punto(x: fx * pantalla.width, y: suelo - R_POSADO - 4); claves.append((c, 1)) }
        // Nunca dentro del panel abierto.
        let p = panel.isVisible ? CGRect(x: panel.frame.minX - pantalla.minX, y: pantalla.maxY - panel.frame.maxY, width: panel.frame.width, height: panel.frame.height).insetBy(dx: -12, dy: -12) : .null
        puntos = nuevos
        lista = claves.filter { !p.contains(CGPoint(x: nuevos[$0.0]!.x, y: nuevos[$0.0]!.y)) }.map { c in
            let q = nuevos[c.0]!
            return Posadero(clave: c.0, escala: c.1) { [weak self] in self?.puntos[c.0] ?? q }
        }
    }

    // MARK: Bucle

    func paso(_ dt: Double) {
        let t = ahora, raton = aEscritorio(NSEvent.mouseLocation)
        impar.toggle()
        if m.ajustes.lado != ladoAntes { colocar() }
        if m.ajustes.pantalla != Pantallas.elegida { cambiarPantalla() }
        refresco -= dt
        if refresco <= 0 {
            refresco = 0.5
            if let h = hueco { seguirHueco(h) }
            refrescarPosaderos()
            let et = etapaPorHoras(m.cuentas.horasLuz); lumenFoco.etapa = et; lumenHogar.etapa = et
            if m.plegado && m.ajustes.espirituEscritorio && !espiritu.activo { espiritu.salir(puntoTira()) }
            if !m.ajustes.espirituEscritorio && espiritu.activo && !espiritu.fundiendo { espiritu.volver(puntoTira()) }
        }

        // El Hueco va en este mismo reloj: la app tiene uno solo.
        hueco?.paso(dt, ahora: t); huecoVentana?.paso(t)

        espiritu.moverCursor(raton.x, raton.y, ahora: t)
        espiritu.actualizar(dt)
        if var c = caida {
            c.vy = min(70, c.vy + 160 * dt); c.y += c.vy * dt; c.x += sin((espiritu.t - c.t0) * 2.4) * 10 * dt
            if espiritu.activo && hypot(espiritu.x - c.x, espiritu.y - c.y) < 16 {
                // Con conversaciones esperando, echa un vistazo hacia la pestaña, de donde sale la luz de espera.
                espiritu.recoger(vistazo: miraTrasRecoger ? (izq ? -1 : 1) : nil); miraTrasRecoger = false; caida = nil; Sonido.tocar(.gota)
            }
            else {
                if !espiritu.activo || c.y > pantalla.height - 12 { c.vida -= dt / 0.5 }
                caida = c.vida <= 0 ? nil : c
            }
        }
        rama.cayendo = caida != nil
        // Solo se toca la ventana si cambia: cada asignación es una llamada al servidor de ventanas.
        let pasaEscena = !(vistaEscena.arrastre != nil || espiritu.bajoCursor(raton.x, raton.y))
        if escena.ignoresMouseEvents != pasaEscena { escena.ignoresMouseEvents = pasaEscena }
        // Posado solo respira: a 30 fps basta. Volando, arrastrado o con la gota cayendo, a 60.
        if impar || espiritu.vuelo != nil || espiritu.arrastrado || caida != nil { vistaEscena.repintar() }

        // Cada minuto cumplido, la punta de la savia da un pulso suave.
        if m.foco != nil {
            let mins = m.minutosCartel
            if mins != minAntes { if minAntes != nil { rama.pulsoT = t }; minAntes = mins; rama.cartel = String(format: "%02d", mins) }
        } else { minAntes = nil }

        guard m.plegado else { return }
        // La rama se mueve despacio: a 30 fps se ve igual y cuesta la mitad.
        dtRama += dt
        if impar { vistaRama.dt = dtRama; dtRama = 0; vistaRama.needsDisplay = true }
        // Solo el tronco (y el cartel en foco) recibe clics; el resto de la pestaña deja pasar el ratón.
        let tr = marcoTira, x = raton.x - tr.minX, y = raton.y - tr.minY
        let xb = izq ? x : ANCHO - x
        ratonTira = Punto(x: TW - xb, y: y)
        let sobreTira = lateral ? xb >= 0 && xb <= LW + 2 && y >= LY0 - 9 && y <= LY0 + LH + 9
            : (xb >= 0 && xb <= 16 && y >= 10 && y <= TH - 10) || (m.foco != nil && xb >= 6 && xb <= 34 && y >= 24 && y <= 52)
        if tira.ignoresMouseEvents == sobreTira { tira.ignoresMouseEvents = !sobreTira }
        // El cajón se abre con intención (350 ms encima de la rama) y se cierra 300 ms después de salir de los dos.
        let sobreCajon = cajon.isVisible && !cerrando && cajon.frame.contains(NSEvent.mouseLocation)
        if sobreTira { sobreTiraDesde = sobreTiraDesde ?? t } else { sobreTiraDesde = nil }
        if let d = sobreTiraDesde, t - d > 0.35, !cajon.isVisible || cerrando { abrirCajon() }
        if sobreTira || sobreCajon { fueraDesde = nil } else { fueraDesde = fueraDesde ?? t }
        if let f = fueraDesde, t - f > 0.3, cajon.isVisible, !cerrando { cerrarCajon() }
        if cajon.isVisible, !cerrando, t - cajonDesde > 0.4, let h = cajon.contentView?.fittingSize.height, abs(h - cajon.frame.height) > 0.5 { colocarCajon() }
    }

    // Copia los ajustes al Hueco y, cuando Claude se pone a trabajar, el espíritu vuela a posarse en él.
    private func seguirHueco(_ h: Hueco) {
        let a = m.ajustes
        if h.visible != (a.hueco ?? true) { h.visible = a.hueco ?? true }
        if h.hilo != (a.hiloAliento ?? true) { h.hilo = a.hiloAliento ?? true }
        if h.consultarUso != (a.consultarUso ?? false) { h.consultarUso = a.consultarUso ?? false }
        if h.esconderCompleta != (a.esconderCompleta ?? true) { h.esconderCompleta = a.esconderCompleta ?? true }
        if h.scriptorium != (a.scriptoriumAbierto ?? false) { h.scriptorium = a.scriptoriumAbierto ?? false }
        // Con el foco en marcha (sin pausa) Claude calla; al terminar, lo acumulado sale como «Te esperan».
        let callar = m.foco.map { !$0.pausada } ?? false
        h.seguirFoco(enMarcha: m.foco != nil, callar: callar,
                     avance: m.foco.flatMap { $0.modo == .temporizador && $0.duracion > 0 ? $0.segundosRonda / $0.duracion : nil })
        h.callarPermisos = callar && !(a.permisoEnFoco ?? false)
        let esperan = m.foco == nil ? 0 : h.live.sessions.values.filter { $0.state == .perm }.count
        if esperan != m.esperando { m.esperando = esperan }
        if h.terminal != a.terminalClaude { h.terminal = a.terminalClaude }
        huecoVentana?.revisarAjustes()
        if h.estado == .trabajo || h.estado == .permiso { trabajoHasta = ahora + 90 }
        let empieza = h.estado == .trabajo && estadoHueco != .trabajo
        estadoHueco = h.estado
        if empieza, h.visible, espiritu.activo, !espiritu.arrastrado, espiritu.posado?.clave != "hueco", !m.reducir,
           let r = huecoVentana?.marcoEscritorio {
            let q = Punto(x: r.maxX - 24, y: r.maxY + R_POSADO + 2)
            espiritu.volar(Posadero(clave: "hueco", escala: 0.8) { [weak self] in self?.puntos["hueco"] ?? q })
        }
    }

    func dibujarRama(_ l: Lienzo, _ dt: Double) {
        if !izq { l.translate(ANCHO - TW, 0) }
        let c = m.cuentas, pausa = m.foco?.pausada ?? false, dormido = m.estado == .dormido
        let esperando = m.esperando > 0, sinBoveda = m.bovedaDesconectada
        // Respira con la misma onda que el espíritu; en pausa, más despacio.
        let resp = (sin(espiritu.t * PI2 / (pausa ? 7 : 4.2) + espiritu.semilla) + 1) / 2
        let v = m.foco.map { m.progreso($0) } ?? min(1, c.hoyMin / Double(m.ajustes.objetivoMin))
        if lateral {
            lado.dibujar(l, dt: dt, t: ahora, foco: m.foco != nil, pausa: pausa, dormido: dormido,
                         hoy: c.hoyMin / Double(m.ajustes.objetivoMin), ses: m.foco.map { m.progreso($0) } ?? 0, minutos: rama.cartel,
                         racha: c.racha, aviso: ahora - rama.avisoT, pulso: ahora - rama.pulsoT, nombre: rama.nombre,
                         etiqueta: ahora - rama.etiquetaT, desdeFoco: ahora - rama.focoT, esperando: esperando,
                         sube: ahora - rama.esperaSube, sinBoveda: sinBoveda, izq: izq, reducir: m.reducir)
            return
        }
        rama.dibujar(l, t: espiritu.t, dt: dt, ahora: ahora, foco: m.foco != nil, pausa: pausa, dormido: dormido, v: v, resp: resp,
                     hoyLleno: c.hoyMin >= Double(m.ajustes.objetivoMin), racha: c.racha > 0, esperando: esperando,
                     sinBoveda: sinBoveda, izq: izq, reducir: m.reducir)
    }
}

// MARK: Vistas de dibujo

// Sin esto, la primera pulsación sobre una ventana que no está activa solo la activa: «Terminar» había que mantenerlo dos veces.
final class Anfitrion<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class RamaNSView: NSView {
    unowned let d: Delegado
    var dt = 1.0 / 60
    init(_ d: Delegado) {
        self.d = d; super.init(frame: .zero)
        setAccessibilityRole(.button); setAccessibilityLabel(String(localized: "Abrir Embery"))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ r: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        d.dibujarRama(Lienzo(c), dt)
    }
    override func mouseDown(with e: NSEvent) { d.plegar(false) }
    override func accessibilityPerformPress() -> Bool { d.plegar(false); return true }
}

final class EscenaNSView: NSView {
    unowned let d: Delegado
    var arrastre: (dx: Double, dy: Double, x0: Double, y0: Double, movio: Bool)?
    private var link: CADisplayLink?
    private var antes: CFTimeInterval = 0

    init(_ d: Delegado) { self.d = d; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // El ritmo va atado a la pantalla: la ventana nace sin tamaño y un enlace atado a ella no llegaría a latir.
    func arrancar() {
        link?.invalidate()
        link = Pantallas.actual.displayLink(target: self, selector: #selector(tic))
        // En pantallas ProMotion latiría a 120 Hz: el doble de dibujo por CPU sin que se note en una luz que flota.
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link?.add(to: .main, forMode: .common)
    }
    @objc private func tic(_ l: CADisplayLink) {
        let dt = antes == 0 ? 1.0 / 60 : min(0.05, l.timestamp - antes); antes = l.timestamp
        d.paso(dt)
    }

    // La ventana ocupa toda la pantalla, pero se dibuja en una vista pequeña que sigue al espíritu, su estela y la gota:
    // una capa del tamaño de la pantalla se preparaba entera cada fotograma (~35 % de CPU).
    private lazy var trozo: TrozoNSView = { let v = TrozoNSView(d); addSubview(v); return v }()
    func repintar() {
        let e = d.espiritu
        var r = NSRect.null
        if e.activo {
            r = NSRect(x: e.x - 130, y: e.y - 130, width: 260, height: 260)
            for q in e.rastro { r = r.union(NSRect(x: q.x - 24, y: q.y - 24, width: 48, height: 48)) }
            for q in e.motas { r = r.union(NSRect(x: q.x - 8, y: q.y - 8, width: 16, height: 16)) }
        }
        if let c = d.caida { r = r.union(NSRect(x: c.x - 40, y: c.y - 40, width: 80, height: 80)) }
        trozo.isHidden = r.isNull
        guard !r.isNull else { return }
        // Tamaño redondeado a 64 para no rehacer la memoria de la capa cada vez que la estela crece un poco.
        let w = (r.width / 64).rounded(.up) * 64, h = (r.height / 64).rounded(.up) * 64
        trozo.frame = NSRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h).integral
        trozo.needsDisplay = true
    }

    // El espíritu se agarra desde el escritorio; un toque sin mover le da un pulso.
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil), s = d.espiritu
        guard s.bajoCursor(p.x, p.y) else { return }
        arrastre = (s.x - p.x, s.y - p.y, p.x, p.y, false)
    }
    override func mouseDragged(with e: NSEvent) {
        guard var a = arrastre else { return }
        let p = convert(e.locationInWindow, from: nil)
        if !a.movio && hypot(p.x - a.x0, p.y - a.y0) > 4 { a.movio = true; d.espiritu.agarrar(); NSCursor.closedHand.set(); Sonido.tocar(.lumen) }
        if a.movio { d.espiritu.x = p.x + a.dx; d.espiritu.y = p.y + a.dy }
        arrastre = a
    }
    override func mouseUp(with e: NSEvent) {
        guard let a = arrastre else { return }
        if a.movio { d.espiritu.soltar(); NSCursor.arrow.set() } else { d.espiritu.tocar(); Sonido.tocar(.lumen) }
        arrastre = nil
    }
}

final class TrozoNSView: NSView {
    unowned let d: Delegado
    init(_ d: Delegado) { self.d = d; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    // Los clics los resuelve la escena, que sabe dónde está el espíritu.
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override func draw(_ r: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.clear(bounds)
        c.translateBy(x: -frame.minX, y: -frame.minY)
        let l = Lienzo(c)
        d.espiritu.dibujarEstela(l)
        d.espiritu.dibujarEn(l)
        if let g = d.caida {
            l.alfa = g.vida; l.sumaLuz = true; luzEn(l, g.x, g.y, g.r * 3, 0.3)
            l.sumaLuz = false; formaGota(l, g.x, g.y, g.r, 0, 1); l.alfa = 1
        }
    }
}

// MARK: Cajón y aviso

struct CajonVista: View {
    @Bindable var m: Embery
    var abrir: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let f = m.foco {
                Text(m.relojSub).font(.system(size: 11)).foregroundStyle(Color.sec).lineLimit(1)
                Text(m.relojTexto).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().padding(.top, 2).padding(.bottom, 8)
                pista(m.progreso(f))
                if m.esperando > 0 {
                    linea(m.esperando == 1 ? String(localized: "1 conversación") : String(localized: "\(m.esperando) conversaciones"), String(localized: "Esperan a que termines")) { LuzEspera(reducir: m.reducir) }
                }
                if m.bovedaDesconectada { bovedaFuera }
                HStack(spacing: 6) {
                    Button(f.pausada ? "Seguir" : "Pausa") { m.pausar() }.buttonStyle(Secundario(alto: 34))
                    Mantener(alto: 34) { m.terminar() }
                }
            } else {
                let c = m.cuentas, obj = Double(m.ajustes.objetivoMin)
                Text("Luz de hoy").font(.system(size: 11)).foregroundStyle(Color.sec)
                Text("\(Int(c.hoyMin) / 60) h \(String(format: "%02d", Int(c.hoyMin) % 60)) \(Text("de \(Int(obj) % 60 == 0 ? "\(Int(obj) / 60) h" : duracion(obj))").font(.system(size: 13, weight: .medium)).foregroundColor(.sec))")
                    .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().padding(.top, 2).padding(.bottom, 8)
                pista(min(1, c.hoyMin / obj))
                Group {
                    if c.racha > 0 { HStack(spacing: 6) { Destello(color: .luzOn, tam: 10); Text(c.racha == 1 ? String(localized: "1 día de racha") : String(localized: "\(c.racha) días de racha")) } } else { Text(String(localized: "Sin racha todavía")) }
                    Text("Lumen \(m.etapaTexto.lowercased())")
                }.font(.system(size: 12)).foregroundStyle(Color.sec).padding(.bottom, 5)
                if m.bovedaDesconectada { bovedaFuera }
                if let r = m.previa { PreviaVista(m: m, r: r, alto: 36).padding(.top, 6) } else {
                    Button("Concentrarse") { m.empezar() }.buttonStyle(Principal(alto: 36)).padding(.top, 6)
                        .disabled(m.modo == .app && m.appElegida == nil)
                }
            }
        }
        .foregroundStyle(Color.texto)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            // Abrir entero: la misma flecha que pliega el panel, del revés.
            Button(action: abrir) {
                Image(systemName: m.ajustes.lado == "izq" ? "chevron.right" : "chevron.left").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ter).frame(width: 22, height: 22)
            }.buttonStyle(Hunde()).help(String(localized: "Abrir Embery")).accessibilityLabel(String(localized: "Abrir Embery"))
            .offset(x: 6, y: -5)
        }
        .padding(14).frame(width: ANCHO_CAJON, alignment: .leading)
        .background { fondo }
        .fixedSize(horizontal: false, vertical: true)
    }
    // Con el notch lateral, negro puro pegado al borde: es el mismo notch, más ancho.
    @ViewBuilder private var fondo: some View {
        if m.ajustes.borde == "lateral" {
            let r = 18.0, izq = m.ajustes.lado == "izq"
            UnevenRoundedRectangle(topLeadingRadius: izq ? 0 : r, bottomLeadingRadius: izq ? 0 : r, bottomTrailingRadius: izq ? r : 0,
                                   topTrailingRadius: izq ? r : 0, style: .continuous).fill(Color.black)
        } else {
            let forma = RoundedRectangle(cornerRadius: 18, style: .continuous)
            forma.fill(Color.black.opacity(0.9)).background(.ultraThinMaterial, in: forma).overlay(forma.strokeBorder(Color.white.opacity(0.08)))
        }
    }
    private func linea(_ texto: String, _ sub: String, @ViewBuilder icono: () -> some View) -> some View {
        HStack(spacing: 6) {
            icono()
            VStack(alignment: .leading, spacing: 0) {
                Text(texto).font(.system(size: 12)).foregroundStyle(Color.texto)
                Text(sub).font(.system(size: 11)).foregroundStyle(Color.sec)
            }
        }
        .padding(.bottom, 5).accessibilityElement(children: .combine)
    }
    private var bovedaFuera: some View {
        linea(String(localized: "Bóveda desconectada"), String(localized: "Se guarda en la app")) { Image(nsImage: RAIZ).resizable().frame(width: 11, height: 11) }
            .padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Color.linea).frame(height: 1) }
            .padding(.top, 3)
    }
    private func pista(_ v: Double) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(LinearGradient(colors: [Color(hex: "#8fb3ff"), .white], startPoint: .leading, endPoint: .trailing)).frame(width: g.size.width * v)
            }
        }.frame(height: 4).padding(.bottom, 10)
    }
}

// La única píldora de la app: bloqueos (y el aviso de descanso). Entra con muelle desde y − 10, se va hacia arriba.
struct AvisoVista: View {
    @Bindable var m: Embery
    var body: some View {
        let reducir = m.reducir
        VStack {
            if let t = m.aviso {
                HStack(spacing: 10) {
                    Circle().fill(RadialGradient(colors: [.white, .luzOn], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 14))
                        .frame(width: 22, height: 22).shadow(color: Color(hex: "#bcd3ff"), radius: 5)
                    Text("\(Text(t).font(.system(size: 13, weight: .medium)).foregroundColor(.texto))\(Text(m.avisoMin.map { " · \($0) min" } ?? "").font(.system(size: 13)).foregroundColor(.sec))")
                        .lineLimit(1)
                        .id(t).transition(.opacity.animation(.easeOut(duration: Dura.resalte)))
                }
                .padding(.leading, 8).padding(.trailing, 16).padding(.vertical, 8)
                .frame(height: 38)
                .background(Capsule().fill(Color.black.opacity(0.85)).background(.ultraThinMaterial, in: Capsule()))
                .overlay(Capsule().strokeBorder(Color.linea))
                .accessibilityElement(children: .combine)
                .transition(reducir ? .opacity.animation(.easeOut(duration: Dura.resalte))
                            : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: -10)).animation(muelleForma),
                                          removal: .opacity.combined(with: .offset(y: -6)).animation(salida(0.4))))
            }
        }
        .padding(.top, 10)
        .frame(width: 520, height: 70, alignment: .top)
        // Cada transición lleva su curva; esta solo hace que el cambio cuente como animado.
        .animation(.easeOut(duration: Dura.resalte), value: m.aviso)
    }
}

private let RAIZ = svg(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 11 11" fill="none" stroke="#8e8e93" stroke-width="1.1" stroke-linecap="round"><path d="M5.5 1v4.2M5.5 5.2c0 2-1.6 2.6-3.2 4M5.5 5.2c0 2 1.6 2.6 3.2 4M5.5 5.2c-1 1.6-1.2 3-.6 4.6"/></svg>"##)

// Las conversaciones que esperan: una luz que respira en 7 s (quieta al 0,8 con reducir movimiento).
private struct LuzEspera: View {
    var reducir: Bool
    @State private var lleno = false
    var body: some View {
        Circle().fill(RadialGradient(colors: [.white, .luzOn], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 6))
            .frame(width: 9, height: 9).shadow(color: Color(210, 228, 255).opacity(0.7), radius: 3)
            .padding(.horizontal, 1)
            .opacity(reducir ? 0.8 : lleno ? 1 : 0.55)
            .onAppear { if !reducir { withAnimation(.easeInOut(duration: Dura.respiraLenta / 2).repeatForever()) { lleno = true } } }
    }
}
