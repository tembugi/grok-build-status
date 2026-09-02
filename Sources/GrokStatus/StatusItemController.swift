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
    private var usageItem: NSMenuItem?
    private var usageTitleField: NSTextField?
    private var usagePercentField: NSTextField?
    private var usageResetField: NSTextField?
    private var usageRow: NSView?
    private var roster: [LiveSession] = []
    private var sessionStates: [SessionState] = []
    private var pendingSession: ActiveSession?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: GrokMarkImage.pointSize.width)
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let usage = makeUsageMenuItem()
        usageItem = usage
        menu.addItem(usage)
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

    func menuWillOpen(_ menu: NSMenu) {
        roster = SessionRoster.labeled(sessionStates, home: GrokPaths.home())
        rebuildSessionItems(in: menu)
        syncUsage()
        syncLoginSwitch()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard let session = pendingSession else { return }
        pendingSession = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if !(await SessionFocus.bringSessionToFront(session)) {
                NSSound.beep()
            }
        }
    }

    private func rebuildSessionItems(in menu: NSMenu) {
        guard let usageItem else { return }
        while let first = menu.items.first, first !== usageItem {
            menu.removeItem(first)
        }

        var items: [NSMenuItem] = []
        if roster.isEmpty {
            items.append(disabledSessionItem("No sessions"))
        } else {
            if roster.count > 1, let summary = TrafficLight.countSummary(roster.map(\.light)) {
                items.append(disabledSessionItem(summary))
            }
            for row in roster {
                let item = NSMenuItem(
                    title: row.menuTitle,
                    action: #selector(showSession(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.isEnabled = true
                item.representedObject = row.session.sessionId
                item.toolTip = row.light.tooltip
                items.append(item)
            }
        }
        items.append(.separator())

        for (offset, item) in items.enumerated() {
            menu.insertItem(item, at: offset)
        }
    }

    private func disabledSessionItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func showSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        pendingSession = roster.first { $0.session.sessionId == id }?.session
            ?? sessionStates.first { $0.session.sessionId == id }?.session
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

    func setLight(_ light: TrafficLight, sessions: [SessionState] = []) {
        self.light = light
        self.sessionStates = sessions
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
        let tip = iconTooltip()
        button.toolTip = tip
        button.setAccessibilityLabel(tip)
    }

    private func iconTooltip() -> String {
        if sessionStates.count > 1, let summary = TrafficLight.countSummary(sessionStates.map(\.light)) {
            return summary
        }
        return (sessionStates.first?.light ?? light).tooltip
    }
}
