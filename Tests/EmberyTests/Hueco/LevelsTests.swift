// Tests del filtro del brillo: el sensor de luz no dispara el aviso; una tecla sí.
import XCTest
@testable import Embery

final class LevelsTests: XCTestCase {
    func testFirstReadingIsSilent() {
        var f = BrightnessFilter()
        XCTAssertFalse(f.feed(0.6, at: 0, showing: false))
    }

    func testSlowRampDoesNotFire() {   // brillo automático: 0,005 cada 0,2 s durante 10 s
        var f = BrightnessFilter()
        _ = f.feed(0.6, at: 0, showing: false)
        for i in 1...50 { XCTAssertFalse(f.feed(0.6 - 0.005 * Double(i), at: 0.2 * Double(i), showing: false), "paso \(i)") }
    }

    func testKeyStepFires() {   // una tecla: 1/16 de golpe
        var f = BrightnessFilter()
        _ = f.feed(0.6, at: 0, showing: false)
        XCTAssertTrue(f.feed(0.6625, at: 5, showing: false))
    }

    func testAnimatedKeyStepFires() {   // la tecla animada en varios trocitos dentro de 0,3 s
        var f = BrightnessFilter()
        _ = f.feed(0.6, at: 0, showing: false)
        let fired = (1...5).map { f.feed(0.6 + 0.0125 * Double($0), at: 5 + 0.03 * Double($0), showing: false) }
        XCTAssertTrue(fired.contains(true))
    }

    func testFollowsEveryChangeWhileShowing() {
        var f = BrightnessFilter()
        _ = f.feed(0.6, at: 0, showing: false)
        XCTAssertTrue(f.feed(0.605, at: 1, showing: true))
        XCTAssertFalse(f.feed(0.605, at: 1.1, showing: true))   // sin cambio, nada
    }

    func testLevelPercent() {
        XCTAssertEqual(Level(kind: .volume, value: 0.625).percent, 63)
        XCTAssertEqual(Level(kind: .brightness, value: 0).percent, 0)
    }
}
