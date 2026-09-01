import AppKit
import GrokStatusCore
import QuartzCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private var light: TrafficLight = .inactive
    private var motion = IconMotion()
    private var appearanceObserver: NSKeyValueObservation?
    private var displayLink: CADisplayLink?
    private var fallbackTimer: Timer?
    private var loginSwitch: AppleSwitch?
    private var showSessionItem: NSMenuItem?
    private var pendingShowSession = false

    override init() {
        item = NSStatusBar.system.statusItem(withLength: GrokMarkImage.pointSize.width)
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(makeShowSessionItem())
        menu.addItem(.separator())
        menu.addItem(makeLoginMenuItem())
        menu.addItem(.separator())
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        showSessionItem?.isEnabled = SessionFocus.hasLiveSession()
        syncLoginSwitch()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard pendingShowSession else { return }
        pendingShowSession = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            if !(await SessionFocus.bringSessionToFront()) {
                NSSound.beep()
            }
        }
    }

    private func makeShowSessionItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Show Session",
            action: #selector(showSession),
            keyEquivalent: ""
        )
        item.target = self
        showSessionItem = item
        return item
    }

    @objc private func showSession() {
        pendingShowSession = true
    }

    private func makeLoginMenuItem() -> NSMenuItem {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 252, height: 32))
        let label = NSTextField(labelWithString: "Start on login")
        label.font = NSFont.menuFont(ofSize: 0)
        label.frame = NSRect(x: 14, y: 6, width: 168, height: 20)
        let toggle = AppleSwitch(frame: NSRect(x: 198, y: 4, width: 40, height: 24))
        toggle.target = self
        toggle.action = #selector(toggleLogin(_:))
        toggle.setAccessibilityLabel("Start on login")
        row.addSubview(label)
        row.addSubview(toggle)
        loginSwitch = toggle

        let item = NSMenuItem()
        item.view = row
        return item
    }

    @objc private func toggleLogin(_ sender: AppleSwitch) {
        do {
            try LoginItem.setEnabled(sender.state == .on)
        } catch {
            NSSound.beep()
        }
        syncLoginSwitch()
    }

    private func syncLoginSwitch() {
        let installed = LoginItem.isInstalledInApplications
        loginSwitch?.isEnabled = installed
        loginSwitch?.setOn(LoginItem.isEnabled, animated: false)
        loginSwitch?.toolTip = installed
            ? nil
            : "Install Grok Status to the Applications folder to enable this."
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
