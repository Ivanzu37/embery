// Tests del disco de la bóveda: qué cuenta como «dentro» y qué se queda en custodia sin disco.
import XCTest
@testable import Embery

final class VaultTests: XCTestCase {
    func testContains() {
        let v = Vault(root: "/Volumes/Notes")
        XCTAssertTrue(v.contains("/Volumes/Notes"))
        XCTAssertTrue(v.contains("/Volumes/Notes/Vault"))
        XCTAssertFalse(v.contains("/Volumes/Notes2/notas"))   // otro disco que empieza igual
        XCTAssertFalse(v.contains(""))
    }

    func testOffline() {
        XCTAssertTrue(Vault.offline(URL(fileURLWithPath: "/Volumes/NoExiste-Embery/nota.md")))
        XCTAssertFalse(Vault.offline(URL(fileURLWithPath: "/Users/nadie/nota.md")))   // disco interno: se borró de verdad
        XCTAssertFalse(Vault.offline(URL(fileURLWithPath: "/Volumes")))
    }

    func testShelfKeepsFilesOfMissingDisk() {
        XCTAssertTrue(Shelf.kept(URL(fileURLWithPath: "/Volumes/NoExiste-Embery/nota.md")))
        XCTAssertFalse(Shelf.kept(URL(fileURLWithPath: "/Users/nadie/borrado.md")))
    }
}

final class VolumenTests: XCTestCase {
    func testRaicesSaleDeLaBoveda() {
        XCTAssertEqual(Vault.volumen(de: "/Volumes/Disco/Notas/Bóveda"), "/Volumes/Disco")
        XCTAssertNil(Vault.volumen(de: "/Users/alguien/Documents/Bóveda"))
    }
}
