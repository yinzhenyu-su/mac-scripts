import AppKit

// The app icon uses a purple door-and-exit-arrow mark; the menu icon remains a template glyph.
// Run from smart-close/: swift Assets/GenerateIcons.swift

let assetRoot = URL(fileURLWithPath: "SmartClose/Assets.xcassets", isDirectory: true)
let appIconRoot = assetRoot.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
let menuIconRoot = assetRoot.appendingPathComponent("MenuBarIcon.imageset", isDirectory: true)

try FileManager.default.createDirectory(at: appIconRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: menuIconRoot, withIntermediateDirectories: true)

func stroke(_ points: [CGPoint], color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = width
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    color.setStroke()
    path.stroke()
}

func drawExitDoorGlyph(color: NSColor) {
    let frame = NSBezierPath()
    frame.lineCapStyle = .round
    frame.lineJoinStyle = .round
    frame.lineWidth = 58
    frame.move(to: CGPoint(x: 570, y: 786))
    frame.line(to: CGPoint(x: 282, y: 786))
    frame.line(to: CGPoint(x: 282, y: 238))
    frame.line(to: CGPoint(x: 570, y: 238))
    color.setStroke()
    frame.stroke()

    let door = NSBezierPath()
    door.move(to: CGPoint(x: 420, y: 746))
    door.line(to: CGPoint(x: 554, y: 790))
    door.line(to: CGPoint(x: 554, y: 234))
    door.line(to: CGPoint(x: 420, y: 278))
    door.close()
    color.setFill()
    door.fill()

    let arrowEnd = CGPoint(x: 812, y: 512)
    stroke([CGPoint(x: 500, y: 512), arrowEnd], color: color, width: 66)
    stroke([CGPoint(x: 690, y: 632), arrowEnd, CGPoint(x: 690, y: 392)], color: color, width: 66)
}

func renderPNG(size: Int, at url: URL, draw: () -> Void) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "IconGenerator", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGenerator", code: 2)
    }
    try data.write(to: url)
}

func drawAppIcon() {
    let body = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 206, yRadius: 206)
    NSGradient(starting: NSColor(red: 0.66, green: 0.35, blue: 0.98, alpha: 1),
               ending: NSColor(red: 0.32, green: 0.12, blue: 0.78, alpha: 1))!
        .draw(in: body, angle: 135)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    body.lineWidth = 8
    body.stroke()

    drawExitDoorGlyph(color: .white)
}

func drawMenuIcon() {
    // In a template image, opaque black becomes the menu bar's current tint.
    let window = NSBezierPath(roundedRect: NSRect(x: 184, y: 192, width: 540, height: 640), xRadius: 105, yRadius: 105)
    window.lineWidth = 86
    NSColor.black.setStroke()
    window.stroke()
    stroke([CGPoint(x: 232, y: 646), CGPoint(x: 680, y: 646)], color: .black, width: 72)
    stroke([CGPoint(x: 444, y: 446), CGPoint(x: 864, y: 446)], color: .black, width: 94)
    stroke([CGPoint(x: 726, y: 584), CGPoint(x: 864, y: 446), CGPoint(x: 726, y: 308)], color: .black, width: 94)
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    try renderPNG(size: size, at: appIconRoot.appendingPathComponent("icon_\(size).png"), draw: drawAppIcon)
}
for size in [18, 36] {
    try renderPNG(size: size, at: menuIconRoot.appendingPathComponent("menu_\(size).png"), draw: drawMenuIcon)
}
