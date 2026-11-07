import AppKit
import Testing
@testable import Embery

@Test func laRamaGuardaLaLuz() {
    var d = DatosHogar(horas: 0, racha: 3, hoy: 0.5)
    let pocas = d.hojas
    d.horas = 150
    #expect(d.hojas > pocas)
    #expect(d.flores == 3 && d.luciernagas == 3)
    d.racha = 12; d.hoy = 1.2
    #expect(d.flores == 7 && d.luciernagas == 8)
    d.estado = .triste
    #expect(d.luciernagas == 0)
}

// Con EMBERY_FOTOS=<carpeta> guarda la escena a 2× en varios estados, para revisarla de cerca.
@Test func fotosDelHogar() throws {
    guard let dir = ProcessInfo.processInfo.environment["EMBERY_FOTOS"] else { return }
    let casos: [(String, Double, Estado, Double, Int, Double, Set<String>)] = [
        ("noche-foco", 23, .foco, 160, 7, 1.1, ["nido", "seta", "campanilla", "farolillo", "guirnalda"]),
        ("dia-reposo", 13, .reposo, 30, 2, 0.6, ["nido"]),
        ("atardecer-triste", 19.5, .triste, 90, 0, 0, ["nido", "farolillo"]),
        ("noche-dormido", 2, .dormido, 90, 4, 0.4, ["nido", "seta"]),
    ]
    for (nombre, hora, estado, horas, racha, hoy, tiene) in casos {
        let e = EscenaHogar(); e.horaFija = hora
        e.d = DatosHogar(estado: estado, horas: horas, racha: racha, hoy: hoy, tiene: tiene)
        let b = Buho(zoom: 0.85, suelo: SUELO_HOGAR / HH, etapa: etapaPorHoras(horas)); b.redimensionar(HW, HH); b.setEstado(estado)
        for _ in 0..<240 { e.paso(1.0 / 60); b.actualizar(1.0 / 60) }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(HW * 2), pixelsHigh: Int(HH * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        ctx.translateBy(x: 0, y: HH * 2); ctx.scaleBy(x: 2, y: -2)
        let l = Lienzo(ctx)
        e.fondo(l); b.dibujar(l); e.frente(l)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(nombre).png"))
    }
}

@Test func avisaSiLaBovedaEsUnaSubcarpeta() throws {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("embery-boveda-\(UUID().uuidString.prefix(8))")
    let inbox = raiz.appendingPathComponent("inbox"), suelta = raiz.appendingPathComponent("suelta")
    for d in [raiz.appendingPathComponent(".obsidian"), inbox, suelta] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
    defer { try? FileManager.default.removeItem(at: raiz) }
    #expect(Boveda.sugerencia(para: raiz, patronDiaria: "daily-notes/{fecha}.md") == nil)
    #expect(Boveda.sugerencia(para: inbox, patronDiaria: "daily-notes/{fecha}.md")?.standardizedFileURL == raiz.standardizedFileURL)
    let fuera = FileManager.default.temporaryDirectory.appendingPathComponent("embery-nada-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: fuera, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fuera) }
    #expect(Boveda.sugerencia(para: fuera, patronDiaria: "daily-notes/{fecha}.md") == fuera)
}
