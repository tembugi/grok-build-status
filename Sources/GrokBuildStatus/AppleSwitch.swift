import AppKit
import QuartzCore

/// Capsule switch with the iOS / macOS on-fill (system blue).
/// NSSwitch inside an NSMenu is restyled by the menu material and can lose that blue.
final class AppleSwitch: NSControl {
    /// Default macOS / classic iOS switch-on fill (#007AFF).
    private static let onBlue = NSColor(srgbRed: 0, green: 0.4784313725, blue: 1, alpha: 1)

    private var isOn = false
    private var knob: CGFloat = 0
    private var anim: Timer?
    private var animStart: CGFloat = 0
    private var animTarget: CGFloat = 0
    private var animT0: CFTimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isEnabled = true
        setAccessibilityRole(.checkBox)
        setAccessibilityRoleDescription("switch")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 24) }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    var state: NSControl.StateValue {
        get { isOn ? .on : .off }
        set { setOn(newValue != .off, animated: false) }
    }

    func setOn(_ on: Bool, animated: Bool) {
        isOn = on
        let target: CGFloat = on ? 1 : 0
        anim?.invalidate()
        anim = nil
        if !animated || abs(knob - target) < 0.001 {
            knob = target
            needsDisplay = true
            return
        }
        animStart = knob
        animTarget = target
        animT0 = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tickAnim), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        anim = timer
    }

    @objc private func tickAnim() {
        let u = min(1, (CACurrentMediaTime() - animT0) / 0.18)
        let eased = 1 - pow(1 - u, 3)
        knob = animStart + (animTarget - animStart) * eased
        needsDisplay = true
        if u >= 1 {
            knob = animTarget
            anim?.invalidate()
            anim = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 1, y: 2, width: bounds.width - 2, height: bounds.height - 4)
        let radius = track.height / 2
        let path = NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius)

        let enabled = isEnabled ? 1.0 : 0.45
        NSColor.labelColor.withAlphaComponent(0.25 * enabled).setFill()
        path.fill()
        Self.onBlue.withAlphaComponent(knob * enabled).setFill()
        path.fill()

        let pad: CGFloat = 2
        let d = track.height - pad * 2
        let travel = max(0, track.width - pad * 2 - d)
        let knobRect = NSRect(
            x: track.minX + pad + travel * knob,
            y: track.minY + pad,
            width: d,
            height: d
        )
        NSGraphicsContext.current?.cgContext.setShadow(
            offset: CGSize(width: 0, height: -0.5),
            blur: 1.5,
            color: NSColor.black.withAlphaComponent(0.28).cgColor
        )
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
        NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setOn(!isOn, animated: true)
        sendAction(action, to: target)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityValue() -> Any? {
        isOn ? 1 : 0
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        setOn(!isOn, animated: true)
        sendAction(action, to: target)
        return true
    }
}
