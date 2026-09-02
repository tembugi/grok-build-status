import AppKit
import GrokStatusCore
import QuartzCore

private enum MenuLayout {
    static let width: CGFloat = 252
    static let inset: CGFloat = 14
    static let gap: CGFloat = 12
    static let rowHeight: CGFloat = 32
    static let headingHeight: CGFloat = 24

    static var rowFont: NSFont { NSFont.menuFont(ofSize: 0) }
    static var headingFont: NSFont { NSFont.menuFont(ofSize: NSFont.smallSystemFontSize) }

    static func textWidth(_ string: String, font: NSFont?) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        let font = font ?? NSFont.menuFont(ofSize: 0)
        let rect = (string as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: 32),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(rect.width) + 2
    }
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

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
    private var usageRow: NSView?
    private var countdownTimer: Timer?
    private var seenIDs: Set<String> = []
    private var lightsByID: [String: TrafficLight] = [:]
    private var iconVisible = true
    private var menuIsOpen = false

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
        rebuildSessionItems(in: menu)
        bindSnapshotToMenu()
        syncNotificationsSwitch()
        syncLoginSwitch()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        stopCountdownClock()
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
        for row in snapshot.sessions {
            items.append(makeSessionMenuItem(row))
        }
        items.append(.separator())
        for (offset, item) in items.enumerated() {
            menu.insertItem(item, at: insertAt + offset)
        }
    }

    private func makeSessionsHeaderItem() -> NSMenuItem {
        let row = KeyedMenuRow(compact: true)
        row.setTitle("Sessions", value: "None")
        let item = NSMenuItem()
        item.view = row
        return item
    }

    private func makeSessionMenuItem(_ row: LiveSession) -> NSMenuItem {
        let view = KeyedMenuRow()
        view.setTitle(row.title, value: row.light.menuLabel)
        let item = NSMenuItem(
            title: "\(row.title), \(row.light.menuLabel)",
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
        guard let row = usageRow as? UsageMenuRow else { return }
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
            : "Install Grok Status to the Applications folder to enable this."
    }

    @objc private func focusMayHaveChanged(_ notification: Notification) {
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
        if menuIsOpen {
            if idsChanged, let menu = item.menu {
                rebuildSessionItems(in: menu)
            }
            bindSnapshotToMenu()
        }
    }

    /// Paints the current snapshot onto whatever rows already exist.
    /// New fields: put them on `SessionSnapshot`, bind them here.
    private func bindSnapshotToMenu() {
        guard let menu = item.menu else { return }
        if let header = sessionsHeaderItem?.view as? KeyedMenuRow {
            header.setTitle("Sessions", value: sessionsCountLabel(snapshot.sessions))
        }
        for item in menu.items {
            guard let id = item.representedObject as? String,
                  let row = snapshot.sessions.first(where: { $0.session.sessionId == id })
            else { continue }
            item.title = "\(row.title), \(row.light.menuLabel)"
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
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(tickCountdown), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        countdownTimer = timer
    }

    private func stopCountdownClock() {
        countdownTimer?.invalidate()
        countdownTimer = nil
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
        iconVisible && motion.needsFrames(light: snapshot.light)
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        animationTimer = timer
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
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
        guard now - lastTabPoll >= 0.25 else { return }
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
}

@MainActor
private func menuLabel(
    font: NSFont,
    color: NSColor = .labelColor,
    alignment: NSTextAlignment = .left,
    truncates: Bool = false
) -> NSTextField {
    let field = NSTextField(labelWithString: "")
    field.font = font
    field.textColor = color
    field.alignment = alignment
    field.lineBreakMode = truncates ? .byTruncatingTail : .byClipping
    field.usesSingleLineMode = true
    field.maximumNumberOfLines = 1
    if let cell = field.cell as? NSTextFieldCell {
        cell.wraps = false
        cell.isScrollable = false
        cell.truncatesLastVisibleLine = truncates
        cell.lineBreakMode = truncates ? .byTruncatingTail : .byClipping
        cell.alignment = alignment
    }
    field.setContentCompressionResistancePriority(
        truncates ? .fittingSizeCompression : .required,
        for: .horizontal
    )
    field.setContentHuggingPriority(
        truncates ? .defaultLow : .required,
        for: .horizontal
    )
    return field
}

/// Custom menu views keep a fixed width so long titles cannot stretch the menu.
private class MenuItemRowView: NSView {
    let rowHeight: CGFloat

    init(height: CGFloat) {
        rowHeight = height
        super.init(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: height))
        autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: MenuLayout.width, height: rowHeight)
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    fileprivate func trailingValueFrame(for field: NSTextField, y: CGFloat, height: CGFloat) -> (value: NSRect, title: NSRect) {
        let inset = MenuLayout.inset
        let gap = MenuLayout.gap
        let valueWidth = MenuLayout.textWidth(field.stringValue, font: field.font)
        let value = NSRect(
            x: bounds.width - inset - valueWidth,
            y: y,
            width: valueWidth,
            height: height
        )
        let titleRight = valueWidth > 0 ? value.minX - gap : bounds.width - inset
        let title = NSRect(x: inset, y: y, width: max(0, titleRight - inset), height: height)
        return (value, title)
    }
}

/// One menu row: title on the left, grey value on the right.
private final class KeyedMenuRow: MenuItemRowView {
    let titleField: NSTextField
    let valueField: NSTextField
    var clickHandler: (() -> Void)?
    private let compact: Bool
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(compact: Bool = false) {
        self.compact = compact
        let font = compact ? MenuLayout.headingFont : MenuLayout.rowFont
        titleField = menuLabel(
            font: font,
            color: compact ? .secondaryLabelColor : .labelColor,
            truncates: true
        )
        valueField = menuLabel(
            font: font,
            color: .secondaryLabelColor,
            alignment: .right
        )
        super.init(height: compact ? MenuLayout.headingHeight : MenuLayout.rowHeight)
        addSubview(titleField)
        addSubview(valueField)
    }

    func setTitle(_ title: String, value: String) {
        titleField.stringValue = title
        valueField.stringValue = value
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        let labelHeight: CGFloat = compact ? 16 : 20
        let y = ((bounds.height - labelHeight) / 2).rounded()
        let frames = trailingValueFrame(for: valueField, y: y, height: labelHeight)
        valueField.frame = frames.value
        titleField.preferredMaxLayoutWidth = frames.title.width
        titleField.frame = frames.title
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        guard clickHandler != nil else { return }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard clickHandler != nil else { return }
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor.quaternaryLabelColor.setFill()
            bounds.fill()
        }
        super.draw(dirtyRect)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        clickHandler?()
    }
}

