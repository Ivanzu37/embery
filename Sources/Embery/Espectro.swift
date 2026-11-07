import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import Observation

// Espectro real del audio del sistema: process tap global de Core Audio en un dispositivo agregado privado
// y FFT de 1024 con vDSP. Solo existe mientras la tarjeta del Canto se ve y hay música; al parar se destruye todo.
@Observable
final class Espectro {
    static let bandas = 28, n = 1024
    // Sigue encendido un momento tras parar para que las barras bajen despacio antes de quedarse quietas.
    private(set) var vivo = false

    @ObservationIgnored private var tap = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var dispositivo = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var proc: AudioDeviceIOProcID?
    @ObservationIgnored private var querido = false
    @ObservationIgnored private var apagarEn: DispatchWorkItem?
    @ObservationIgnored private let cola = DispatchQueue(label: "embery.espectro")
    @ObservationIgnored private let cerrojo = NSLock()
    @ObservationIgnored private var objetivo = [Float](repeating: 0, count: bandas)   // bajo el cerrojo
    @ObservationIgnored private(set) var actual = [Float](repeating: 0, count: bandas)  // solo en el hilo principal
    @ObservationIgnored private var antes = 0.0

    func encender(_ si: Bool) {
        guard si != querido else { return }
        querido = si
        apagarEn?.cancel(); apagarEn = nil
        if si {
            vivo = true
            cola.async { self.arrancar() }
        } else {
            cola.async { self.parar() }
            let w = DispatchWorkItem { [weak self] in self?.vivo = false }
            apagarEn = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
        }
    }

    // Lo llama el dibujo, a 30 fps: acerca lo que se ve a lo último que se oyó.
    func paso(_ t: Double) -> [Float] {
        let dt = antes == 0 ? 1.0 / 30 : min(0.1, t - antes); antes = t
        cerrojo.lock(); let o = querido ? objetivo : [Float](repeating: 0, count: Espectro.bandas); cerrojo.unlock()
        actual = Espectro.suavizar(actual, hacia: o, dt: dt)
        return actual
    }

    // MARK: Core Audio (en `cola`)

    private func arrancar() {
        guard proc == nil else { return }
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr, let uid = Espectro.salida() else { return parar() }
        let agregado: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Embery", kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: uid, kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false, kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]]]
        guard AudioHardwareCreateAggregateDevice(agregado as CFDictionary, &dispositivo) == noErr else { return parar() }

        let fft = vDSP.FFT(log2n: 10, radix: .radix2, ofType: DSPSplitComplex.self)!
        let ventana = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Espectro.n, isHalfWindow: false)
        var muestras = [Float](repeating: 0, count: Espectro.n), lleno = 0
        var re = [Float](repeating: 0, count: Espectro.n / 2), im = re, mag = re
        let estado = AudioDeviceCreateIOProcIDWithBlock(&proc, dispositivo, nil) { [weak self] _, entrada, _, _, _ in
            let lista = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: entrada))
            guard let b = lista.first, let d = b.mData else { return }
            let f = d.assumingMemoryBound(to: Float.self), c = max(1, Int(b.mNumberChannels))
            for i in 0..<(Int(b.mDataByteSize) / 4 / c) {
                // Mezcla de los canales, interleaved.
                var s: Float = 0
                for k in 0..<c { s += f[i * c + k] }
                muestras[lleno] = s / Float(c); lleno += 1
                guard lleno == Espectro.n else { continue }
                lleno = 0
                vDSP.multiply(muestras, ventana, result: &muestras)
                re.withUnsafeMutableBufferPointer { rp in im.withUnsafeMutableBufferPointer { ip in
                    var sc = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    muestras.withUnsafeBytes { vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &sc, 1, vDSP_Length(Espectro.n / 2)) }
                    fft.forward(input: sc, output: &sc)
                    vDSP.absolute(sc, result: &mag)
                }}
                let o = Espectro.medir(mag)
                self?.cerrojo.lock(); self?.objetivo = o; self?.cerrojo.unlock()
            }
        }
        guard estado == noErr, AudioDeviceStart(dispositivo, proc) == noErr else { return parar() }
    }

    private func parar() {
        if let p = proc { AudioDeviceStop(dispositivo, p); AudioDeviceDestroyIOProcID(dispositivo, p); proc = nil }
        if dispositivo != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(dispositivo); dispositivo = AudioObjectID(kAudioObjectUnknown) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap); tap = AudioObjectID(kAudioObjectUnknown) }
        cerrojo.lock(); objetivo = [Float](repeating: 0, count: Espectro.bandas); cerrojo.unlock()
    }

    private static func salida() -> String? {
        var dir = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0), tam = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &dir, 0, nil, &tam, &id) == noErr else { return nil }
        dir.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?; tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &dir, 0, nil, &tam, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    // MARK: Lógica pura

    // Bordes logarítmicos de ~47 Hz a ~16 kHz (a 48 kHz, cada casilla de la FFT son 46,9 Hz); nunca dos bandas en la misma casilla.
    static let bordes: [Int] = {
        var b = [1]
        for k in 1...bandas { b.append(max(b[k - 1] + 1, Int((pow(341.0, Double(k) / Double(bandas))).rounded()))) }
        return b
    }()

    // Magnitudes de la FFT (n/2) a bandas de 0 a 1: el pico de cada banda en dB, de −60 a 0 dB sobre el máximo de un seno.
    static func medir(_ mag: [Float]) -> [Float] {
        let ref = Float(n) / 4   // un seno a escala completa con ventana de Hann da ~n/4
        return (0..<bandas).map { k in
            let lo = min(bordes[k], mag.count), hi = min(bordes[k + 1], mag.count)
            guard lo < hi else { return 0 }
            let pico = mag[lo..<hi].max() ?? 0
            let db = 20 * log10(max(pico / ref, 1e-6))
            return min(1, max(0, (db + 60) / 60))
        }
    }

    // Sube en ~0,15 s y baja en ~0,4 s: se mueve con la música sin saltar.
    static func suavizar(_ a: [Float], hacia o: [Float], dt: Double) -> [Float] {
        let sube = Float(1 - exp(-dt / 0.15)), baja = Float(1 - exp(-dt / 0.4))
        return zip(a, o).map { a, o in a + (o - a) * (o > a ? sube : baja) }
    }
}
