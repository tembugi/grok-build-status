import AppKit
import GrokStatusCore
import QuartzCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private enum MenuLayout {
        static let width: CGFloat = 252
    }

    private let item: NSStatusItem
    private var light: TrafficLight = .inactive
    private var motion = IconMotion()
    private var appearanceObserver: NSKeyValueObservation?
    private var displayLink: CADisplayLink?
    private var fallbackTimer: Timer?
    private var loginSwitch: AppleSwitch?
    private var showSessionItem: NSMenuItem?
    private var usageTitleField: NSTextField?
    private var usagePercentField: NSTextField?
    private var usageResetField: NSTextField?
    private var usageRow: NSView?
    private var pendingShowSession = false

    override init() {
        item = NSStatusBar.system.statusItem(withLength: GrokMarkImage.pointSize.width)
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        // Session
        menu.addItem(makeShowSessionItem())
        menu.addItem(.separator())
        // Status
        menu.addItem(makeUsageMenuItem())
        menu.addItem(.separator())
        // Settings
        menu.addItem(makeLoginMenuItem())
        menu.addItem(.separator())
        // App
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
        syncUsage()
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

    private func makeUsageMenuItem() -> NSMenuItem {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: 44))
        let title = NSTextField(labelWithString: "Weekly usage")
        title.font = NSFont.menuFont(ofSize: 0)
        title.frame = NSRect(x: 14, y: 22, width: 150, height: 18)
        let value = NSTextField(labelWithString: "—")
        value.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        value.alignment = .right
        value.frame = NSRect(x: 164, y: 22, width: 74, height: 18)
        let reset = NSTextField(labelWithString: "")
        reset.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        reset.textColor = .secondaryLabelColor
        reset.frame = NSRect(x: 14, y: 6, width: 224, height: 16)
        row.addSubview(title)
        row.addSubview(value)
        row.addSubview(reset)
        usageTitleField = title
        usagePercentField = value
        usageResetField = reset
        usageRow = row

        let item = NSMenuItem()
        item.view = row
        return item
    }

    private func syncUsage() {
        guard let usage = WeeklyUsage.latest(in: GrokPaths.unifiedLog(home: GrokPaths.home())) else {
            usageTitleField?.stringValue = "Weekly usage"
            usagePercentField?.stringValue = "—"
            usageResetField?.stringValue = ""
            usageRow?.toolTip = "Usage appears after Grok fetches billing."
            return
        }
        usageTitleField?.stringValue = usage.title
        usagePercentField?.stringValue = usage.percentLabel
        usageResetField?.stringValue = usage.resetLabel() ?? ""
        usageRow?.toolTip = usage.tooltip
    }

    private func makeLoginMenuItem() -> NSMenuItem {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: 32))
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
        if needsDisplayLink {
            startAnimating()
        }
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
        motion.needsFrames(light: light, focused: SessionFocus.isGrokSessionFocused())
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
