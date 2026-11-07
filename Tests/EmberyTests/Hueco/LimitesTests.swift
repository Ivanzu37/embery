import Foundation
import Testing
@testable import Embery

// handleRateLimit escribe limits.json: solo corre con EMBERY_DIR aparte, para no pisar el de la app instalada.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["EMBERY_DIR"] != nil))
struct LimitesTests {
    @Test func rateLimitEventFijaBloqueYSemana() {
        let live = Live(), ahora = Date().timeIntervalSince1970
        live.handleRateLimit(["type": "rate_limit_event", "rate_limit_info": ["unifiedWindows": [
            "five_hour": ["utilization": 0.44, "resetsAt": ahora + 3600],
            "seven_day": ["utilization": 0.38, "resetsAt": ahora + 86400]]]])
        let f = live.feed()
        #expect(f.block == 44)
        #expect(f.week == 38)
        #expect(live.edadLimites < 5)
    }

    @Test func eventoVacioNoBorraNada() {
        let live = Live(), antes = live.limits.at
        live.handleRateLimit(["type": "rate_limit_event", "rate_limit_info": [:]])
        #expect(live.limits.at == antes)
    }
}
