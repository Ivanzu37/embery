import AppKit

// Envoltorio de CGContext con la semántica del canvas 2D del prototipo, para portar el dibujo línea a línea:
// el trazado actual sobrevive a fill/stroke/clip y los degradados radiales van de círculo a círculo.

let PI2 = Double.pi * 2
func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }
func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }
func ease(_ dt: Double, _ rapidez: Double) -> Double { 1 - pow(rapidez, dt) }
func suave(_ x: Double) -> Double { let x = clamp(x, 0, 1); return x * x * (3 - 2 * x) }
func azar(_ a: Double, _ b: Double) -> Double { Double.random(in: a..<b) }
// Ruido suave de una dimensión: suma de senos con frecuencias que no se repiten entre sí.
func ruido(_ t: Double, _ s: Double) -> Double { sin(t * 0.37 + s) + 0.6 * sin(t * 0.61 + s * 1.7) + 0.3 * sin(t * 1.13 + s * 2.3) }

struct Col {
    var r, g, b: Double
    var a: Double = 1
    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(_ hex: String) {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(Double(v >> 16 & 255), Double(v >> 8 & 255), Double(v & 255))
    }
    func alfa(_ a: Double) -> Col { var c = self; c.a = a; return c }
    func mezcla(_ o: Col, _ k: Double) -> Col { Col(lerp(r, o.r, k).rounded(), lerp(g, o.g, k).rounded(), lerp(b, o.b, k).rounded(), lerp(a, o.a, k)) }
    var cg: CGColor { CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: clamp(a, 0, 1)) }
}

struct Degradado {
    enum Forma { case radial(Double, Double, Double, Double, Double, Double), lineal(Double, Double, Double, Double) }
    var forma: Forma
    var paradas: [(Double, Col)] = []
    static func radial(_ x0: Double, _ y0: Double, _ r0: Double, _ x1: Double, _ y1: Double, _ r1: Double) -> Degradado { Degradado(forma: .radial(x0, y0, r0, x1, y1, r1)) }
    static func lineal(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Degradado { Degradado(forma: .lineal(x0, y0, x1, y1)) }
    func parada(_ k: Double, _ c: Col) -> Degradado { var d = self; d.paradas.append((k, c)); return d }
}

final class Lienzo {
    let ctx: CGContext
    private(set) var camino = CGMutablePath()
    var alfa: Double = 1 { didSet { ctx.setAlpha(alfa) } }
    var sumaLuz = false { didSet { ctx.setBlendMode(sumaLuz ? .plusLighter : .normal) } }
    private var pila: [(Double, Bool)] = []

    init(_ ctx: CGContext) { self.ctx = ctx; ctx.setLineCap(.round) }

    func save() { ctx.saveGState(); pila.append((alfa, sumaLuz)) }
    func restore() { ctx.restoreGState(); if let (a, s) = pila.popLast() { alfa = a; sumaLuz = s } }
    func translate(_ x: Double, _ y: Double) { ctx.translateBy(x: x, y: y) }
    func scale(_ x: Double, _ y: Double) { ctx.scaleBy(x: x, y: y) }
    func rotate(_ a: Double) { ctx.rotate(by: a) }

