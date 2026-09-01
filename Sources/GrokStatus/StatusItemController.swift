import AppKit
import GrokStatusCore
import QuartzCore

@MainActor
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private var light: TrafficLight = .inactive
    private var motion = IconMotion()
    private var appearanceObserver: NSKeyValueObservation?
    private var displayLink: CADisplayLink?
    private var fallbackTimer: Timer?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: GrokMarkImage.pointSize.width)
        super.init()

        let menu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit Grok Status",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu

        if let button = item.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
        }

        appearanceObserver = item.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.render()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(focusMayHaveChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        render()
    }

    @objc private func focusMayHaveChanged(_ notification: Notification) {
        render()
    }

    func setLight(_ light: TrafficLight) {
        self.light = light
        if needsDisplayLink {
            startAnimating()
        }
        render()
    }

    private var needsDisplayLink: Bool {
        switch light {
        case .running, .waitingForInput, .completed:
            return true
        default:
            return motion.isSettling
        }
    }

    private func startAnimating() {
        guard displayLink == nil, fallbackTimer == nil else { return }
        if let screen = item.button?.window?.screen ?? NSScreen.main {
            let link = screen.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { self?.render() }
            }
            RunLoop.main.add(timer, forMode: .common)
            fallbackTimer = timer
        }
    }

    private func stopAnimating() {
        displayLink?.invalidate()
        displayLink = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        render()
        if !needsDisplayLink {
            stopAnimating()
        }
    }

    private func render() {
        guard let button = item.button else { return }
        motion.advance(
            light: light,
            now: CACurrentMediaTime(),
            focused: SessionFocus.isGrokSessionFocused()
        )
        let appearance = button.effectiveAppearance
        let scale = button.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        button.image = GrokMarkImage.make(
            appearance: appearance,
            scale: scale,
            pose: motion.pose
        )
        button.toolTip = light.tooltip
        button.setAccessibilityLabel(light.tooltip)
    }
}
