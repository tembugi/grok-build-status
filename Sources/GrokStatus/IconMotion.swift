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
    private var bounceVelocity: CGFloat = 0
    private var pulseScale: CGFloat = 1
    private var pulseScaleVelocity: CGFloat = 0
    private var pulseAlpha: CGFloat = 1
    private var pulseAlphaVelocity: CGFloat = 0
    private var pulseClock: TimeInterval = 0
    private var cometClock: TimeInterval = 0
    private var bounceCooldown: TimeInterval = 0
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
            || abs(bounceVelocity) > 2
            || abs(pulseScale - 1) > 0.01
            || abs(pulseAlpha - 1) > 0.02
    }

    mutating func advance(light: TrafficLight, now: TimeInterval, focused: Bool) {
        let dt = min(now - (lastTime ?? now), 1.0 / 20.0)
        lastTime = now

        let running = light == .running
        let waiting = light == .waitingForInput
        let completed = light == .completed
        let attention = waiting && !focused
        let celebrate = completed && !focused

        if waiting, !wasWaiting { bounceCooldown = 0 }
        if completed, !wasCompleted { pulseClock = 0 }
        wasWaiting = waiting
        wasCompleted = completed

        comet = mix(comet, running ? 1 : 0, tau: 0.22, dt: dt)
        if running || comet > 0.02 {
            cometClock += dt
        }

        if attention {
            bounceCooldown -= dt
            let settled = abs(bounceY) < 0.12 && abs(bounceVelocity) < 4
            if bounceCooldown <= 0, settled {
                bounceVelocity = 58
                bounceCooldown = 1.55
            }
            spring(&bounceY, &bounceVelocity, toward: 0, dt: dt, stiffness: 210, damping: 9.5)
        } else {
            spring(&bounceY, &bounceVelocity, toward: 0, dt: dt, stiffness: 170, damping: 18)
        }

        if celebrate {
            pulseClock += dt
            let pulse = breathe(pulseClock)
            spring(&pulseScale, &pulseScaleVelocity, toward: pulse.scale, dt: dt, stiffness: 150, damping: 16)
            spring(&pulseAlpha, &pulseAlphaVelocity, toward: pulse.alpha, dt: dt, stiffness: 150, damping: 16)
        } else {
            spring(&pulseScale, &pulseScaleVelocity, toward: 1, dt: dt, stiffness: 170, damping: 18)
            spring(&pulseAlpha, &pulseAlphaVelocity, toward: 1, dt: dt, stiffness: 170, damping: 18)
        }
    }

    private func mix(_ current: CGFloat, _ target: CGFloat, tau: TimeInterval, dt: TimeInterval) -> CGFloat {
        if dt <= 0 { return current }
        let k = 1 - CGFloat(exp(-dt / tau))
        return current + (target - current) * k
    }

    private func spring(
        _ value: inout CGFloat,
        _ velocity: inout CGFloat,
        toward target: CGFloat,
        dt: TimeInterval,
        stiffness: CGFloat,
        damping: CGFloat
    ) {
        let dt = CGFloat(dt)
        let accel = stiffness * (target - value) - damping * velocity
        velocity += accel * dt
        value += velocity * dt
    }

    private func breathe(_ time: TimeInterval) -> (scale: CGFloat, alpha: CGFloat) {
        let wave = 0.5 + 0.5 * sin(time * 3.5 - .pi / 2)
        let peak = pow(max(0, wave), 1.4)
        return (1 + 0.11 * peak, 1 - 0.62 * peak)
    }
}
