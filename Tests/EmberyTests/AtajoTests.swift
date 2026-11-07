import AppKit
import Carbon.HIToolbox
import Testing
@testable import Embery

private func pulsar(_ c: String, _ tecla: Int, _ f: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: f, timestamp: 0, windowNumber: 0, context: nil,
                     characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: UInt16(tecla))!
}

@Test func atajoDeUnaPulsacion() {
    let a = AtajoTeclas(pulsar("n", kVK_ANSI_N, [.control, .option]))
    #expect(a == .deSerie)
    let b = AtajoTeclas(pulsar("j", kVK_ANSI_J, [.command, .shift]))
    #expect(b?.mods == cmdKey | shiftKey && b?.texto == "⇧⌘J")
}

@Test func lasTeclasEspecialesLlevanNombre() {
    #expect(AtajoTeclas(pulsar(String(UnicodeScalar(0xF708)!), kVK_F5, [.control]))?.texto == "⌃F5")
    #expect(AtajoTeclas(pulsar(String(UnicodeScalar(0xF702)!), kVK_LeftArrow, [.option]))?.texto == "⌥←")
    #expect(AtajoTeclas(pulsar(" ", kVK_Space, [.command, .option]))?.texto == "⌥⌘Espacio")
}

@Test func sinModificadorNoHayAtajo() {
    #expect(AtajoTeclas(pulsar("n", kVK_ANSI_N, [])) == nil)
    #expect(AtajoTeclas(pulsar("N", kVK_ANSI_N, [.shift])) == nil)
}
