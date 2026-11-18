// 生成 Better Wacom 的 App 图标：白色圆角方块 + 单线圆角 w（与板子字标同一风格）
// 用法：swift scripts/make_icon.swift <输出目录>.iconset
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

/// w 的中心线（字高 1，原点左上、y 向下），与 Logo.swift 中 Glyphs 一致
func wPath(origin: CGPoint, h: CGFloat, flippedHeight H: CGFloat) -> NSBezierPath {
    let W: CGFloat = 1.26, e: CGFloat = 0.07, r: CGFloat = 0.36, mid = W / 2
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * h, y: H - (origin.y + y * h)) }
    let p = NSBezierPath()
    for (a, b) in [(e, mid), (mid, W - e)] {
        p.move(to: P(a, e))
        p.line(to: P(a, 1 - e - r))
        p.curve(to: P(a + r, 1 - e), controlPoint1: P(a, 1 - e), controlPoint2: P(a, 1 - e))
        p.line(to: P(b - r, 1 - e))
        p.curve(to: P(b, 1 - e - r), controlPoint1: P(b, 1 - e), controlPoint2: P(b, 1 - e))
        p.line(to: P(b, e))
    }
    return p
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 100 / 1024
    let box = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = box.width * 0.225
    let shape = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.white.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(white: 1, alpha: 1), NSColor(white: 0.90, alpha: 1)])!.draw(in: shape, angle: -90)
    NSColor.black.withAlphaComponent(0.06).setStroke()
    shape.lineWidth = max(1, s * 0.003)
    shape.stroke()

    let h = box.height * 0.36
    let w = 1.26 * h
    let p = wPath(origin: CGPoint(x: s / 2 - w / 2, y: s / 2 - h / 2), h: h, flippedHeight: s)
    p.lineWidth = h * 0.19
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    NSColor(white: 0.07, alpha: 1).setStroke()
    p.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                   ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("ok")
