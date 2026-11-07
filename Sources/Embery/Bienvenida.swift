import SwiftUI

// La primera vez, en lugar de preparar un foco: dónde vive, el primer foco y lo opcional.
struct BienvenidaVista: View {
    @Bindable var m: Embery
    let lumen: Buho
    @State private var notas: String?
    @State private var claude = false
    @State private var falloClaude = false

    private var paso: Int { m.pasoBienvenida }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 5) {
                    ForEach(1...3, id: \.self) { n in
                        Capsule().fill(n == paso ? Color.luz : n < paso ? Color(hex: "#5a6478") : Color(hex: "#2e2e33"))
                            .frame(width: n == paso ? 18 : 6, height: 6)
                            .shadow(color: n == paso ? Color.luz.opacity(0.5) : .clear, radius: 4)
                    }
                }.animation(muelle.sinMovimiento(m.reducir), value: paso)
                    .accessibilityElement().accessibilityLabel(String(localized: "Paso \(paso) de 3"))
                Spacer()
                if paso < 3 {
                    Button("Saltar") { m.cerrarBienvenida(concentrar: false) }.buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sec)
                }
            }.frame(height: 20)

            Group {
                switch paso {
                case 1: dondeVive
                case 2: primerFoco
                default: loOpcional
                }
            }.transition(entra(m.reducir)).id(paso)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity, minHeight: 470, alignment: .top)
        .tarjeta()
    }

    private func ir(_ n: Int) {
        withAnimation(salida().sinMovimiento(m.reducir)) { m.pasoBienvenida = n }
        lumen.tocar()
    }

    private func titulo(_ t: String) -> some View {
        Text(t).font(.system(size: 19, weight: .semibold, design: .rounded)).tracking(-0.3).foregroundStyle(Color.texto)
    }

    // MARK: 1 · Dónde vive

    private var dondeVive: some View {
        let lateral = m.ajustes.borde == "lateral", notch = Pantallas.actual.safeAreaInsets.top > 0
        return VStack(alignment: .leading, spacing: 12) {
            titulo(String(localized: "Vivo en el borde de tu pantalla"))
            EsquemaPantalla(lateral: lateral, notch: notch, reducir: m.reducir)
            VStack(alignment: .leading, spacing: 8) {
                linea("chevron.right", lateral ? String(localized: "**El borde \(m.ajustes.lado == "izq" ? String(localized: "izquierdo") : String(localized: "derecho")).** Pasa el ratón por el notch lateral y se abre este panel.")
                                               : String(localized: "**El borde \(m.ajustes.lado == "izq" ? String(localized: "izquierdo") : String(localized: "derecho")).** Pasa el ratón por la rama de luz y se abre este panel."))
                if notch { linea("rectangle.topthird.inset.filled", String(localized: "**El notch es el Hueco.** Volumen, brillo, una nota rápida con \(m.ajustes.atajoNota?.texto ?? "⌃⌥N") y una bandeja para soltar archivos.")) }
                linea("sparkle", String(localized: "**La barra de menús.** Desde ✦ abres Embery y sus Ajustes."))
            }
            Spacer(minLength: 8)
            Button("Siguiente") { ir(2) }.buttonStyle(Principal())
        }
    }

    private func linea(_ icono: String, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icono).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.luz)
                .frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.05)))
            Text(resaltado(texto)).font(.system(size: 12.5)).foregroundStyle(Color.sec).fixedSize(horizontal: false, vertical: true)
        }
    }

    // Lo que va en **negrita** sale en el color del texto; el resto, en secundario.
    private func resaltado(_ md: String) -> AttributedString {
        var a = (try? AttributedString(markdown: md)) ?? AttributedString(md)
        for r in a.runs where r.inlinePresentationIntent?.contains(.stronglyEmphasized) == true { a[r.range].foregroundColor = Color.texto }
        return a
    }

    // MARK: 2 · Primer foco

    private var primerFoco: some View {
        VStack(alignment: .leading, spacing: 12) {
            titulo(String(localized: "Concéntrate y crezco"))
            Text("Cada minuto de foco me da luz. Con las horas cambio de etapa, y con los destellos amueblas mi rama.")
                .font(.system(size: 13)).foregroundStyle(Color.sec).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach([15, 25, 50], id: \.self) { d in
                    Button { withAnimation(muelle) { m.datos.ajustes.duracionMin = d } } label: { Chip(texto: String(localized: "\(d) min"), on: m.ajustes.duracionMin == d) }
                        .buttonStyle(Hunde())
                }
            }
            Text("Elige cuánto dura tu primer foco; empieza al final. Si quieres, durante el foco Embery bloquea las apps y webs que elijas. Lo configuras en Ajustes.")
                .font(.system(size: 11.5)).foregroundStyle(Color.ter).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Siguiente") { ir(3) }.buttonStyle(Principal())
        }
        .onAppear { if ![15, 25].contains(m.ajustes.duracionMin) { m.datos.ajustes.duracionMin = 25 } }
    }

    // MARK: 3 · Lo opcional

    private var loOpcional: some View {
        VStack(alignment: .leading, spacing: 12) {
            titulo(String(localized: "Si quieres, conecto más cosas"))
            Text("Nada de esto hace falta. Lo puedes cambiar luego en Ajustes.").font(.system(size: 13)).foregroundStyle(Color.sec)
            opcion(String(localized: "Carpeta de notas"), String(localized: "Markdown u Obsidian: casillas del día y registro de focos"),
                   hecho: notas, accion: String(localized: "Elegir…")) {
                m.elegirBoveda()
                if !m.ajustes.boveda.isEmpty { notas = URL(fileURLWithPath: m.ajustes.boveda).lastPathComponent; lumen.tocar() }
            }
            if JornadaTarjeta.detectado {
                opcion(String(localized: "Claude Code"), falloClaude ? String(localized: "No se pudo leer settings.json: no se ha tocado") : String(localized: "Conversaciones y permisos en el Hueco"),
                       hecho: claude ? String(localized: "Conectado") : nil, accion: String(localized: "Conectar…")) {
                    do { try m.conectarClaude(); claude = true; falloClaude = false; lumen.tocar() } catch { falloClaude = true }
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button(String(localized: "Concentrarse \(m.ajustes.duracionMin) min")) { m.cerrarBienvenida(concentrar: true) }.buttonStyle(Principal())
                Button("Ahora no") { m.cerrarBienvenida(concentrar: false) }.buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sec).padding(.horizontal, 10).frame(height: 46)
            }
            Text("Tus datos se quedan en este Mac.").font(.system(size: 11.5)).foregroundStyle(Color.ter).frame(maxWidth: .infinity)
        }
    }

    private func opcion(_ t: String, _ sub: String, hecho: String?, accion: String, _ hacer: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(t).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.texto)
                Text(sub).font(.system(size: 11.5)).foregroundStyle(Color.sec).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let hecho {
                HStack(spacing: 6) { PuntoEstado(bien: true); Text(hecho).lineLimit(1) }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.luz)
                    .transition(.opacity)
            } else {
                Button(action: hacer) {
                    Text(accion).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.luz)
                        .padding(.horizontal, 12).frame(height: 30).background(Capsule().fill(Color.luzTenue))
                }.buttonStyle(Hunde(escala: 0.95))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
        .animation(salida(0.25), value: hecho)
    }
}

