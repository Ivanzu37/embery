// Tests del calendario de tokens: cada respuesta una vez, lectura a trozos y memoria más allá de los 30 días.
import XCTest
@testable import Embery

final class TokensTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("embery-tokens-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("proyecto"), withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func line(_ id: String, _ out: Int, ts: String = "2026-10-01T10:00:00.000Z", side: Bool = false) -> String {
        #"{"type":"assistant","isSidechain":\#(side),"timestamp":"\#(ts)","message":{"id":"\#(id)","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":99999,"output_tokens":\#(out)}}}"# + "\n"
    }
    func append(_ s: String, _ name: String = "a.jsonl") {
        let u = dir.appendingPathComponent("proyecto/\(name)")
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(Data(s.utf8)); try? h.close() }
        else { try? Data(s.utf8).write(to: u) }
    }
    func ledger() -> TokenLedger { TokenLedger(root: dir.path, store: dir.appendingPathComponent("tokens.json")) }
    var day: String { TokenLedger.dayFormat.string(from: ISO8601DateFormatter().date(from: "2026-10-01T10:00:00Z")!) }

    func testEachMessageOnce() {
        append(line("A", 5) + line("A", 5) + line("A", 5) + #"{"type":"user","message":{}}"# + "\n" + line("B", 20))
        let l = ledger(); l.scanNow()
        XCTAssertEqual(l.days[day], 115 + 130)   // sin lecturas de caché
    }

    func testMessageSplitAcrossReads() {
        append(line("A", 5))
        let l = ledger(); l.scanNow()
        XCTAssertEqual(l.days[day], 115)
        append(line("A", 7) + line("B", 0))   // sigue el mismo mensaje y vale su última línea
        l.scanNow()
        XCTAssertEqual(l.days[day], 117 + 110)
    }

    func testSidechainAndPartialLine() {
        append(line("S", 50, side: true) + String(line("C", 1).dropLast()))   // la última, sin terminar
        let l = ledger(); l.scanNow()
        XCTAssertEqual(l.days[day], 160)   // el subagente cuenta; la línea a medias, todavía no
        append("\n"); l.scanNow()
        XCTAssertEqual(l.days[day], 160 + 111)
    }

    func testSubagentsInSubfolders() throws {
        let sub = dir.appendingPathComponent("proyecto/sesion/subagents")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try line("G", 5, side: true).write(to: sub.appendingPathComponent("agent-1.jsonl"), atomically: true, encoding: .utf8)
        let l = ledger(); l.scanNow()
        XCTAssertEqual(l.days[day], 115)
    }

    func testKeepsDaysOfDeletedConversations() {
        append(line("A", 5))
        let l = ledger()
        let first = expectation(description: "lectura"), second = expectation(description: "tras borrar")
        l.scan { first.fulfill() }
        wait(for: [first], timeout: 5)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("proyecto/a.jsonl"))
        l.scan { second.fulfill() }
        wait(for: [second], timeout: 5)
        XCTAssertEqual(l.days[day], 115)
        XCTAssertEqual(ledger().days[day], 115)   // y lo recuerda tras reiniciar (tokens.json)
    }

    // Una raíz que no se lee (otro HOME) no debe archivar nada: al volver se contaría dos veces.
    func testMissingRootDoesNotArchiveDays() {
        append(line("A", 5))
        let first = expectation(description: "lectura"), second = expectation(description: "sin carpeta")
        ledger().scan { first.fulfill() }
        wait(for: [first], timeout: 5)
        TokenLedger(root: dir.appendingPathComponent("no-existe").path, store: dir.appendingPathComponent("tokens.json")).scan { second.fulfill() }
        wait(for: [second], timeout: 5)
        let l = ledger(); l.scanNow()
        XCTAssertEqual(l.days[day], 115)
    }

    func testShort() {
        XCTAssertEqual(TokenLedger.short(2_340_000), "2,3M")
        XCTAssertEqual(TokenLedger.short(850_400), "850k")
        XCTAssertEqual(TokenLedger.short(420), "420")
    }
}
