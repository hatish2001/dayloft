import AppKit
import Foundation
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for multiplier in [1, 2] {
        let pixels = points * multiplier
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let frame = NSRect(x: 50, y: 50, width: 924, height: 924)
        let background = NSBezierPath(roundedRect: frame, xRadius: 205, yRadius: 205)
        NSColor(calibratedWhite: 0.025, alpha: 1).setFill(); background.fill()
        NSGradient(colors: [NSColor(calibratedWhite: 0.19, alpha: 1), NSColor(calibratedWhite: 0.025, alpha: 1)])!
            .draw(in: background, relativeCenterPosition: .zero)
        NSColor(calibratedWhite: 0.27, alpha: 1).setStroke(); background.lineWidth = 2; background.stroke()
        context.cgContext.translateBy(x: 512, y: 512)
        context.cgContext.scaleBy(x: 4.9, y: 4.9)
        NSColor.white.setStroke()
        for radius in [23.0, 36.0] {
            let p = NSBezierPath()
            p.appendArc(withCenter: NSPoint(x: 0, y: -5), radius: radius, startAngle: 0, endAngle: 180)
            p.lineWidth = pixels <= 32 ? 2.4 : 1.5; p.lineCapStyle = .round; p.stroke()
        }
        for (width, y) in [(42.0, -15.0), (22.0, -28.0)] {
            let p = NSBezierPath(); p.move(to: NSPoint(x: -width, y: y)); p.line(to: NSPoint(x: width, y: y))
            p.lineWidth = pixels <= 32 ? 2.4 : 1.5; p.lineCapStyle = .round; p.stroke()
        }
        NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: -6, y: 1, width: 12, height: 12)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = multiplier == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/icon_\(points)x\(points)\(suffix).png"))
    }
}
