import AppKit
import GrokStatusCore

enum GrokMarkImage {
    static let pointSize = NSSize(width: 36, height: 22)

    static func make(
        appearance: NSAppearance,
        scale: CGFloat = 2,
        pose: IconPose,
        cometStyle: CometStyle = .current
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
            let showComet = pose.comet > 0.015
            if showComet, cometStyle == .orbit3D {
                drawOrbit3D(in: rect, time: pose.cometTime, strength: pose.comet, behind: true)
            }
            drawMark(
                in: rect,
                scale: pose.pulseScale,
                alpha: pose.pulseAlpha,
                yOffset: pose.bounceY
            )
            if showComet {
                switch cometStyle {
                case .planar:
                    drawCometPlanar(in: rect, time: pose.cometTime, strength: pose.comet)
                case .orbit3D:
                    drawOrbit3D(in: rect, time: pose.cometTime, strength: pose.comet, behind: false)
                }
            }
        }

        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private static func drawMark(
        in rect: NSRect,
        scale: CGFloat = 1,
        alpha: CGFloat = 1,
        yOffset: CGFloat = 0
    ) {
        let markBox = NSRect(x: rect.midX - 11, y: rect.minY, width: 22, height: 22)
        var dest = markBox.insetBy(dx: 1.25, dy: 1.25)
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

    private static func drawCometPlanar(in rect: NSRect, time: TimeInterval, strength: CGFloat) {
        let samples = orbitSamples(in: rect, time: time, incline: false)
        guard samples.count > 1 else { return }
        for i in 1..<samples.count {
            let a = samples[i - 1]
            let b = samples[i]
            let u = (a.u + b.u) / 2
            let alpha = pow(1 - u, 1.45) * strength
            if alpha < 0.03 { continue }
            let path = NSBezierPath()
            path.move(to: a.point)
            path.line(to: b.point)
            path.lineCapStyle = .round
            path.lineWidth = 1.7 - 1.05 * u
            NSColor.black.withAlphaComponent(alpha).setStroke()
            path.stroke()
        }
    }

    private struct OrbitSample {
        var point: CGPoint
        var z: CGFloat
        var scale: CGFloat
        var u: CGFloat
    }

    /// Inclined eccentric orbit. `behind` draws only the far side (under the mark, visible in the slash).
    private static func drawOrbit3D(
        in rect: NSRect,
        time: TimeInterval,
        strength: CGFloat,
        behind: Bool
    ) {
        let samples = orbitSamples(in: rect, time: time, incline: true)
        guard samples.count > 1 else { return }

        for i in 1..<samples.count {
            let a = samples[i - 1]
            let b = samples[i]
            let midZ = (a.z + b.z) / 2
            let isBehind = midZ <= 0
            if behind != isBehind { continue }

            let u = (a.u + b.u) / 2
            let depth = min(1, max(0, (midZ + 8) / 16))
            let occluded: CGFloat = behind ? 0.7 : 1
            // Same taper as planar; depth only tints it, so the tail stays readable.
            let alpha = pow(1 - u, 1.45) * strength * occluded * (0.72 + 0.28 * depth)
            if alpha < 0.03 { continue }

            let width = (1.7 - 1.0 * u) * (0.38 + 0.62 * (a.scale + b.scale) / 2)
            let path = NSBezierPath()
            path.move(to: a.point)
            path.line(to: b.point)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.lineWidth = width
            NSColor.black.withAlphaComponent(alpha).setStroke()
            path.stroke()
        }

        if !behind, let head = samples.first, head.z > 0 {
            let r = 0.55 * head.scale + 0.35
            let dot = NSRect(
                x: head.point.x - r,
                y: head.point.y - r,
                width: r * 2,
                height: r * 2
            )
            NSColor.black.withAlphaComponent(strength).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    private static func orbitSamples(in rect: NSRect, time: TimeInterval, incline: Bool) -> [OrbitSample] {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2 - 1.6
        let ry = rect.height / 2 - 2.6
        let head = time * 2.35 + 0.42 * sin(time * 1.85)
        let tailSweep = incline
            ? 1.85 + 0.4 * sin(time * 1.15)
            : 0.85 + 0.35 * sin(time * 1.15)
        let inclination = incline ? 1.02 : 0.0
        let yaw: CGFloat = incline ? -0.55 : 0
        let eccentricity = incline ? 0.34 : 0.12
        let posFocal: CGFloat = 42
        let sizeFocal: CGFloat = 13
        let count = incline ? 64 : 28

        var samples: [OrbitSample] = []
        samples.reserveCapacity(count)
        for i in 0..<count {
            let u = CGFloat(i) / CGFloat(count - 1)
            let theta = head - Double(u) * tailSweep
            let rScale = 1 - eccentricity * sin(theta)
            let x0 = rx * rScale * cos(theta)
            let y0 = ry * rScale * sin(theta)
            let y1 = y0 * cos(inclination)
            let z = incline ? y0 * sin(inclination) : 0
            let x = x0 * cos(yaw) - y1 * sin(yaw)
            let y = x0 * sin(yaw) + y1 * cos(yaw)

            let posPersp = posFocal / max(posFocal - z, 16)
            let sizePersp = sizeFocal / max(sizeFocal - z, 8)
            samples.append(
                OrbitSample(
                    point: CGPoint(x: center.x + x * posPersp, y: center.y + y * posPersp),
                    z: z,
                    scale: sizePersp,
                    u: u
                )
            )
        }
        return samples
    }
}
