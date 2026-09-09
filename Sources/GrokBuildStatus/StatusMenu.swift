import AppKit

enum MenuLayout {
    static let width: CGFloat = 252
    static let inset: CGFloat = 14
    static let gap: CGFloat = 12
    static let rowHeight: CGFloat = 32
    static let headingHeight: CGFloat = 24
    static let rowLabelHeight: CGFloat = 20
    static let headingLabelHeight: CGFloat = 16
    static let captionLabelHeight: CGFloat = 14
    static var usageHeight: CGFloat { rowHeight + headingHeight * 2 }

    static var rowFont: NSFont { NSFont.menuFont(ofSize: 0) }
    static var headingFont: NSFont { NSFont.menuFont(ofSize: NSFont.smallSystemFontSize) }

    static func centeredY(labelHeight: CGFloat, in rowHeight: CGFloat, at offset: CGFloat = 0) -> CGFloat {
        offset + ((rowHeight - labelHeight) / 2).rounded()
    }

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
class MenuItemRowView: NSView {
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

    func trailingValueFrame(for field: NSTextField, y: CGFloat, height: CGFloat) -> (value: NSRect, title: NSRect) {
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

enum MenuRowStyle {
    /// Section title, same weight as Notifications / Start on login.
    case section
    /// Subhead inside a section, smaller grey type.
    case group
    /// Clickable session row.
    case row

    var compact: Bool { self == .group }
    var font: NSFont { compact ? MenuLayout.headingFont : MenuLayout.rowFont }
    var titleColor: NSColor { self == .row ? .labelColor : .secondaryLabelColor }
    var height: CGFloat { compact ? MenuLayout.headingHeight : MenuLayout.rowHeight }
}

/// One menu row: title on the left, grey value on the right.
final class KeyedMenuRow: MenuItemRowView {
    let titleField: NSTextField
    let valueField: NSTextField
    var clickHandler: (() -> Void)?
    private let style: MenuRowStyle
    private var hovered = false
    private var tracking: NSTrackingArea?

    init(style: MenuRowStyle = .row) {
        self.style = style
        titleField = menuLabel(
            font: style.font,
            color: style.titleColor,
            truncates: true
        )
        valueField = menuLabel(
            font: style.font,
            color: .secondaryLabelColor,
            alignment: .right
        )
        super.init(height: style.height)
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
        let labelHeight: CGFloat = style.compact
            ? MenuLayout.headingLabelHeight
            : MenuLayout.rowLabelHeight
        let y = MenuLayout.centeredY(labelHeight: labelHeight, in: bounds.height)
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

final class UsageMenuRow: MenuItemRowView {
    let titleField: NSTextField
    let percentField: NSTextField
    let resetField: NSTextField
    let countdownField: NSTextField

    init() {
        titleField = menuLabel(
            font: MenuLayout.rowFont,
            color: .secondaryLabelColor,
            truncates: true
        )
        percentField = menuLabel(
            font: NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .regular
            ),
            color: .secondaryLabelColor,
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
        super.init(height: MenuLayout.usageHeight)
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
        let titleY = MenuLayout.centeredY(
            labelHeight: MenuLayout.rowLabelHeight,
            in: MenuLayout.rowHeight,
            at: MenuLayout.headingHeight * 2
        )
        let resetY = MenuLayout.centeredY(
            labelHeight: MenuLayout.headingLabelHeight,
            in: MenuLayout.headingHeight,
            at: MenuLayout.headingHeight
        )
        let countdownY = MenuLayout.centeredY(
            labelHeight: MenuLayout.captionLabelHeight,
            in: MenuLayout.headingHeight
        )
        let frames = trailingValueFrame(
            for: percentField,
            y: titleY,
            height: MenuLayout.rowLabelHeight
        )
        percentField.frame = frames.value
        titleField.preferredMaxLayoutWidth = frames.title.width
        titleField.frame = frames.title
        resetField.preferredMaxLayoutWidth = inner
        countdownField.preferredMaxLayoutWidth = inner
        resetField.frame = NSRect(
            x: inset,
            y: resetY,
            width: inner,
            height: MenuLayout.headingLabelHeight
        )
        countdownField.frame = NSRect(
            x: inset,
            y: countdownY,
            width: inner,
            height: MenuLayout.captionLabelHeight
        )
    }
}

final class SwitchMenuRow: MenuItemRowView {
    let labelField: NSTextField
    let toggle: AppleSwitch

    init(title: String) {
        labelField = menuLabel(font: MenuLayout.rowFont)
        labelField.stringValue = title
        toggle = AppleSwitch(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
        super.init(height: MenuLayout.rowHeight)
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
        labelField.frame = NSRect(
            x: inset,
            y: MenuLayout.centeredY(labelHeight: MenuLayout.rowLabelHeight, in: bounds.height),
            width: labelWidth,
            height: MenuLayout.rowLabelHeight
        )
    }
}
