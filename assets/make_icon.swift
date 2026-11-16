// Génère assets/icon-1024.png : un cœur rouge gribouillé au crayon avec une prise blanche dessinée à la main
// (clin d'œil à l'univers de « Simple Plan »). Dessin déterministe (graine fixe).
// Usage : swift assets/make_icon.swift assets/icon-1024.png
import AppKit
import CoreGraphics

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(S))
ctx.scaleBy(x: 1, y: -1)

// Générateur pseudo-aléatoire reproductible
struct RNG {
    var state: UInt64 = 0x5eed_1234_abcd
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}
var rng = RNG()

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255,
                                          CGFloat(hex & 255) / 255, a])!
}

// MARK: Papier
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 188, cornerHeight: 188, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x000000, 0.4))
ctx.setFillColor(color(0xf3f1ec))
ctx.addPath(tilePath); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
ctx.setFillColor(color(0xf4f2ed)); ctx.fill(tile)
// grain de papier : taches et fibres
for _ in 0..<5200 {
    let x = rng.range(100, 924), y = rng.range(100, 924)
    let r = rng.range(0.6, 2.4)
    ctx.setFillColor(color(rng.next() > 0.5 ? 0xb9b4a8 : 0xffffff, rng.range(0.08, 0.35)))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}
for _ in 0..<260 {
    let x = rng.range(100, 924), y = rng.range(100, 924), a = rng.range(0, .pi)
    let l = rng.range(10, 36)
    ctx.setStrokeColor(color(0xb9b4a8, rng.range(0.06, 0.18))); ctx.setLineWidth(1)
    ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l)); ctx.strokePath()
}
ctx.restoreGState()

// MARK: Cœur
let cx: CGFloat = 512, cy: CGFloat = 458, sc: CGFloat = 20.5

func heartPoint(_ t: CGFloat, scale k: CGFloat = 1) -> CGPoint {
    let x = 16 * pow(sin(t), 3)
    let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
    return CGPoint(x: cx + x * sc * k, y: cy - y * sc * k)
}

func heartPath(scale k: CGFloat = 1, steps: Int = 240) -> CGPath {
    let p = CGMutablePath()
    for i in 0...steps {
        let pt = heartPoint(CGFloat(i) / CGFloat(steps) * 2 * .pi, scale: k)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

let reds: [UInt32] = [0xe5131d, 0xf0262b, 0xd20f19, 0xff3a3a, 0xc40d17]

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
ctx.setLineCap(.round); ctx.setLineJoin(.round)

// remplissage au crayon : plusieurs passes de traits courbes dans des directions différentes
ctx.saveGState()
ctx.addPath(heartPath(scale: 1.01)); ctx.clip()
for (angle, spacing, width) in [(CGFloat(-0.55), CGFloat(8), CGFloat(9)),
                                (CGFloat(0.62), CGFloat(11), CGFloat(8)),
                                (CGFloat(-1.25), CGFloat(15), CGFloat(7)),
                                (CGFloat(0.05), CGFloat(20), CGFloat(6))] {
    let d = CGPoint(x: cos(angle), y: sin(angle)), n = CGPoint(x: -sin(angle), y: cos(angle))
    var k: CGFloat = -560
    var flip = false
    while k < 560 {
        let off = k + rng.range(-3, 3)
        let a = CGPoint(x: cx + d.x * -520 + n.x * off, y: cy + 40 + d.y * -520 + n.y * off)
        let b = CGPoint(x: cx + d.x * 520 + n.x * (off + rng.range(-10, 10)), y: cy + 40 + d.y * 520 + n.y * (off + rng.range(-10, 10)))
        let mid = CGPoint(x: (a.x + b.x) / 2 + n.x * rng.range(-14, 14), y: (a.y + b.y) / 2 + n.y * rng.range(-14, 14))
        ctx.setStrokeColor(color(reds[Int(rng.range(0, CGFloat(reds.count)))], rng.range(0.7, 0.95)))
        ctx.setLineWidth(width * rng.range(0.7, 1.2))
        ctx.move(to: flip ? b : a)
        ctx.addQuadCurve(to: flip ? a : b, control: mid)
        ctx.strokePath()
        flip.toggle()
        k += spacing * rng.range(0.7, 1.3)
    }
}
// éclats de papier qui percent à travers le rouge
for _ in 0..<420 {
    let x = rng.range(180, 850), y = rng.range(200, 820), a = rng.range(-1, 1), l = rng.range(6, 26)
    ctx.setStrokeColor(color(0xffffff, rng.range(0.06, 0.22))); ctx.setLineWidth(rng.range(1, 2.6))
    ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l)); ctx.strokePath()
}
ctx.restoreGState()

// contour griffonné : plusieurs tours un peu décalés
for pass in 0..<4 {
    let k = 1.0 + CGFloat(pass - 1) * 0.012
    ctx.setStrokeColor(color(reds[pass % reds.count], 0.92))
    ctx.setLineWidth(rng.range(7, 11))
    var first = true
    let steps = 90
    let start = rng.range(0, 2 * .pi)
    for i in 0...(steps + 3) {
        var pt = heartPoint(start + CGFloat(i) / CGFloat(steps) * 2 * .pi, scale: k)
        pt.x += rng.range(-5, 5); pt.y += rng.range(-5, 5)
        if first { ctx.move(to: pt); first = false } else { ctx.addLine(to: pt) }
    }
    ctx.strokePath()
}
ctx.restoreGState()

