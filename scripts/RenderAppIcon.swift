import AppKit

/// Renders the official Grok mark into a macOS iconset, then `iconutil` packs it.
@main
enum RenderAppIcon {
    static func main() {
        guard CommandLine.arguments.count >= 2 else {
            fputs("usage: RenderAppIcon <iconset-dir>\n", stderr)
            exit(1)
        }
        let dest = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try? FileManager.default.removeItem(at: dest)
        try! FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        let files: [(name: String, pixels: Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]
        for file in files {
            let image = render(pixels: file.pixels)
            let url = dest.appendingPathComponent(file.name)
            try! image.write(to: url, options: .atomic)
        }
    }

    private static func render(pixels: Int) -> Data {
        let size = CGFloat(pixels)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            fatalError("bitmap")
        }
        rep.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            fatalError("context")
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.shouldAntialias = true
        context.cgContext.setShouldAntialias(true)
        context.cgContext.setAllowsAntialiasing(true)

        let margin = size * (pixels <= 32 ? 0.07 : 100.0 / 1024.0)
        let box = NSRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
        let radius = box.width * 0.223

        drawBackground(in: box, radius: radius)
        let markPad = box.width * (pixels <= 32 ? 0.16 : 0.18)
        drawMark(in: box.insetBy(dx: markPad, dy: markPad))
        drawInnerHighlight(in: box, radius: radius, pixels: pixels)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            fatalError("png")
        }
        return data
    }

    private static func drawBackground(in box: NSRect, radius: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        let space = CGColorSpaceCreateDeviceRGB()
        let colors = [
            NSColor(white: 0.20, alpha: 1).cgColor,
            NSColor(white: 0.05, alpha: 1).cgColor,
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else {
            ctx.restoreGState()
            return
        }
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: box.midX, y: box.maxY),
            end: CGPoint(x: box.midX, y: box.minY),
            options: []
        )
        ctx.restoreGState()
    }

    private static func drawInnerHighlight(in box: NSRect, radius: CGFloat, pixels: Int) {
        guard pixels >= 32 else { return }
        let stroke = max(1, box.width * 0.012)
        let inset = stroke / 2
        let inner = box.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: inner, xRadius: radius - inset, yRadius: radius - inset)
        path.lineWidth = stroke
        NSColor.white.withAlphaComponent(0.10).setStroke()
        path.stroke()
    }

    private static func drawMark(in rect: NSRect) {
        let path = GrokMark.cgPath()
        let bounds = path.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0, rect.width > 0, rect.height > 0 else { return }

        let fit = min(rect.width / bounds.width, rect.height / bounds.height)
        let drawSize = CGSize(width: bounds.width * fit, height: bounds.height * fit)
        let origin = CGPoint(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2
        )
        var transform = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
            .concatenating(CGAffineTransform(scaleX: fit, y: -fit))
            .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y + drawSize.height))
        guard let transformed = path.copy(using: &transform) else { return }
        NSColor.white.setFill()
        NSBezierPath(cgPath: transformed).fill()
    }
}
