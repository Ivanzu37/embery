import Testing
@testable import Embery

private func salida(_ c: [String]) -> String { c.joined(separator: "\u{1F}") }

@Test func leerMusicaConComasDecimales() throws {
    let p = try #require(Canto.leer(salida(["playing", "Canción", "Artista", "21,345", "178,5", "id-1"]), app: .musica))
    #expect(p.app == .musica && p.titulo == "Canción" && p.artista == "Artista")
    #expect(p.posicion == 21.345 && p.duracion == 178.5)
    #expect(p.sonando && p.id == "id-1")
}

@Test func leerSpotifyConDuracionEnMilisegundos() throws {
    let p = try #require(Canto.leer(salida(["playing", "Track", "Artist", "21,345", "178000", "spotify:track:x"]), app: .spotify))
    #expect(p.posicion == 21.345 && p.duracion == 178)
}

@Test func leerAceptaDecimalesConPunto() throws {
    let p = try #require(Canto.leer(salida(["playing", "T", "A", "21.345", "178.5", "id"]), app: .musica))
    #expect(p.posicion == 21.345 && p.duracion == 178.5)
}

@Test func leerPausaSinSonar() throws {
    #expect(try #require(Canto.leer(salida(["paused", "T", "A", "10", "100", "id"]), app: .musica)).sonando == false)
}

@Test func leerParadoOMalDevuelveNil() {
    #expect(Canto.leer("stopped", app: .musica) == nil)
    #expect(Canto.leer(salida(["stopped", "T", "A", "10", "100", "id"]), app: .musica) == nil)
    #expect(Canto.leer(salida(["playing", "T", "A"]), app: .musica) == nil)
    #expect(Canto.leer("basura", app: .spotify) == nil)
}

@Test func leerLimitaPosicionALaDuracion() throws {
    #expect(try #require(Canto.leer(salida(["playing", "T", "A", "200", "100", "id"]), app: .musica)).posicion == 100)
}

@Test func elegirPrefiereLaQueSuena() throws {
    let pausada = try #require(Canto.leer(salida(["paused", "Primera", "A", "1", "10", "1"]), app: .musica))
    let otra = try #require(Canto.leer(salida(["paused", "Segunda", "A", "1", "10", "2"]), app: .spotify))
    let sonando = try #require(Canto.leer(salida(["playing", "Tercera", "A", "1", "10", "3"]), app: .spotify))
    #expect(Canto.elegir([pausada, sonando]) == sonando)
    #expect(Canto.elegir([pausada, otra]) == pausada)
    #expect(Canto.elegir([]) == nil)
}

@Test func tiempoEnMinutosYSegundos() {
    #expect(Canto.tiempo(21) == "0:21")
    #expect(Canto.tiempo(178.9) == "2:58")
    #expect(Canto.tiempo(0) == "0:00")
}

@Test func bordesDelEspectroCrecientes() {
    let b = Espectro.bordes
    #expect(b.count == Espectro.bandas + 1 && b.first == 1 && b.last! <= Espectro.n / 2)
    #expect(zip(b, b.dropFirst()).allSatisfy { $0 < $1 })
}

@Test func medirSilencioYPico() {
    var mag = [Float](repeating: 0, count: Espectro.n / 2)
    #expect(Espectro.medir(mag).allSatisfy { $0 == 0 })
    mag[Espectro.bordes[10]] = 256   // n/4: un seno a escala completa
    let v = Espectro.medir(mag)
    #expect(abs(v[10] - 1) < 0.001)
    #expect(v.enumerated().allSatisfy { $0.offset == 10 || $0.element == 0 })
    mag[Espectro.bordes[10]] = 256 * 0.001   // −60 dB
    #expect(Espectro.medir(mag)[10] == 0)
    mag[Espectro.bordes[10]] = .greatestFiniteMagnitude
    #expect(Espectro.medir(mag).allSatisfy { (0...1).contains($0) })
}

@Test func suavizarSubeAntesQueBajaSinPasarse() {
    let v = Espectro.suavizar([0.2, 0.8], hacia: [1, 0], dt: 0.1)
    #expect(v[0] > 0.2 && v[0] < 1 && v[1] < 0.8 && v[1] > 0)
    #expect(Espectro.suavizar([0], hacia: [1], dt: 0.1)[0] > 1 - Espectro.suavizar([1], hacia: [0], dt: 0.1)[0])
    #expect(Espectro.suavizar([0.2, 0.8], hacia: [1, 0], dt: 0) == [0.2, 0.8])
    var c: [Float] = [0]
    for _ in 0..<300 { c = Espectro.suavizar(c, hacia: [1], dt: 1.0 / 30) }
    #expect(abs(c[0] - 1) < 0.001)
}
