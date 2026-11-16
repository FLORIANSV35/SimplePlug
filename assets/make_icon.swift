// Génère assets/icon-1024.png : une prise qui fait un clin d'œil (clin d'œil à « Simple Plan »).
// Usage : swift assets/make_icon.swift assets/icon-1024.png
import AppKit
import CoreGraphics

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Origine en haut à gauche (comme un écran).
ctx.translateBy(x: 0, y: CGFloat(S))
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255,
                                          CGFloat(hex & 255) / 255, a])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}

func fillLinear(_ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func star(_ c: CGPoint, _ r: CGFloat, _ col: CGColor) {
    let p = CGMutablePath()
    let k = r * 0.22
    p.move(to: CGPoint(x: c.x, y: c.y - r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
    ctx.setFillColor(col); ctx.addPath(p); ctx.fillPath()
}

let ink = color(0x14121a)

// MARK: Fond (carré arrondi façon macOS, 824 px dans la grille de 1024)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 188, cornerHeight: 188, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x000000, 0.45))
ctx.setFillColor(color(0xb3121f))
ctx.addPath(tilePath); ctx.fillPath()
ctx.restoreGState()

fillLinear(tilePath, gradient([(0, color(0xff4756)), (0.55, color(0xe0202e)), (1, color(0x9c0f1b))]),
           from: CGPoint(x: 200, y: 100), to: CGPoint(x: 800, y: 924))

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
// reflet doux en haut à gauche
ctx.drawRadialGradient(gradient([(0, color(0xffffff, 0.32)), (1, color(0xffffff, 0))]),
                       startCenter: CGPoint(x: 330, y: 220), startRadius: 0,
                       endCenter: CGPoint(x: 330, y: 220), endRadius: 520, options: [])
// trame de points (ambiance fanzine punk) dans le coin bas droit
for row in 0..<18 {
    for col in 0..<18 {
        let x = 924 - CGFloat(col) * 34 + (row % 2 == 0 ? 0 : 17)
        let y = 924 - CGFloat(row) * 34
        let d = hypot(924 - x, 924 - y) / 620
        let r = max(0, 11 * (1 - d))
        if r > 0.8 {
            ctx.setFillColor(color(0x000000, 0.16))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }
}
ctx.restoreGState()

// Étincelles
star(CGPoint(x: 205, y: 250), 40, color(0xffffff, 0.95))
star(CGPoint(x: 800, y: 215), 26, color(0xffffff, 0.8))
star(CGPoint(x: 828, y: 560), 20, color(0xffe066, 0.95))
star(CGPoint(x: 190, y: 700), 22, color(0xffe066, 0.9))

// MARK: Mascotte (ombre portée commune)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 22, color: color(0x000000, 0.5))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)

let lw: CGFloat = 16 // épaisseur du contour

// Câble en S qui sort du bas
let cable = CGMutablePath()
cable.move(to: CGPoint(x: 512, y: 640))
cable.addCurve(to: CGPoint(x: 600, y: 770), control1: CGPoint(x: 512, y: 720), control2: CGPoint(x: 700, y: 700))
cable.addCurve(to: CGPoint(x: 430, y: 850), control1: CGPoint(x: 520, y: 830), control2: CGPoint(x: 500, y: 880))
ctx.setLineCap(.round)
ctx.addPath(cable); ctx.setStrokeColor(ink); ctx.setLineWidth(52 + lw); ctx.strokePath()
ctx.addPath(cable); ctx.setStrokeColor(color(0x3a3744)); ctx.setLineWidth(52 - 4); ctx.strokePath()
ctx.addPath(cable); ctx.setStrokeColor(color(0x55515f)); ctx.setLineWidth(12)
ctx.setLineCap(.round); ctx.strokePath()

// Fiches métalliques
for dx in [-92.0, 92.0] {
    let prong = CGPath(roundedRect: CGRect(x: 512 + dx - 36, y: 150, width: 72, height: 200),
                       cornerWidth: 16, cornerHeight: 16, transform: nil)
    fillLinear(prong, gradient([(0, color(0xf4f4f8)), (0.5, color(0xc9cad3)), (1, color(0x8d8e99))]),
               from: CGPoint(x: 512 + dx - 36, y: 0), to: CGPoint(x: 512 + dx + 36, y: 0))
    ctx.addPath(prong); ctx.setStrokeColor(ink); ctx.setLineWidth(lw); ctx.strokePath()
}

// Corps de la prise
let body = CGPath(roundedRect: CGRect(x: 292, y: 320, width: 440, height: 330), cornerWidth: 110, cornerHeight: 110, transform: nil)
fillLinear(body, gradient([(0, color(0xffffff)), (1, color(0xe3e3ec))]),
           from: CGPoint(x: 512, y: 320), to: CGPoint(x: 512, y: 650))
ctx.addPath(body); ctx.setStrokeColor(ink); ctx.setLineWidth(lw); ctx.strokePath()

// Joues
ctx.setFillColor(color(0xff6b81, 0.55))
ctx.fillEllipse(in: CGRect(x: 330, y: 500, width: 56, height: 34))
ctx.fillEllipse(in: CGRect(x: 638, y: 500, width: 56, height: 34))

// Œil gauche ouvert
ctx.setFillColor(ink)
ctx.fillEllipse(in: CGRect(x: 380 - 40, y: 440 - 46, width: 80, height: 92))
ctx.setFillColor(color(0xffffff))
ctx.fillEllipse(in: CGRect(x: 380 - 4, y: 440 - 30, width: 26, height: 26))

// Œil droit : clin d'œil
let wink = CGMutablePath()
wink.addArc(center: CGPoint(x: 644, y: 470), radius: 44, startAngle: .pi * 1.12, endAngle: .pi * 1.88, clockwise: false)
ctx.setLineCap(.round)
ctx.addPath(wink); ctx.setStrokeColor(ink); ctx.setLineWidth(24); ctx.strokePath()

// Sourire en coin + langue
let tongue = CGPath(ellipseIn: CGRect(x: 548, y: 536, width: 70, height: 84), transform: nil)
ctx.setFillColor(color(0xff5d7a)); ctx.addPath(tongue); ctx.fillPath()
ctx.addPath(tongue); ctx.setStrokeColor(ink); ctx.setLineWidth(10); ctx.strokePath()
ctx.setStrokeColor(color(0xd93a5a)); ctx.setLineWidth(6)
ctx.move(to: CGPoint(x: 583, y: 560)); ctx.addLine(to: CGPoint(x: 583, y: 596)); ctx.strokePath()

let smile = CGMutablePath()
smile.move(to: CGPoint(x: 422, y: 546))
smile.addCurve(to: CGPoint(x: 640, y: 530), control1: CGPoint(x: 470, y: 606), control2: CGPoint(x: 600, y: 600))
ctx.addPath(smile); ctx.setStrokeColor(ink); ctx.setLineWidth(20); ctx.setLineCap(.round); ctx.strokePath()

ctx.endTransparencyLayer()
ctx.restoreGState()

// Étincelle du clin d'œil
star(CGPoint(x: 730, y: 380), 44, color(0xffffff))
star(CGPoint(x: 730, y: 380), 24, color(0xffe066))

// MARK: Export
let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("→ \(outPath)")
