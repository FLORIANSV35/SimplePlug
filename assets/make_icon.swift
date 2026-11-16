// Generates assets/icon-1024.png: "SIMPLE / PLUG" in brushed graffiti lettering, black on paper,
// inside a brush circle with drips (a wink at the world of "Simple Plan").
// The letters are drawn here stroke by stroke (original lettering), fixed random seed.
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

struct RNG {
    var state: UInt64 = 0x5eed_9876_cafe
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
let ink = color(0x0e0d0f)
let paperHex: UInt32 = 0xf4f2ed

// MARK: Paper
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 188, cornerHeight: 188, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x000000, 0.4))
ctx.setFillColor(color(paperHex))
ctx.addPath(tilePath); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
ctx.setFillColor(color(paperHex)); ctx.fill(tile)
for _ in 0..<4200 {
    let x = rng.range(100, 924), y = rng.range(100, 924), r = rng.range(0.6, 2.2)
    ctx.setFillColor(color(rng.next() > 0.5 ? 0xb9b4a8 : 0xffffff, rng.range(0.06, 0.28)))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// MARK: Brush tools
func spline(_ p: [CGPoint], samples: Int = 14) -> [CGPoint] {
    guard p.count > 2 else { return p }
    var out: [CGPoint] = []
    for i in 0..<(p.count - 1) {
        let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, p.count - 1)]
        for s in 0..<samples {
            let t = CGFloat(s) / CGFloat(samples), t2 = t * t, t3 = t2 * t
            let x0 = 2 * p1.x
            let x1 = (p2.x - p0.x) * t
            let x2 = (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
            let x3 = (3 * p1.x - p0.x - 3 * p2.x + p3.x) * t3
            let y0 = 2 * p1.y
            let y1 = (p2.y - p0.y) * t
            let y2 = (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
            let y3 = (3 * p1.y - p0.y - 3 * p2.y + p3.y) * t3
            out.append(CGPoint(x: 0.5 * (x0 + x1 + x2 + x3), y: 0.5 * (y0 + y1 + y2 + y3)))
        }
    }
    out.append(p.last!)
    return out
}

func lineSamples(_ p: [CGPoint], step: CGFloat = 2) -> [CGPoint] {
    var out: [CGPoint] = []
    for i in 0..<(p.count - 1) {
        let a = p[i], b = p[i + 1]
        let n = max(1, Int(hypot(b.x - a.x, b.y - a.y) / step))
        for j in 0..<n {
            let t = CGFloat(j) / CGFloat(n)
            out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
    }
    out.append(p.last!)
    return out
}

/// Draws a line with a tilted flat brush: variable thickness, uneven edges.
func brush(_ pts: [CGPoint], width: CGFloat, taper: Bool = false) {
    let dense = lineSamples(pts, step: 1.6)
    let n = dense.count
    for (i, p) in dense.enumerated() {
        var w = width
        if taper {
            let t = CGFloat(i) / CGFloat(max(n - 1, 1))
            w *= pow(sin(CGFloat.pi * t), 0.55)
        }
        w *= rng.range(0.9, 1.1)
        ctx.saveGState()
        ctx.translateBy(x: p.x + rng.range(-1.2, 1.2), y: p.y + rng.range(-1.2, 1.2))
        ctx.rotate(by: -0.62)
        ctx.setFillColor(ink)
        ctx.fillEllipse(in: CGRect(x: -w * 0.55, y: -w * 0.3, width: w * 1.1, height: w * 0.6))
        ctx.restoreGState()
    }
    // dry brush: thin paper streaks along the stroke
    if width > 14 {
        for _ in 0..<(n / 14) {
            let s = Int(rng.range(0, CGFloat(n - 2)))
            let len = Int(rng.range(8, 40))
            let off = rng.range(-width * 0.3, width * 0.3)
            ctx.setStrokeColor(color(paperHex, rng.range(0.2, 0.5)))
            ctx.setLineWidth(rng.range(0.8, 2.2)); ctx.setLineCap(.round)
            var started = false
            for k in s..<min(s + len, n - 1) {
                let a = dense[k], b = dense[k + 1]
                let dx = b.x - a.x, dy = b.y - a.y
                let l = max(hypot(dx, dy), 0.001)
                let q = CGPoint(x: a.x - dy / l * off, y: a.y + dx / l * off)
                if !started { ctx.move(to: q); started = true } else { ctx.addLine(to: q) }
            }
            ctx.strokePath()
        }
    }
}

// MARK: Letters (coordinates u: 0…0.8, v: 0 top … 1 bottom)
struct Glyph { var strokes: [[CGPoint]]; var smooth: Bool }
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

let glyphs: [Character: Glyph] = [
    "S": Glyph(strokes: [[P(0.74, 0.14), P(0.46, 0.0), P(0.12, 0.12), P(0.14, 0.38), P(0.46, 0.5), P(0.72, 0.62), P(0.7, 0.88), P(0.4, 1.0), P(0.04, 0.86)]], smooth: true),
    "I": Glyph(strokes: [[P(0.38, 0.0), P(0.4, 1.0)]], smooth: false),
    "M": Glyph(strokes: [[P(0.04, 1.0), P(0.1, 0.0), P(0.4, 0.62), P(0.7, 0.0), P(0.78, 1.0)]], smooth: false),
    "P": Glyph(strokes: [[P(0.1, 1.0), P(0.12, 0.0), P(0.5, 0.04), P(0.7, 0.24), P(0.5, 0.5), P(0.12, 0.52)]], smooth: true),
    "L": Glyph(strokes: [[P(0.1, 0.0), P(0.1, 1.0), P(0.74, 0.98)]], smooth: false),
    "E": Glyph(strokes: [[P(0.72, 0.02), P(0.1, 0.0), P(0.1, 1.0), P(0.74, 0.98)], [P(0.1, 0.5), P(0.56, 0.5)]], smooth: false),
    "U": Glyph(strokes: [[P(0.1, 0.0), P(0.14, 0.78), P(0.4, 1.0), P(0.66, 0.78), P(0.72, 0.0)]], smooth: true),
    "G": Glyph(strokes: [[P(0.72, 0.16), P(0.42, 0.0), P(0.1, 0.22), P(0.08, 0.78), P(0.4, 1.0), P(0.72, 0.84), P(0.72, 0.56), P(0.46, 0.56)]], smooth: true),
]

var drips: [(CGPoint, CGFloat)] = []

func drawWord(_ word: String, centerX: CGFloat, top: CGFloat, height H: CGFloat, penScale: CGFloat,
              dripChance: CGFloat, dripMax: CGFloat) {
    let pitch = H * 0.80
    let total = pitch * CGFloat(word.count)
    var x0 = centerX - total / 2
    for ch in word {
        guard let g = glyphs[ch] else { x0 += pitch; continue }
        let rot = rng.range(-0.05, 0.05), dy = rng.range(-H * 0.035, H * 0.035), sc = rng.range(0.95, 1.05)
        let cxg = x0 + H * 0.4, cyg = top + H / 2 + dy
        func map(_ p: CGPoint) -> CGPoint {
            // italic + rotation + scale specific to each letter
            let lx = (p.x - 0.4) * H * sc + (0.5 - p.y) * H * 0.16
            let ly = (p.y - 0.5) * H * sc
            let c = cos(rot), s = sin(rot)
            return CGPoint(x: cxg + lx * c - ly * s, y: cyg + lx * s + ly * c)
        }
        for stroke in g.strokes {
            let mapped = stroke.map(map)
            brush(g.smooth ? spline(mapped) : mapped, width: H * penScale)
        }
        // possible drip under the letter
        if rng.next() < dripChance, let base = g.strokes.flatMap({ $0 }).max(by: { $0.y < $1.y }) {
            drips.append((map(P(base.x + rng.range(-0.05, 0.05), 1.0)), rng.range(30, dripMax)))
        }
        x0 += pitch
    }
}

// MARK: Brush circle (cut at the top and bottom like a stamp)
func ringArc(center: CGPoint, radius: CGFloat, from a0: CGFloat, to a1: CGFloat, width: CGFloat) {
    var pts: [CGPoint] = []
    let steps = 90
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let a = a0 + (a1 - a0) * t
        let r = radius + sin(t * 9) * 3 + rng.range(-1.5, 1.5)
        pts.append(CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r))
    }
    brush(pts, width: width, taper: true)
}
let ringC = CGPoint(x: 512, y: 512)
ringArc(center: ringC, radius: 362, from: CGFloat.pi * 1.10, to: CGFloat.pi * 1.90, width: 46)   // top
ringArc(center: ringC, radius: 362, from: CGFloat.pi * 0.10, to: CGFloat.pi * 0.90, width: 46)   // bottom

// MARK: Text
drawWord("SIMPLE", centerX: 508, top: 336, height: 112, penScale: 0.25, dripChance: 0.2, dripMax: 44)
drawWord("PLUG", centerX: 512, top: 508, height: 148, penScale: 0.25, dripChance: 0.6, dripMax: 120)

// Drips
for (p, len) in drips {
    let w = rng.range(7, 11)
    ctx.setStrokeColor(ink); ctx.setLineCap(.round); ctx.setLineWidth(w)
    ctx.move(to: p); ctx.addLine(to: CGPoint(x: p.x + rng.range(-2, 2), y: p.y + len)); ctx.strokePath()
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: p.x - w * 0.9, y: p.y + len - w * 0.6, width: w * 1.8, height: w * 2.0))
}
// Splatters
for _ in 0..<70 {
    let a = rng.range(0, 2 * CGFloat.pi), r = rng.range(250, 420)
    let x = 512 + cos(a) * r, y = 512 + sin(a) * r * 0.95
    let d = rng.range(1.5, 6.5)
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: x - d, y: y - d, width: d * 2, height: d * 2))
}
ctx.restoreGState()

// MARK: Export
let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("→ \(outPath)")
