import Foundation
import GrokStatusCore

struct IconPose {
    var comet: CGFloat
    var cometTime: TimeInterval
    var bounceY: CGFloat
    var pulseScale: CGFloat
    var pulseAlpha: CGFloat
}

struct IconMotion {
    private var comet: CGFloat = 0
    private var bounceY: CGFloat = 0
    private var pulseScale: CGFloat = 1
    private var pulseAlpha: CGFloat = 1
    private var bounceClock: TimeInterval = 0
    private var pulseClock: TimeInterval = 0
    private var cometClock: TimeInterval = 0
    private var lastTime: TimeInterval?
    private var wasWaiting = false
    private var wasCompleted = false

    var pose: IconPose {
        IconPose(
            comet: comet,
            cometTime: cometClock,
            bounceY: bounceY,
            pulseScale: pulseScale,
            pulseAlpha: pulseAlpha
        )
    }

    var isSettling: Bool {
        comet > 0.02
            || abs(bounceY) > 0.12
            || abs(pulseScale - 1) > 0.01
            || abs(pulseAlpha - 1) > 0.02
    }

    mutating func advance(light: TrafficLight, now: TimeInterval) {
        let dt = min(now - (lastTime ?? now), 1.0 / 20.0)
        lastTime = now

        let running = light == .running
        let waiting = light == .waitingForInput
        let completed = light == .completed

        if waiting, !wasWaiting { bounceClock = 0 }
        if completed, !wasCompleted { pulseClock = 0 }
        wasWaiting = waiting
        wasCompleted = completed

        comet = mix(comet, running ? 1 : 0, tau: 0.2, dt: dt)

        if running || comet > 0.02 {
            cometClock += dt
        }

        if waiting {
            bounceClock += dt
            bounceY = mix(bounceY, dockBounce(bounceClock), tau: 0.05, dt: dt)
        } else {
            bounceY = mix(bounceY, 0, tau: 0.14, dt: dt)
        }

        if completed {
            pulseClock += dt
            let pulse = breathe(pulseClock)
            pulseScale = mix(pulseScale, pulse.scale, tau: 0.1, dt: dt)
            pulseAlpha = mix(pulseAlpha, pulse.alpha, tau: 0.1, dt: dt)
        } else {
            pulseScale = mix(pulseScale, 1, tau: 0.16, dt: dt)
            pulseAlpha = mix(pulseAlpha, 1, tau: 0.16, dt: dt)
        }
    }

    private func mix(_ current: CGFloat, _ target: CGFloat, tau: TimeInterval, dt: TimeInterval) -> CGFloat {
        if dt <= 0 { return current }
        let k = 1 - CGFloat(exp(-dt / tau))
        return current + (target - current) * k
    }

    private func dockBounce(_ time: TimeInterval) -> CGFloat {
        let cycle: TimeInterval = 1.7
        let window: TimeInterval = 0.78
        let t = time.truncatingRemainder(dividingBy: cycle)
        if t >= window { return 0 }
        let u = t / window
        return 3.4 * abs(sin(u * .pi * 2.6)) * exp(-2.5 * u)
    }

    private func breathe(_ time: TimeInterval) -> (scale: CGFloat, alpha: CGFloat) {
        let wave = 0.5 + 0.5 * sin(time * 3.5 - .pi / 2)
        let peak = pow(max(0, wave), 1.4)
        return (1 + 0.11 * peak, 1 - 0.62 * peak)
    }
}