// Una pantalla en miniatura: el cursor va al borde y se abre el panel; luego al notch, que es el Hueco.
private struct EsquemaPantalla: View {
    let lateral: Bool, notch: Bool, reducir: Bool
    @State private var fase = 0   // 0 cursor fuera · 1 en el borde · 2 panel abierto · 3 en el notch · 4 Hueco abierto

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let borde = fase == 2, hueco = fase == 4
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: "#101420"), Color(hex: "#0c0e14")], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color.white.opacity(0.04)).frame(height: 12)
                Image(systemName: "sparkle").font(.system(size: 7)).foregroundStyle(Color.luz).position(x: w - 12, y: 6)
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hex: "#16171c"))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.05)))
                    .frame(width: 140, height: 46).offset(x: 18, y: 40)
                if notch {
                    UnevenRoundedRectangle(bottomLeadingRadius: hueco ? 12 : 7, bottomTrailingRadius: hueco ? 12 : 7, style: .continuous).fill(.black)
                        .frame(width: hueco ? 110 : 58, height: hueco ? 26 : 12).position(x: w / 2, y: hueco ? 13 : 6)
                    Text("El Hueco").font(.system(size: 10)).foregroundStyle(Color.sec).position(x: w / 2, y: 34).opacity(hueco ? 1 : 0)
                }
                // El borde: notch lateral o rama de luz; abierto, un panel negro.
                if lateral || borde {
                    UnevenRoundedRectangle(topLeadingRadius: borde ? 10 : 7, bottomLeadingRadius: borde ? 10 : 7, style: .continuous).fill(.black)
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: borde ? 10 : 7, bottomLeadingRadius: borde ? 10 : 7, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
                        .frame(width: borde ? 64 : 6, height: borde ? 84 : 34).position(x: w - (borde ? 32 : 3), y: borde ? 62 : 61)
                } else {
                    Path { p in p.move(to: CGPoint(x: w, y: 62)); p.addQuadCurve(to: CGPoint(x: w - 19, y: 52), control: CGPoint(x: w - 9, y: 61)) }
                        .stroke(Color(hex: "#c9d8f2").opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    Circle().fill(Color.luz).frame(width: 4.4, height: 4.4).position(x: w - 18, y: 52)
                }
                Text("Pasa el ratón: se abre").font(.system(size: 10)).foregroundStyle(Color.sec).position(x: 70, y: h - 12).opacity(borde ? 1 : 0)
                if !reducir {
                    Image(systemName: "cursorarrow").font(.system(size: 12)).foregroundStyle(.white).shadow(color: .black, radius: 0.5)
                        .position(fase == 0 ? CGPoint(x: w - 66, y: 76) : fase <= 2 ? CGPoint(x: w - 22, y: 64) : CGPoint(x: w / 2, y: 10))
                }
            }
            .animation(reducir ? nil : .spring(response: 0.55, dampingFraction: 0.9), value: fase)
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.linea))
        .accessibilityHidden(true)
        .task(id: "\(lateral)\(notch)\(reducir)") {
            // Con reducir movimiento se queda quieto, con el panel abierto y su etiqueta.
            guard !reducir else { fase = 2; return }
            let pasos: [(Int, Double)] = notch ? [(0, 0.7), (1, 0.9), (2, 2.2), (3, 0.9), (4, 2.4)] : [(0, 0.7), (1, 0.9), (2, 2.4)]
            while !Task.isCancelled {
                for (f, s) in pasos { fase = f; try? await Task.sleep(for: .seconds(s)) }
            }
        }
    }
}
