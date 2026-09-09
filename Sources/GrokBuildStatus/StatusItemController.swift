import AppKit
import GrokBuildStatusCore
import QuartzCore

/// Menu bar extra: icon, live menu, notifications, and login.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    private static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "Grok Build Status"
    }

    private let item: NSStatusItem
    private var snapshot = SessionSnapshot.empty
    private var motion = IconMotion()
    private var appearanceObserver: NSKeyValueObservation?
    private var animationTimer: Timer?
    private var loginSwitch: AppleSwitch?
    private var notificationsSwitch: AppleSwitch?
    private var primedAlerts = false
    private var sessionsHeaderItem: NSMenuItem?
    private var usageItem: NSMenuItem?
    private var usageRow: UsageMenuRow?
    private var countdownTimer: Timer?
    private var seenIDs: Set<String> = []
    private var lightsByID: [String: TrafficLight] = [:]
    private var iconVisible = true
    private var menuIsOpen = false
    private var groups: [SessionGroup] = []
    private var groupTimer: Timer?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: GrokMarkImage.pointSize.width)
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let sessions = makeSessionsHeaderItem()
        sessionsHeaderItem = sessions
        menu.addItem(sessions)
        menu.addItem(.separator())
        let usage = makeUsageMenuItem()
        usageItem = usage
        menu.addItem(usage)
        menu.addItem(.separator())
        menu.addItem(makeNotificationsMenuItem())
        menu.addItem(makeLoginMenuItem())
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit \(Self.displayName)",
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(occlusionChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        StatusNotifications.shared.start()
        StatusNotifications.shared.onOpenSession = { [weak self] id in
            self?.openSession(id: id)
        }

        render()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        refreshGroups(forceWindows: true)
        rebuildSessionItems(in: menu)
        bindSnapshotToMenu()
        syncNotificationsSwitch()
        syncLoginSwitch()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        stopCountdownClock()
        stopGroupClock()
    }

    func apply(_ snapshot: SessionSnapshot) {
        let previousLights = lightsByID
        let finishedWhileRunning = reconcileSeen(with: snapshot)
        let idsChanged = Set(self.snapshot.sessions.map(\.session.sessionId))
            != Set(snapshot.sessions.map(\.session.sessionId))
        self.snapshot = snapshot
        noteSelectedTab()
        if primedAlerts {
            StatusNotifications.shared.post(
                SessionAlerts.arriving(
                    previous: previousLights,
                    sessions: snapshot.sessions,
                    seenIDs: seenIDs
                )
            )
        }
        primedAlerts = true
        if finishedWhileRunning, iconVisible {
            motion.tapPulse()
        }
        if needsAnimation {
            startAnimating()
        }
        render()
        // Window grouping talks to Terminal/iTerm. Keep that off the icon path.
        if menuIsOpen {
            let previousGroups = groupingSignature(groups)
            refreshGroups()
            let groupingChanged = groupingSignature(groups) != previousGroups
            if idsChanged || groupingChanged, let menu = item.menu {
                rebuildSessionItems(in: menu)
            }
            bindSnapshotToMenu()
        }
    }

    private func rebuildSessionItems(in menu: NSMenu) {
        guard let header = sessionsHeaderItem, let usageItem else { return }
        for item in menu.items {
            if item === header { continue }
            if item === usageItem { break }
            menu.removeItem(item)
        }
        guard let insertAt = menu.items.firstIndex(of: usageItem) else { return }

        var items: [NSMenuItem] = []
        for (index, group) in groups.enumerated() {
            if index > 0 {
                items.append(.separator())
            }
            items.append(makeGroupHeaderItem(group))
            for row in group.sessions {
                items.append(makeSessionMenuItem(row))
            }
        }
        items.append(.separator())
        for (offset, item) in items.enumerated() {
            menu.insertItem(item, at: insertAt + offset)
        }
    }

    private func makeGroupHeaderItem(_ group: SessionGroup) -> NSMenuItem {
        let row = KeyedMenuRow(style: .group)
        row.setTitle(group.title, value: TrafficLight.countSummary(group.sessions.map(\.light)) ?? "")
        let item = NSMenuItem()
        item.view = row
        item.representedObject = group.id
        return item
    }

    private func makeSessionsHeaderItem() -> NSMenuItem {
        let row = KeyedMenuRow(style: .section)
        row.setTitle("Sessions", value: "None")
        let item = NSMenuItem()
        item.view = row
        return item
    }

    private func makeSessionMenuItem(_ row: LiveSession) -> NSMenuItem {
        let view = KeyedMenuRow()
        view.setTitle(row.title, value: row.light.menuLabel)
        let item = NSMenuItem(
            title: row.menuTitle,
            action: #selector(showSession(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.isEnabled = true
        item.representedObject = row.session.sessionId
        item.toolTip = row.light.tooltip
        view.clickHandler = { [weak self, weak item] in
            guard let self, let item else { return }
            item.menu?.cancelTracking()
            self.showSession(item)
        }
        item.view = view
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(item.title)
        return item
    }

    private func sessionsCountLabel(_ sessions: [LiveSession]) -> String {
        TrafficLight.countSummary(sessions.map(\.light)) ?? "None"
    }

    @objc private func showSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        // Menu tracking uses a special run-loop mode. AppleScript to Terminal
        // is ignored until that mode ends. GCD's main queue runs in default
        // mode after the menu closes — that is the event, not a timer.
        DispatchQueue.main.async {
            self.openSession(id: id)
        }
    }

    private func openSession(id: String) {
        guard let session = snapshot.sessions.first(where: { $0.session.sessionId == id })?.session
        else {
            NSSound.beep()
            return
        }
        if !SessionFocus.bringSessionToFront(session) {
            NSSound.beep()
        }
    }

    private func makeUsageMenuItem() -> NSMenuItem {
        let row = UsageMenuRow()
        usageRow = row
        let item = NSMenuItem()
        item.view = row
        return item
    }

    private func syncUsage() {
        guard let row = usageRow else { return }
        guard let usage = snapshot.usage else {
            row.set(
                title: "Weekly usage",
                percent: "—",
                reset: "",
                countdown: ""
            )
            row.toolTip = "Usage appears after Grok fetches billing."
            return
        }
        row.set(
            title: usage.title,
            percent: usage.percentLabel,
            reset: usage.resetLabel() ?? "",
            countdown: usage.countdownLabel() ?? ""
        )
        row.toolTip = usage.tooltip
    }

    private func makeNotificationsMenuItem() -> NSMenuItem {
        let row = SwitchMenuRow(title: "Notifications")
        row.toggle.target = self
        row.toggle.action = #selector(toggleNotifications(_:))
        row.toggle.setAccessibilityLabel("Notifications")
        notificationsSwitch = row.toggle
        syncNotificationsSwitch()

        let item = NSMenuItem()
        item.view = row
        return item
    }

    @objc private func toggleNotifications(_ sender: AppleSwitch) {
        StatusNotifications.shared.setEnabled(sender.state == .on) { granted in
            if sender.state == .on, !granted {
                NSSound.beep()
            }
            self.syncNotificationsSwitch()
        }
    }

    private func syncNotificationsSwitch() {
        notificationsSwitch?.setOn(StatusNotifications.shared.isEnabled, animated: false)
        notificationsSwitch?.toolTip = StatusNotifications.shared.isEnabled
            ? nil
            : "Mac notifications when Grok is waiting or done."
    }

    private func makeLoginMenuItem() -> NSMenuItem {
        let row = SwitchMenuRow(title: "Start on login")
        row.toggle.target = self
        row.toggle.action = #selector(toggleLogin(_:))
        row.toggle.setAccessibilityLabel("Start on login")
        loginSwitch = row.toggle

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
            : "Install \(Self.displayName) to the Applications folder to enable this."
    }

    @objc private func focusMayHaveChanged(_ notification: Notification) {
        noteSelectedTab()
        syncIconVisibility()
        if needsAnimation {
            startAnimating()
        }
        render()
    }

    @objc private func occlusionChanged(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           window !== item.button?.window,
           notification.name == NSWindow.didChangeOcclusionStateNotification
        {
            return
        }
        syncIconVisibility()
    }

    private func syncIconVisibility() {
        let visible = item.button?.window?.occlusionState.contains(.visible) ?? true
        iconVisible = visible
        if visible {
            if needsAnimation {
                startAnimating()
            }
        } else {
            stopAnimating()
        }
    }

    private func groupingSignature(_ groups: [SessionGroup]) -> [[String]] {
        groups.map { [$0.id, $0.title] + $0.sessions.map(\.session.sessionId) }
    }

    private func refreshGroups(forceWindows: Bool = false) {
        let windows = snapshot.sessions.isEmpty ? [] : HostWindows.list(force: forceWindows)
        var ttys: [pid_t: String] = [:]
        for row in snapshot.sessions {
            if let tty = ProcessLiveness.ttyName(of: row.session.pid) {
                ttys[row.session.pid] = tty
            }
        }
        groups = SessionGroups.make(sessions: snapshot.sessions, windows: windows, ttys: ttys)
        startGroupClock()
    }

    private func startGroupClock() {
        guard menuIsOpen, !snapshot.sessions.isEmpty else {
            stopGroupClock()
            return
        }
        guard groupTimer == nil else { return }
        groupTimer = scheduleRepeatingTimer(interval: 1, selector: #selector(tickGroups))
    }

    private func stopGroupClock() {
        invalidate(&groupTimer)
    }

    @objc private func tickGroups() {
        guard menuIsOpen else {
            stopGroupClock()
            return
        }
        let before = groupingSignature(groups)
        refreshGroups(forceWindows: true)
        if groupingSignature(groups) != before, let menu = item.menu {
            rebuildSessionItems(in: menu)
        }
        bindSnapshotToMenu()
    }

    private func bindSnapshotToMenu() {
        guard let menu = item.menu else { return }
        if let header = sessionsHeaderItem?.view as? KeyedMenuRow {
            header.setTitle("Sessions", value: sessionsCountLabel(snapshot.sessions))
        }
        for item in menu.items {
            guard let id = item.representedObject as? String else { continue }
            if let group = groups.first(where: { $0.id == id }),
               let view = item.view as? KeyedMenuRow
            {
                view.setTitle(group.title, value: TrafficLight.countSummary(group.sessions.map(\.light)) ?? "")
                continue
            }
            guard let row = snapshot.sessions.first(where: { $0.session.sessionId == id })
            else { continue }
            item.title = row.menuTitle
            item.toolTip = row.light.tooltip
            if let view = item.view as? KeyedMenuRow {
                view.setTitle(row.title, value: row.light.menuLabel)
                view.setAccessibilityLabel(item.title)
            }
        }
        syncUsage()
        startCountdownClock()
    }

    private func startCountdownClock() {
        guard menuIsOpen, let end = snapshot.usage?.periodEnd, end.timeIntervalSinceNow > 0 else {
            stopCountdownClock()
            return
        }
        guard countdownTimer == nil else { return }
        countdownTimer = scheduleRepeatingTimer(interval: 1, selector: #selector(tickCountdown))
    }

    private func stopCountdownClock() {
        invalidate(&countdownTimer)
    }

    @objc private func tickCountdown() {
        guard menuIsOpen else {
            stopCountdownClock()
            return
        }
        syncUsage()
        if snapshot.usage?.periodEnd?.timeIntervalSinceNow ?? 0 <= 0 {
            stopCountdownClock()
        }
    }

    private func reconcileSeen(with snapshot: SessionSnapshot) -> Bool {
        let ids = Set(snapshot.sessions.map(\.session.sessionId))
        seenIDs = seenIDs.intersection(ids)
        var finished = false
        for row in snapshot.sessions {
            let id = row.session.sessionId
            let previous = lightsByID[id]
            if row.light == .completed, let previous, previous != .completed {
                finished = true
            }
            if previous != row.light {
                seenIDs.remove(id)
            }
            lightsByID[id] = row.light
        }
        lightsByID = lightsByID.filter { ids.contains($0.key) }
        return finished && snapshot.light == .running
    }

    /// Only a matching tab TTY counts. Frontmost Terminal does not.
    private func noteSelectedTab() {
        switch snapshot.light {
        case .waitingForInput, .completed:
            break
        default:
            return
        }
        guard let tty = SessionFocus.selectedTabTTY() else { return }
        for row in snapshot.sessions {
            if ProcessLiveness.ttyName(of: row.session.pid) == tty {
                seenIDs.insert(row.session.sessionId)
                return
            }
        }
    }

    private var attentionFocused: Bool {
        AttentionFocus.isSettled(
            light: snapshot.light,
            sessions: snapshot.sessions,
            seenIDs: seenIDs
        )
    }

    private var needsAnimation: Bool {
        iconVisible && motion.needsFrames(light: snapshot.light, focused: attentionFocused)
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }
        animationTimer = scheduleRepeatingTimer(interval: 1.0 / 30.0, selector: #selector(tick))
    }

    private func stopAnimating() {
        invalidate(&animationTimer)
    }

    @objc private func tick() {
        pollSelectedTabIfNeeded()
        render()
        if !needsAnimation {
            stopAnimating()
        }
    }

    private var lastTabPoll: TimeInterval = 0

    private func pollSelectedTabIfNeeded() {
        switch snapshot.light {
        case .waitingForInput, .completed:
            break
        default:
            return
        }
        let now = CACurrentMediaTime()
        guard now - lastTabPoll >= 0.5 else { return }
        lastTabPoll = now
        noteSelectedTab()
    }

    private func render() {
        guard let button = item.button else { return }
        motion.advance(
            light: snapshot.light,
            now: CACurrentMediaTime(),
            focused: attentionFocused
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
        if snapshot.sessions.count > 1, let summary = TrafficLight.countSummary(snapshot.sessions.map(\.light)) {
            return summary
        }
        return (snapshot.sessions.first?.light ?? snapshot.light).tooltip
    }

    private func scheduleRepeatingTimer(interval: TimeInterval, selector: Selector) -> Timer {
        let timer = Timer(timeInterval: interval, target: self, selector: selector, userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        return timer
    }

    private func invalidate(_ timer: inout Timer?) {
        timer?.invalidate()
        timer = nil
    }
}
