import Foundation
import Testing
@testable import Embery

private func sesion(_ id: String, hace: Double = 0, ctx: Int? = nil) -> SessionInfo {
    var s = SessionInfo(id: id, project: id)
    s.lastEvent = Date().addingTimeInterval(-hace); s.ctx = ctx
    return s
}

@Test func tareasDeTaskCreateYTaskUpdate() {
    var l = Tarea.aplicar([], herramienta: "TaskCreate", entrada: ["subject": "Leer el plan"], respuesta: ["task": ["id": "1", "subject": "Leer el plan"]])
    l = Tarea.aplicar(l, herramienta: "TaskCreate", entrada: ["subject": "Escribir la prueba"], respuesta: nil)
    #expect(l.map(\.clave) == ["1", "2"])
    l = Tarea.aplicar(l, herramienta: "TaskUpdate", entrada: ["taskId": "1", "status": "completed"], respuesta: nil)
    l = Tarea.aplicar(l, herramienta: "TaskUpdate", entrada: ["taskId": "2", "status": "in_progress", "subject": "Escribir dos"], respuesta: nil)
    #expect(l.map(\.estado) == [.hecha, .curso])
    #expect(l[1].texto == "Escribir dos")
    #expect(Tarea.aplicar(l, herramienta: "TaskUpdate", entrada: ["taskId": "1", "status": "deleted"], respuesta: nil).count == 1)
    // Lo que no se entiende deja la lista como estaba.
    #expect(Tarea.aplicar(l, herramienta: "TaskUpdate", entrada: ["taskId": "9", "status": "completed"], respuesta: nil) == l)
    #expect(Tarea.aplicar(l, herramienta: "TaskCreate", entrada: ["otra": 1], respuesta: nil) == l)
}

@Test func tareasDeTodoWrite() {
    let entrada: [String: Any] = ["todos": [["content": "a", "status": "completed"], ["content": "b", "status": "in_progress"], ["content": "c", "status": "pending"]]]
    let l = Tarea.aplicar([], herramienta: "TodoWrite", entrada: entrada, respuesta: nil)
    #expect(l.map(\.estado) == [.hecha, .curso, .pendiente])
    #expect(Tarea.aplicar(l, herramienta: "TodoWrite", entrada: ["todos": [["content": "x", "status": "raro"]]], respuesta: nil) == l)
}

@Test func liveCuentaAyudantesYTareas() {
    let live = Live()
    for (evento, herramienta, entrada) in [("PreToolUse", "Task", [:]), ("PreToolUse", "Agent", [:]), ("PostToolUse", "Task", [:]),
                                            ("PostToolUse", "TaskCreate", ["subject": "Revisar"]), ("PostToolUseFailure", "TaskCreate", ["subject": "No"])] as [(String, String, [String: Any])] {
        live.handle(["hook_event_name": evento, "session_id": "s", "tool_name": herramienta, "tool_input": entrada])
    }
    #expect(live.sessions["s"]?.ayudantes == 1)
    #expect(live.sessions["s"]?.tareas.map(\.texto) == ["Revisar"])
    live.handle(["hook_event_name": "Stop", "session_id": "s"])
    #expect(live.sessions["s"]?.ayudantes == 0)
}

@Test func mesasPorConversacion() {
    let sala = Scriptorium()
    #expect(sala.mesas.count == 1 && sala.mesas[0].id == nil)
    // La primera conversación ocupa la mesa de nadie; las siguientes, mesas nuevas en orden de llegada.
    sala.sincronizar([sesion("a", hace: 30), sesion("b", hace: 10)])
    #expect(sala.mesas.map(\.id) == ["a", "b"])
    #expect(Scriptorium.ancho(mesas: sala.mesas.count) == 456)
    sala.sincronizar((0..<6).map { sesion("s\($0)", hace: Double(60 - $0)) } + [sesion("a", hace: 30), sesion("b", hace: 10)])
    #expect(sala.mesas.count == 4 && sala.extra == 4)
    #expect(Scriptorium.ancho(mesas: 9) == 728)
}

@Test func mesaQueSeVaEspera20s() {
    let sala = Scriptorium(), ahora = Date()
    sala.sincronizar([sesion("a"), sesion("b")], ahora: ahora)
    sala.sincronizar([sesion("a")], ahora: ahora)
    #expect(sala.mesas.count == 2 && sala.mesas[1].e.viva == false)
    // Una nueva en esos 20 s no ocupa la vacía.
    sala.sincronizar([sesion("a"), sesion("c")], ahora: ahora.addingTimeInterval(5))
    #expect(sala.mesas.map(\.id) == ["a", "b", "c"])
    sala.sincronizar([sesion("a"), sesion("c")], ahora: ahora.addingTimeInterval(21))
    #expect(sala.mesas.map(\.id) == ["a", "c"])
    // La última no se retira: se queda como la mesa de nadie, durmiendo.
    sala.sincronizar([], ahora: ahora.addingTimeInterval(30))
    sala.sincronizar([], ahora: ahora.addingTimeInterval(60))
    #expect(sala.mesas.count == 1 && sala.mesas[0].id == nil && sala.mesas[0].e.viva)
    #expect(sala.mesas[0].e.actividad == .duerme)
}

@Test func compactarVaciaLaMesaDeprisa() {
    // Caída de 15 puntos o más: 0,5/s; menor: 0,12/s, como cuando sube.
    func tras(_ desde: Double, _ hasta: Double) -> Double {
        let e = Escribiente()
        e.ctxObj = desde; e.contexto = desde; e.ctxObj = hasta
        for _ in 0..<15 { e.actualizar(1.0 / 30) }
        return e.contexto
    }
    #expect(abs(tras(0.8, 0.1) - 0.55) < 0.01)
    #expect(abs(tras(0.5, 0.38) - 0.44) < 0.01)
}

@Test func tablonDejaSuSitioTrasDosSegundos() {
    let e = Escribiente()
    let lista = (0..<7).map { Tarea(clave: "\($0)", texto: "t\($0)", estado: .pendiente) }
    e.tareas(lista)
    #expect(e.visibles.map(\.clave) == ["0", "1", "2", "3", "4", "5"])
    var hecha = lista; hecha[0].estado = .hecha
    e.tareas(hecha)
    #expect(e.visibles.first?.clave == "0")
    for _ in 0..<70 { e.actualizar(1.0 / 30) }
    #expect(e.visibles.map(\.clave) == ["1", "2", "3", "4", "5", "6"])
}