private final class UsageMenuRow: MenuItemRowView {
    let titleField: NSTextField
    let percentField: NSTextField
    let resetField: NSTextField
    let countdownField: NSTextField

    init() {
        titleField = menuLabel(font: MenuLayout.rowFont, truncates: true)
        percentField = menuLabel(
            font: NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .regular
            ),
            alignment: .right
        )
        resetField = menuLabel(
            font: MenuLayout.headingFont,
            color: .secondaryLabelColor
        )
        countdownField = menuLabel(
            font: NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.smallSystemFontSize,
                weight: .regular
            ),
            color: .secondaryLabelColor
        )
        super.init(height: 60)
        addSubview(titleField)
        addSubview(percentField)
        addSubview(resetField)
        addSubview(countdownField)
    }

    func set(title: String, percent: String, reset: String, countdown: String) {
        titleField.stringValue = title
        percentField.stringValue = percent
        resetField.stringValue = reset
        countdownField.stringValue = countdown
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        let inset = MenuLayout.inset
        let inner = max(0, bounds.width - inset * 2)
        let frames = trailingValueFrame(for: percentField, y: 38, height: 18)
        percentField.frame = frames.value
        titleField.preferredMaxLayoutWidth = frames.title.width
        titleField.frame = frames.title
        resetField.preferredMaxLayoutWidth = inner
        countdownField.preferredMaxLayoutWidth = inner
        resetField.frame = NSRect(x: inset, y: 20, width: inner, height: 16)
        countdownField.frame = NSRect(x: inset, y: 4, width: inner, height: 14)
    }
}

private final class SwitchMenuRow: MenuItemRowView {
    let labelField: NSTextField
    let toggle: AppleSwitch

    init(title: String) {
        labelField = menuLabel(font: MenuLayout.rowFont)
        labelField.stringValue = title
        toggle = AppleSwitch(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
        super.init(height: 32)
        addSubview(labelField)
        addSubview(toggle)
    }

    override func layout() {
        super.layout()
        let inset = MenuLayout.inset
        let gap = MenuLayout.gap
        let switchSize = toggle.intrinsicContentSize
        toggle.frame = NSRect(
            x: bounds.width - inset - switchSize.width,
            y: ((bounds.height - switchSize.height) / 2).rounded(),
            width: switchSize.width,
            height: switchSize.height
        )
        let labelWidth = max(0, toggle.frame.minX - gap - inset)
        labelField.frame = NSRect(x: inset, y: 6, width: labelWidth, height: 20)
    }
}
