import Foundation

// Puente con navegadores que lo entiendan (Faro): notificaciones distribuidas, sin depender el uno del otro.
// Embery avisa cuando empieza y acaba el bloqueo de webs; el navegador le pasa el foco que hizo dentro de él.
enum Puente {
    static let foco = Notification.Name("com.ivanzu.embery.foco")
    static let pregunta = Notification.Name("com.ivanzu.embery.pregunta")
    static let sumar = Notification.Name("com.ivanzu.embery.foco-navegador")

    static func avisar(bloqueando: Bool, webs: [String]) {
        DistributedNotificationCenter.default().postNotificationName(foco, object: nil, userInfo: ["bloqueando": bloqueando, "webs": webs], deliverImmediately: true)
    }

    static func sesion(_ i: [AnyHashable: Any]?) -> Sesion? {
        guard let i, let s = i["segundos"] as? Double, s >= 60, let t = i["inicio"] as? Double else { return nil }
        let inicio = Date(timeIntervalSince1970: t)
        return Sesion(inicio: inicio, fin: inicio.addingTimeInterval(s), modo: .cronometro, segundos: s, pausas: 0,
                      tarea: i["tarea"] as? String ?? "Navegador", app: "Faro", appID: "com.ivanzu.faro", bloqueos: 0)
    }
}
