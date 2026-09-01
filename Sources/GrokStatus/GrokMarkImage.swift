import AppKit
import GrokStatusCore

enum GrokMarkImage {
    static let pointSize = NSSize(width: 22, height: 22)

    static func make(
        _ light: TrafficLight,
        appearance: NSAppearance,
        scale: CGFloat = 2,
        time: TimeInterval = 0
    ) -> NSImage {
        let scale = max(scale, 1)
        let pixelsWide = Int((pointSize.width * scale).rounded())
        let pixelsHigh = Int((pointSize.height * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: pointSize)
        }
        rep.size = pointSize

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(size: pointSize)
        }
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            let rect = NSRect(origin: .zero, size: pointSize)
            switch light {
            case .running:
                drawMark(in: rect)
                drawComet(in: rect, time: time)
            case .waitingForInput:
                drawMark(in: rect, yOffset: dockBounce(time))
            case .completed:
                let pulse = breathe(time)
                drawMark(in: rect, scale: pulse.scale, alpha: pulse.alpha)
            default:
                drawMark(in: rect)
            }
        }

        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    /// Decaying hops, then a pause — same cadence as a Dock attention bounce.
    private static func dockBounce(_ time: TimeInterval) -> CGFloat {
        let cycle: TimeInterval = 1.7
        let window: TimeInterval = 0.78
        let t = time.truncatingRemainder(dividingBy: cycle)
        if t >= window { return 0 }
        let u = t / window
        return 3.4 * abs(sin(u * .pi * 2.6)) * exp(-2.5 * u)
    }

    private static func breathe(_ time: TimeInterval) -> (scale: CGFloat, alpha: CGFloat) {
        let u = 0.5 + 0.5 * sin(time * 3.5)
        let peak = pow(u, 1.4)
        return (1 + 0.11 * peak, 0.38 + 0.62 * peak)
    }

    private static func drawMark(
        in rect: NSRect,
        scale: CGFloat = 1,
        alpha: CGFloat = 1,
        yOffset: CGFloat = 0
    ) {
        var dest = rect.insetBy(dx: 1.25, dy: 1.25)
        dest.origin.y += yOffset
        if scale != 1 {
            let insetX = dest.width * (1 - scale) / 2
            let insetY = dest.height * (1 - scale) / 2
            dest = dest.insetBy(dx: insetX, dy: insetY)
        }
        guard dest.width > 0, dest.height > 0 else { return }

        let path = GrokMark.cgPath()
        let bounds = path.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return }

        let fit = min(dest.width / bounds.width, dest.height / bounds.height)
        let drawSize = CGSize(width: bounds.width * fit, height: bounds.height * fit)
        let origin = CGPoint(
            x: dest.midX - drawSize.width / 2,
            y: dest.midY - drawSize.height / 2
        )
        let transform = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
            .concatenating(CGAffineTransform(scaleX: fit, y: -fit))
            .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y + drawSize.height))
        var t = transform
        guard let transformed = path.copy(using: &t) else { return }
        let bezier = NSBezierPath(cgPath: transformed)
        NSColor.black.withAlphaComponent(alpha).setFill()
        bezier.fill()
    }

    private static func drawComet(in rect: NSRect, time: TimeInterval) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 1.2
        let head = time * 2.35 + 0.42 * sin(time * 1.85)
        let tailSweep = 0.72 + 0.38 * sin(time * 1.15)

        let steps = 22
        for i in 0..<steps {
            let u = CGFloat(i) / CGFloat(steps)
            let alpha = pow(1 - u, 1.45)
            if alpha < 0.03 { continue }

            let start = head - Double(u) * tailSweep
            let end = head - Double(u + 1 / CGFloat(steps)) * tailSweep
            let path = NSBezierPath()
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: degrees(start),
                endAngle: degrees(end),
                clockwise: true
            )
            path.lineCapStyle = .round
            path.lineWidth = 1.7 - 1.05 * u
            NSColor.black.withAlphaComponent(alpha).setStroke()
            path.stroke()
        }
    }

    private static func degrees(_ radians: Double) -> CGFloat {
        CGFloat(radians * 180 / .pi)
    }
}
