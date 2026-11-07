// Embery · volumen y brillo. Escucha los cambios del sistema (no los provoca): convive con el aviso de macOS y no
// pide permisos. El volumen, por CoreAudio; el brillo, por DisplayServices (privado, cargado en tiempo de ejecución:
// si no está, no hay aviso de brillo y nada se rompe). Sin sondeos: en reposo no cuesta nada.
import AppKit
import AudioToolbox
import CoreAudio

struct Level: Equatable {
    enum Kind { case volume, brightness }
    var kind: Kind
    var value: Double   // 0…1
    var muted = false
    var percent: Int { Int((value * 100).rounded()) }
}

// El sensor de luz mueve el brillo poco a poco y eso no es tuyo: solo cuenta un cambio de al menos `minStep`
// dentro de una ventana de `burst` s (una tecla mueve 1/16). Con el aviso ya en pantalla, se sigue cada cambio.
struct BrightnessFilter {
    var burst = 0.3, minStep = 0.04   // filtro comprobado con F1/F2 el 2026-10-02: no tocar
    private var last: Double?
    private var anchor: (t: Double, v: Double)?
    mutating func feed(_ v: Double, at t: Double, showing: Bool) -> Bool {
        guard let prev = last else { last = v; return false }   // la primera lectura solo se guarda
        last = v
        guard abs(v - prev) > 0.0005 else { return false }
        if showing { anchor = (t, v); return true }
        if anchor == nil || t - anchor!.t > burst { anchor = (t, prev) }
        return abs(v - anchor!.v) >= minStep
    }
}

final class Levels {
    var onChange: ((Level) -> Void)?
    var showing: ((Level.Kind) -> Bool)?   // lo pregunta el filtro del brillo: ¿se ve ya el aviso?
    private var started = false

    // Registra los oyentes una sola vez.
    func start() {
        guard !started else { return }
        started = true
        startVolume()
        startBrightness()
    }

    // MARK: volumen
    private let queue = DispatchQueue(label: "embery.levels")
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var listening: [AudioObjectPropertyAddress] = []
    private var lastVolume: Level?
    private var quietUntil = Date.distantPast   // tras cambiar de salida (AirPods), su volumen no es un cambio tuyo

    private static func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                             _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: el)
    }

    private func startVolume() {
        var a = Levels.addr(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, queue) { [weak self] _, _ in
            DispatchQueue.main.async { self?.attach(quiet: true) }
        }
        attach(quiet: false)
    }

    private static func defaultOutput() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    // Engancha los oyentes a la salida por defecto (y los suelta de la anterior).
    private func attach(quiet: Bool) {
        if let b = deviceBlock {
            for var a in listening { AudioObjectRemovePropertyListenerBlock(device, &a, queue, b) }
        }
        listening = []
        device = Levels.defaultOutput()
        guard device != kAudioObjectUnknown else { return }
        if quiet { quietUntil = Date().addingTimeInterval(1) }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in DispatchQueue.main.async { self?.readVolume() } }
        deviceBlock = block
        let out = kAudioDevicePropertyScopeOutput
        // el volumen «principal» virtual y, por si el dispositivo solo lo da por canales, los canales 1 y 2
        let wanted = [Levels.addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, out),
                      Levels.addr(kAudioDevicePropertyVolumeScalar, out),
                      Levels.addr(kAudioDevicePropertyVolumeScalar, out, 1),
                      Levels.addr(kAudioDevicePropertyVolumeScalar, out, 2),
                      Levels.addr(kAudioDevicePropertyMute, out)]
        for var a in wanted where AudioObjectHasProperty(device, &a) {
            if AudioObjectAddPropertyListenerBlock(device, &a, queue, block) == noErr { listening.append(a) }
        }
        lastVolume = Levels.volume(device) ?? lastVolume
    }

    static func volume(_ dev: AudioObjectID) -> Level? {
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        var v: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(dev, &a),
              AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr else { return nil }   // HDMI: sin volumen
        var m = addr(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        var mute: UInt32 = 0, msize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(dev, &m) { AudioObjectGetPropertyData(dev, &m, 0, nil, &msize, &mute) }
        return Level(kind: .volume, value: Double(max(0, min(1, v))), muted: mute != 0)
    }

    private func readVolume() {
        guard let l = Levels.volume(device) else { return }
        defer { lastVolume = l }
        guard let prev = lastVolume else { return }
        // varios oyentes avisan del mismo cambio (principal y canales): solo cuenta si se mueve algo que se ve
        guard l.muted != prev.muted || abs(l.value - prev.value) > 0.004, Date() >= quietUntil else { return }
        onChange?(l)
    }

    // MARK: brillo
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias RegFn = @convention(c) (UInt32, UnsafeRawPointer?, CFNotificationCallback) -> Int32
    private static let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn: GetFn? = dlsym(ds, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
    private static let regFn: RegFn? = dlsym(ds, "DisplayServicesRegisterForBrightnessChangeNotifications").map { unsafeBitCast($0, to: RegFn.self) }
    private var filter = BrightnessFilter()

    static func brightness() -> Double? {
        guard let get = getFn else { return nil }
        var b: Float = 0
        return get(CGMainDisplayID(), &b) == 0 ? Double(b) : nil
    }

    private func startBrightness() {
        guard let reg = Levels.regFn, let b = Levels.brightness() else { return }
        _ = filter.feed(b, at: CACurrentMediaTime(), showing: false)   // la de ahora, sin aviso
        // callback de C: sin capturas; `self` viaja como observador (vive lo que vive la app)
        _ = reg(CGMainDisplayID(), Unmanaged.passUnretained(self).toOpaque()) { _, observer, _, _, _ in
            guard let observer else { return }
            let me = Unmanaged<Levels>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { me.readBrightness() }
        }
    }

    private func readBrightness() {
        guard let b = Levels.brightness() else { return }
        if filter.feed(b, at: CACurrentMediaTime(), showing: showing?(.brightness) ?? false) {
            onChange?(Level(kind: .brightness, value: b))
        }
    }
}
