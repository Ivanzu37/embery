import EventKit
import Observation

// Lo siguiente: el próximo evento del Calendario de macOS en una línea. Solo lee.
@Observable
final class Siguiente {
    struct Evento: Equatable { var titulo: String; var inicio: Date; var todoElDia: Bool; var color: CGColor? }
    private(set) var evento: Evento?
    private(set) var permiso = EKEventStore.authorizationStatus(for: .event)
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var ultima = Date.distantPast

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.refrescar(ya: true) }
    }

    func pedirPermiso() {
        store.requestFullAccessToEvents { _, _ in DispatchQueue.main.async { self.permiso = EKEventStore.authorizationStatus(for: .event); self.refrescar(ya: true) } }
    }

    // Como mucho una vez por minuto, salvo que el Calendario avise de un cambio.
    func refrescar(ya: Bool = false) {
        guard permiso == .fullAccess, ya || Date().timeIntervalSince(ultima) > 60 else { return }
        ultima = Date()
        let ahora = Date(), fin = Calendar.current.date(byAdding: .hour, value: 36, to: ahora)!
        let eventos = store.events(matching: store.predicateForEvents(withStart: ahora, end: fin, calendars: nil))
        // Lo que ya está en marcha no es «lo siguiente», salvo los de todo el día de hoy si no hay nada más.
        let proximo = eventos.filter { !$0.isAllDay && $0.startDate >= ahora }.min { $0.startDate < $1.startDate }
            ?? eventos.first { $0.isAllDay }
        let e = proximo.map { Evento(titulo: $0.title ?? String(localized: "Evento"), inicio: $0.startDate, todoElDia: $0.isAllDay, color: $0.calendar?.cgColor) }
        if e != evento { evento = e }
    }

    static func cuando(_ e: Evento, ahora: Date = Date()) -> String {
        let cal = Calendar.current
        let dia = cal.isDateInToday(e.inicio) ? String(localized: "hoy") : cal.isDateInTomorrow(e.inicio) ? String(localized: "mañana") : Registro.fecha(e.inicio, "EEEE")
        if e.todoElDia { return String(localized: "\(dia) · todo el día") }
        let hora = Registro.fecha(e.inicio, "H:mm"), min = Int(e.inicio.timeIntervalSince(ahora) / 60)
        return min < 60 ? String(localized: "\(dia) \(hora) · en \(max(0, min)) min") : "\(dia) \(hora)"
    }
}
