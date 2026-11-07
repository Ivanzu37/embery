// Tests del cálculo del plan desde el historial de Claude desktop.
// Los casos salen de lo que pasó de verdad el 2026-09-30 (bloque reiniciado a y media, sin actividad local).
import XCTest
@testable import Embery

final class PlanUsageTests: XCTestCase {
    let org = "org-a"
    // 30 sep 2026 00:00 UTC como origen; los tiempos se dan en minutos desde ahí
    let t0 = Date(timeIntervalSince1970: 1_790_726_400)
    func at(_ min: Double) -> Date { t0.addingTimeInterval(min * 60) }
    func s(_ min: Double, fh: Double? = nil, sd: Double? = nil, org: String? = "org-a") -> UsageSample {
        var u: [String: Double] = [:]
        if let fh { u["fh"] = fh }
        if let sd { u["sd"] = sd }
        return UsageSample(at: at(min), org: org, used: u)
    }

    // Gasto desde claude.ai o el móvil: el historial no ve cuándo empezó el bloque → no se inventa la hora.
    func testBloqueSinAcotarNoDaReinicio() {
        let h = [s(600, fh: 36), s(1000, fh: 3), s(1015, fh: 9)]
        let e = PlanUsage.estimate(h, org: org, prompts: [], now: at(1020))
        XCTAssertEqual(e.block?.used, 9)
        XCTAssertNil(e.block?.resetsAt)
    }

    // Con lecturas cada 15 min el inicio queda acotado: se da la hora más tardía posible.
    func testBloqueAcotadoDaReinicio() {
        let h = [s(1000, fh: 0), s(1015, fh: 5), s(1030, fh: 12)]
        let e = PlanUsage.estimate(h, org: org, prompts: [], now: at(1035))
        XCTAssertEqual(e.block?.resetsAt, at(1015 + 300))
    }

    // Un turno de Claude Code dentro del hueco fija el inicio exacto.
    func testTurnoDeClaudeCodeFijaElInicio() {
        let h = [s(600, fh: 36), s(1000, fh: 3), s(1015, fh: 9)]
        let e = PlanUsage.estimate(h, org: org, prompts: [at(930)], now: at(1020))
        XCTAssertEqual(e.block?.resetsAt, at(930 + 300))
    }

    // Una bajada es una renovación aunque no llegue a 0.
    func testBajadaEmpiezaBloqueNuevo() {
        let h = [s(1000, fh: 60), s(1010, fh: 70), s(1020, fh: 4), s(1030, fh: 8)]
        let e = PlanUsage.estimate(h, org: org, prompts: [], now: at(1035))
        XCTAssertEqual(e.block?.resetsAt, at(1020 + 300))
    }

    // Un bloque leído hace más de 5 h ya se renovó: no vale.
    func testBloqueViejoSeDescarta() {
        let h = [s(1000, fh: 0), s(1015, fh: 40)]
        let e = PlanUsage.estimate(h, org: org, prompts: [], now: at(1015 + 301))
        XCTAssertNil(e.block)
    }

    // La semana se renueva 7 días después de su última caída.
    func testSemanaDesdeLaUltimaCaida() {
        let h = [s(100, sd: 90), s(160, sd: 1), s(3000, sd: 20)]
        let e = PlanUsage.estimate(h, org: org, prompts: [], now: at(3005))
        let expected = PlanUsage.topOfHourUTC(at(100)).addingTimeInterval(3600 + 7 * 86400)
        XCTAssertEqual(e.week?.resetsAt, expected)
        XCTAssertEqual(e.week?.used, 20)
    }

    // Si la app está en otra cuenta que Claude Code, sus muestras no cuentan.
    func testOtraCuentaNoCuenta() {
        let h = [s(1000, fh: 0), s(1015, fh: 5), s(1030, fh: 70, org: "org-b")]
        let e = PlanUsage.estimate(h, org: org, prompts: [], now: at(1035))
        XCTAssertEqual(e.block?.used, 5)
    }

    // Formato desconocido → nil (mejor "—" que adivinar); v2 se lee.
    func testFormato() {
        XCTAssertNil(PlanUsage.parse(Data(#"{"version":9,"samples":[]}"#.utf8)))
        let v2 = #"{"version":2,"samples":[{"t":1790797897608,"org":"o","u":{"fh":58,"sd":33,"xu":13.35}}]}"#
        let r = PlanUsage.parse(Data(v2.utf8))
        XCTAssertEqual(r?.first?.used["fh"], 58)
        XCTAssertEqual(r?.first?.used["sd"], 33)
    }

    // Curva: máximo por tramo, huecos donde no hubo lecturas.
    func testCurva() {
        let now = at(24 * 60)
        let h = [s(20, fh: 10), s(25, fh: 30), s(24 * 60 - 5, fh: 70)]
        let c = PlanUsage.curve(h, org: org, hours: 24, bins: 72, now: now)
        XCTAssertEqual(c.count, 72)
        XCTAssertEqual(c[1], 30)
        XCTAssertNil(c[10])
        XCTAssertEqual(c[71], 70)
    }
}