    func beginPath() { camino = CGMutablePath() }
    func closePath() { camino.closeSubpath() }
    func moveTo(_ x: Double, _ y: Double) { camino.move(to: CGPoint(x: x, y: y)) }
    func lineTo(_ x: Double, _ y: Double) {
        if camino.isEmpty { camino.move(to: CGPoint(x: x, y: y)) } else { camino.addLine(to: CGPoint(x: x, y: y)) }
    }
    func bezierCurveTo(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ x: Double, _ y: Double) {
        camino.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: a, y: b), control2: CGPoint(x: c, y: d))
    }
    func quadraticCurveTo(_ a: Double, _ b: Double, _ x: Double, _ y: Double) {
        camino.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: a, y: b))
    }
    func arc(_ x: Double, _ y: Double, _ r: Double, _ a0: Double = 0, _ a1: Double = PI2, inverso: Bool = false) {
        camino.addArc(center: CGPoint(x: x, y: y), radius: max(0, r), startAngle: a0, endAngle: a1, clockwise: inverso)
    }
    func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ giro: Double = 0) {
        let t = CGAffineTransform(translationX: x, y: y).rotated(by: giro)
        camino.addEllipse(in: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: t)
    }
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { camino.addRect(CGRect(x: x, y: y, width: w, height: h)) }
    func roundRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) {
        camino.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r)
    }

    func fill(_ c: Col) { ctx.addPath(camino); ctx.setFillColor(c.cg); ctx.fillPath() }
    func fill(_ d: Degradado) {
        ctx.saveGState(); ctx.addPath(camino); ctx.clip(); pintar(d); ctx.restoreGState()
    }
    func stroke(_ c: Col, _ ancho: Double) {
        ctx.addPath(camino); ctx.setStrokeColor(c.cg); ctx.setLineWidth(ancho); ctx.strokePath()
    }
    func clip() { ctx.addPath(camino); ctx.clip() }
    // Filo de luz sobre el trazado actual, que no cambia: se recorta a él y se suma luz con un halo de su mismo color.
    func contraluz(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: Col, _ ancho: Double, _ desenfoque: Double) {
        ctx.saveGState()
        ctx.addPath(camino); ctx.clip()
        ctx.setBlendMode(.plusLighter)
        ctx.setShadow(offset: .zero, blur: desenfoque, color: c.cg)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.saveGState()
        ctx.addPath(camino); ctx.setLineWidth(ancho); ctx.replacePathWithStrokedPath(); ctx.clip()
        pintar(.lineal(x0, y0, x1, y1).parada(0, c).parada(1, Col(0, 0, 0, 0)))
        ctx.restoreGState()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
    func fillRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Col) { beginPath(); rect(x, y, w, h); fill(c) }
    func fillRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ d: Degradado) { beginPath(); rect(x, y, w, h); fill(d) }
    private func pintar(_ d: Degradado) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: d.paradas.map(\.1.cg) as CFArray,
                                 locations: d.paradas.map { CGFloat($0.0) }) else { return }
        let opciones: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        switch d.forma {
        case let .radial(x0, y0, r0, x1, y1, r1):
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: x0, y: y0), startRadius: max(0, r0), endCenter: CGPoint(x: x1, y: y1), endRadius: max(0, r1), options: opciones)
        case let .lineal(x0, y0, x1, y1):
            ctx.drawLinearGradient(g, start: CGPoint(x: x0, y: y0), end: CGPoint(x: x1, y: y1), options: opciones)
        }
    }

    // Texto centrado en (x, y), con el lienzo en coordenadas que crecen hacia abajo.
    func texto(_ s: String, _ x: Double, _ y: Double, tamano: Double, peso: NSFont.Weight, color: Col, redonda: Bool = true) {
        let linea = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: Lienzo.fuente(tamano, peso, redonda), .foregroundColor: NSColor(cgColor: color.cg)!]))
        let caja = CTLineGetBoundsWithOptions(linea, .useOpticalBounds)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x - caja.width / 2 - caja.minX, y: y + caja.height / 2 + caja.minY)
        CTLineDraw(linea, ctx)
        ctx.restoreGState()
    }

    static func fuente(_ tamano: Double, _ peso: NSFont.Weight, _ redonda: Bool) -> NSFont {
        let f = NSFont.systemFont(ofSize: tamano, weight: peso)
        guard redonda, let d = f.fontDescriptor.withDesign(.rounded), let r = NSFont(descriptor: d, size: tamano) else { return f }
        return r
    }
    static func ancho(_ s: String, tamano: Double, peso: NSFont.Weight, redonda: Bool = false) -> Double {
        (s as NSString).size(withAttributes: [.font: fuente(tamano, peso, redonda)]).width
    }
    // Recorta con «…» hasta que quepa en el ancho dado.
    static func recortar(_ s: String, cabe: Double, tamano: Double, peso: NSFont.Weight) -> String {
        guard ancho(s, tamano: tamano, peso: peso) > cabe else { return s }
        var t = s
        while !t.isEmpty, ancho(t + "…", tamano: tamano, peso: peso) > cabe { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces) + "…"
    }
}
