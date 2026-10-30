// Draws the Lyricscape app icon (a neon constellation on a dark squircle) to a 1024 px PNG.
// Usage: swift scripts/assets/make-icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Squircle background with a deep violet-to-black gradient.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 0.13, green: 0.03, blue: 0.16, alpha: 1),
                                   CGColor(red: 0.02, green: 0.01, blue: 0.04, alpha: 1)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

// Faint background stars.
var seed: UInt64 = 42
func rand() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
for _ in 0..<70 {
    let d = 2 + rand() * 4
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.15 + rand() * 0.35))
    ctx.fillEllipse(in: CGRect(x: rect.minX + rand() * rect.width, y: rect.minY + rand() * rect.height, width: d, height: d))
}

// The constellation: a rising zig-zag, like a melody.
let pink = CGColor(red: 1, green: 0.17, blue: 0.43, alpha: 1)
let core = CGColor(red: 1, green: 0.93, blue: 0.96, alpha: 1)
let stars: [(CGPoint, CGFloat)] = [
    (CGPoint(x: 270, y: 360), 20), (CGPoint(x: 410, y: 520), 26), (CGPoint(x: 540, y: 430), 22),
    (CGPoint(x: 660, y: 640), 34), (CGPoint(x: 770, y: 560), 22),
]
ctx.setShadow(offset: .zero, blur: 28, color: pink)
ctx.setStrokeColor(pink)
ctx.setLineWidth(9)
ctx.setLineCap(.round)
ctx.addLines(between: stars.map(\.0))
ctx.strokePath()
for (point, r) in stars {
    ctx.setShadow(offset: .zero, blur: r * 2.2, color: pink)
    ctx.setFillColor(core)
    ctx.fillEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r))
}
// Four-point glint on the brightest star.
let c = stars[3].0
let glint = CGMutablePath()
for k in 0..<8 {
    let angle = CGFloat(k) * .pi / 4
    let radius: CGFloat = k.isMultiple(of: 2) ? 120 : 12
    let p = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
    if k == 0 { glint.move(to: p) } else { glint.addLine(to: p) }
}
glint.closeSubpath()
ctx.setShadow(offset: .zero, blur: 30, color: pink)
ctx.addPath(glint)
ctx.setFillColor(core)
ctx.fillPath()
ctx.restoreGState()
image.unlockFocus()

let tiff = image.tiffRepresentation!
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
