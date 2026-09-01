import AppKit
import GrokStatusCore

enum GrokMarkImage {
    static let pointSize = NSSize(width: 24, height: 22)

    static func make(
        appearance: NSAppearance,
        scale: CGFloat = 2,
        pose: IconPose
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
            let snap = abs(pose.pulseScale - 1) < 0.02

            if showComet {
                drawOrbitProfessional(in: rect, time: pose.cometTime, strength: pose.comet, behind: true)
                punchMark(in: rect)
            }

            drawMark(
                in: rect,
                scale: pose.pulseScale,
                alpha: pose.pulseAlpha,
                yOffset: pose.bounceY,
                snap: snap
            )

            if showComet {
                drawOrbitProfessional(in: rect, time: pose.cometTime, strength: pose.comet, behind: false)
            }
        }

        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private static func punchMark(in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setBlendMode(.destinationOut)
        drawMark(in: rect, scale: 1, alpha: 1, yOffset: 0, snap: true)
        ctx.restoreGState()
    }

    private static func drawMark(
        in rect: NSRect,
        scale: CGFloat = 1,
        alpha: CGFloat = 1,
        yOffset: CGFloat = 0,
        snap: Bool = false
    ) {
        let side = min(rect.width, 22)
        let markBox = NSRect(x: rect.midX - side / 2, y: rect.minY, width: side, height: 22)
        var dest = markBox.insetBy(dx: 1.25, dy: 1.25)
        dest.origin.y += snap ? yOffset.rounded() : yOffset
        if snap {
            dest.origin.x = dest.origin.x.rounded()
            dest.origin.y = dest.origin.y.rounded()
        }
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

    private struct OrbitSample {
        var point: CGPoint
        var z: CGFloat
        var scale: CGFloat
        var u: CGFloat
    }

    private static func drawOrbitProfessional(
        in rect: NSRect,
        time: TimeInterval,
        strength: CGFloat,
        behind: Bool
    ) {
        let samples = arcLengthSamples(in: rect, time: time)
        guard samples.count > 1 else { return }

        for sample in samples.reversed() {
            let isBehind = sample.z <= 0
            if behind != isBehind { continue }
            var size = sample.scale
            if sample.z < 0 {
                size = size * 0.8 + 0.2
            }
            let depth = min(1, max(0, (sample.z + 8) / 16))
            let alpha = pow(1 - sample.u, 1.7) * strength * (behind ? 0.64 : 1) * (0.78 + 0.22 * depth)
            if alpha < 0.025 { continue }
            let r = (1.05 - 0.62 * sample.u) * (0.42 + 0.58 * size)
            let dot = NSRect(
                x: sample.point.x - r,
                y: sample.point.y - r,
                width: r * 2,
                height: r * 2
            )
            NSColor.black.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }

        if !behind, samples.count > 3, samples[0].z > 0 {
            let head = samples[0]
            for k in 1...3 {
                let s = samples[k]
                let fade = CGFloat(4 - k) / 8
                let r = (0.7 * head.scale + 0.25) * fade
                let dot = NSRect(
                    x: s.point.x - r,
                    y: s.point.y - r,
                    width: r * 2,
                    height: r * 2
                )
                NSColor.black.withAlphaComponent(strength * fade * 0.55).setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
        }
    }

    private static func arcLengthSamples(in rect: NSRect, time: TimeInterval) -> [OrbitSample] {
        let tableSteps = 192
        var table: [(dist: CGFloat, theta: Double)] = []
        table.reserveCapacity(tableSteps + 1)
        var dist: CGFloat = 0
        var prev: CGPoint?
        for i in 0...tableSteps {
            let theta = Double(i) / Double(tableSteps) * 2 * .pi
            let state = orbitState(theta: theta, in: rect)
            if let prev {
                dist += hypot(state.point.x - prev.x, state.point.y - prev.y)
            }
            table.append((dist, theta))
            prev = state.point
        }
        let total = max(table.last?.dist ?? 1, 1)
        let headDist = CGFloat(time) * 30
        var head = headDist.truncatingRemainder(dividingBy: total)
        if head < 0 { head += total }
        let tailLen = total * 0.3
        let count = 80
        var samples: [OrbitSample] = []
        samples.reserveCapacity(count)
        for i in 0..<count {
            let u = CGFloat(i) / CGFloat(count - 1)
            var d = head - u * tailLen
            while d < 0 { d += total }
            let theta = theta(at: d, table: table)
            let state = orbitState(theta: theta, in: rect)
            samples.append(OrbitSample(point: state.point, z: state.z, scale: state.scale, u: u))
        }
        return samples
    }

    private static func theta(at distance: CGFloat, table: [(dist: CGFloat, theta: Double)]) -> Double {
        var lo = 0
        var hi = table.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if table[mid].dist < distance {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let i = max(1, lo)
        let a = table[i - 1]
        let b = table[i]
        let span = b.dist - a.dist
        let t = span > 0 ? (distance - a.dist) / span : 0
        return a.theta + (b.theta - a.theta) * Double(t)
    }

    private static func orbitState(theta: Double, in rect: NSRect) -> (point: CGPoint, z: CGFloat, scale: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2 - 1.6
        let ry = rect.height / 2 - 2.6
        let inclination = 1.02
        let yaw: CGFloat = -0.55
        let eccentricity = 0.34
        let posFocal: CGFloat = 42
        let sizeFocal: CGFloat = 13

        let rScale = 1 - eccentricity * sin(theta)
        let x0 = rx * rScale * cos(theta)
        let y0 = ry * rScale * sin(theta)
        let y1 = y0 * cos(inclination)
        let z = y0 * sin(inclination)
        let x = x0 * cos(yaw) - y1 * sin(yaw)
        let y = x0 * sin(yaw) + y1 * cos(yaw)
        let posPersp = posFocal / max(posFocal - z, 16)
        var sizePersp = sizeFocal / max(sizeFocal - z, 8)
        if z < 0 {
            sizePersp = sizePersp * 0.8 + 0.2
        }
        return (
            CGPoint(x: center.x + x * posPersp, y: center.y + y * posPersp),
            z,
            sizePersp
        )
    }
}
