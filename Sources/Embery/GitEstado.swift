import Foundation

enum GitEstado {
    // Archivos sin commit en la carpeta; nil si no es un repositorio, falta git o tarda más del límite.
    static func cambios(en carpeta: URL, limite: TimeInterval = 2) -> Int? {
        let p = Process(), salida = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", carpeta.path, "status", "--porcelain"]
        p.standardOutput = salida
        p.standardError = FileHandle.nullDevice
        let fin = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in fin.signal() }
        do { try p.run() } catch { return nil }
        // Se lee mientras corre: con muchos cambios la tubería se llena y git se quedaría esperando.
        var datos = Data()
        let lector = DispatchQueue(label: "embery.git")
        lector.async { datos = salida.fileHandleForReading.readDataToEndOfFile() }
        if fin.wait(timeout: .now() + limite) == .timedOut { p.terminate(); return nil }
        lector.sync {}
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: datos, as: UTF8.self).split(separator: "\n").count
    }
}

extension GitEstado {
    // La rama sin lanzar git: «ref: refs/heads/main» en .git/HEAD; separado (un hash) o sin .git, nada.
    static func rama(_ carpeta: URL) -> String? {
        guard let t = try? String(contentsOf: carpeta.appendingPathComponent(".git/HEAD"), encoding: .utf8) else { return nil }
        let l = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard l.hasPrefix("ref: refs/heads/") else { return nil }
        return String(l.dropFirst("ref: refs/heads/".count))
    }
}