// MARK: Prise blanche (feutre) à la place des lettres
func rough(_ pts: [CGPoint], amp: CGFloat) -> [CGPoint] {
    pts.map { CGPoint(x: $0.x + rng.range(-amp, amp), y: $0.y + rng.range(-amp, amp)) }
}

func densify(_ pts: [CGPoint], step: CGFloat) -> [CGPoint] {
    var out: [CGPoint] = []
    for i in 0..<pts.count {
        let p = pts[i], q = pts[(i + 1) % pts.count]
        let n = max(1, Int(hypot(q.x - p.x, q.y - p.y) / step))
        for j in 0..<n {
            let t = CGFloat(j) / CGFloat(n)
            out.append(CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t))
        }
    }
    return out
}

func roundedRectPoints(_ r: CGRect, radius: CGFloat, step: CGFloat = 14) -> [CGPoint] {
    let rr = min(radius, r.width / 2, r.height / 2)
    let centers: [CGPoint] = [CGPoint(x: r.maxX - rr, y: r.minY + rr), CGPoint(x: r.maxX - rr, y: r.maxY - rr),
                              CGPoint(x: r.minX + rr, y: r.maxY - rr), CGPoint(x: r.minX + rr, y: r.minY + rr)]
    var pts: [CGPoint] = []
    for (idx, c) in centers.enumerated() {
        let a0 = -CGFloat.pi / 2 + CGFloat(idx) * CGFloat.pi / 2
        for i in 0...6 {
            let a = a0 + CGFloat(i) / 6 * CGFloat.pi / 2
            pts.append(CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr))
        }
    }
    return densify(pts, step: step)
}

func drawMarker(_ pts: [CGPoint], width: CGFloat, closed: Bool = false) {
    guard let f = pts.first else { return }
    ctx.setStrokeColor(color(0xfffdf8)); ctx.setLineWidth(width)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: f)
    for p in pts.dropFirst() { ctx.addLine(to: p) }
    if closed { ctx.closePath() }
    ctx.strokePath()
}

func fillMarker(_ pts: [CGPoint]) {
    guard let f = pts.first else { return }
    ctx.setFillColor(color(0xfffdf8))
    ctx.move(to: f)
    for p in pts.dropFirst() { ctx.addLine(to: p) }
    ctx.closePath(); ctx.fillPath()
}

// fiches
for x in [CGFloat(452), CGFloat(572)] {
    let r = CGRect(x: x - 19, y: 346, width: 38, height: 96)
    let pts = roundedRectPoints(r, radius: 4)
    fillMarker(rough(pts, amp: 1.5)); drawMarker(rough(pts, amp: 2.5), width: 11, closed: true)
}
// corps
let bodyR = CGRect(x: 380, y: 432, width: 264, height: 156)
let bodyPts = roundedRectPoints(bodyR, radius: 50)
fillMarker(rough(bodyPts, amp: 1.5))
drawMarker(rough(bodyPts, amp: 3), width: 12, closed: true)
drawMarker(rough(bodyPts, amp: 3), width: 8, closed: true)
// câble en S
func bezier(_ t: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGPoint {
    let u = 1 - t
    let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
    let x: CGFloat = w0 * p0.x + w1 * p1.x + w2 * p2.x + w3 * p3.x
    let y: CGFloat = w0 * p0.y + w1 * p1.y + w2 * p2.y + w3 * p3.y
    return CGPoint(x: x, y: y)
}
var cable: [CGPoint] = []
for i in 0...40 {
    cable.append(bezier(CGFloat(i) / 40, CGPoint(x: 512, y: 585), CGPoint(x: 512, y: 665),
                        CGPoint(x: 604, y: 610), CGPoint(x: 548, y: 696)))
}
drawMarker(rough(cable, amp: 1.5), width: 30)
drawMarker(rough(cable, amp: 2.5), width: 22)

// petit « clin d'œil » dessiné : un œil fermé et un point sur le corps
ctx.setStrokeColor(color(0xe5131d)); ctx.setLineCap(.round); ctx.setLineWidth(10)
let eye = CGMutablePath()
eye.addArc(center: CGPoint(x: 588, y: 506), radius: 24, startAngle: .pi * 1.1, endAngle: .pi * 1.9, clockwise: false)
ctx.addPath(eye); ctx.strokePath()
ctx.setFillColor(color(0xe5131d))
ctx.fillEllipse(in: CGRect(x: 446 - 13, y: 502 - 15, width: 26, height: 30))
let smile = CGMutablePath()
smile.move(to: CGPoint(x: 462, y: 548))
smile.addQuadCurve(to: CGPoint(x: 568, y: 546), control: CGPoint(x: 515, y: 584))
ctx.setLineWidth(9); ctx.addPath(smile); ctx.strokePath()

// MARK: Export
let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("→ \(outPath)")
