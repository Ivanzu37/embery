// Embery · el Nido. Arrastras archivos al Hueco y quedan guardados ahí: referencias (no copias), como mucho 16,
// en EMBERY_DIR/bandeja.json. Sacar un archivo arrastrándolo fuera del Hueco lo quita del Nido.
import AppKit
import SwiftUI

final class Shelf {
    static let max = 16
    private(set) var items: [URL] = []
    private(set) var version = 0
    private let file = URL(fileURLWithPath: EMBERY_DIR).appendingPathComponent("bandeja.json")

    init() {
        let paths = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: file))) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }.filter(Shelf.kept)
    }

    private func save() {
        try? JSONEncoder().encode(items.map(\.path)).write(to: file)
        version &+= 1
    }

    var room: Int { Shelf.max - items.count }

    @discardableResult
    func add(_ urls: [URL]) -> [URL] {
        var added: [URL] = []
        for u in urls where !items.contains(u) && items.count < Shelf.max { items.append(u); added.append(u) }
        if !added.isEmpty { save() }
        return added
    }
    func remove(_ u: URL) { items.removeAll { $0 == u }; save() }
    func clear() { items = []; save() }
    // Si un archivo se mueve o se borra fuera de Embery, desaparece de la bandeja (es una referencia).
    // Si está en un disco que no está montado, se queda: no se ha borrado, se ha ido con el disco.
    static func kept(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) || Vault.offline(u) }
    func prune() {
        let kept = items.filter(Shelf.kept)
        if kept.count != items.count { items = kept; save() }
    }
    // Rutas, una por línea, listas para pegar en un mensaje a Claude.
    func copyPaths() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(items.map(\.path).joined(separator: "\n"), forType: .string)
    }

    private static var icons: [String: NSImage] = [:]
    static func icon(_ u: URL) -> NSImage {
        if let i = icons[u.path] { return i }
        let i = NSWorkspace.shared.icon(forFile: u.path)
        i.size = NSSize(width: 16, height: 16)
        icons[u.path] = i
        return i
    }
    static func shortName(_ u: URL) -> String {
        let n = u.lastPathComponent
        return n.count > 18 ? String(n.prefix(9)) + "…" + String(n.suffix(7)) : n
    }
}

// Coloca las fichas en filas, saltando de línea cuando no caben.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > maxW { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing; row = max(row, z.height); width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + z.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}

// Capa transparente sobre cada ficha: clic abre (⌥ + clic, en Finder); arrastrar saca el archivo del notch.
struct DragSource: NSViewRepresentable {
    let url: URL
    let began: () -> Void
    let ended: (NSPoint) -> Void
    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }
    func updateNSView(_ v: DragSourceView, context: Context) { v.url = url; v.began = began; v.ended = ended }
}

final class DragSourceView: NSView, NSDraggingSource {
    var url: URL?
    var began: (() -> Void)?
    var ended: ((NSPoint) -> Void)?
    private var downAt: NSPoint?
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { downAt = e.locationInWindow; dragging = false }
    override func mouseDragged(with e: NSEvent) {
        guard let d = downAt, !dragging, let url, hypot(e.locationInWindow.x - d.x, e.locationInWindow.y - d.y) > 4 else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        let p = convert(e.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32), contents: img)
        began?()
        beginDraggingSession(with: [item], event: e, source: self)
    }
    override func mouseUp(with e: NSEvent) {
        if !dragging, let url {
            if e.modifierFlags.contains(.option) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            else { NSWorkspace.shared.open(url) }
        }
        downAt = nil
    }
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation {
        c == .outsideApplication ? [.copy, .move, .link, .generic] : []
    }
    func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) {
        dragging = false
        ended?(p)
    }
}
