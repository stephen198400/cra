import AppKit
import UniformTypeIdentifiers

/// The downloads button at the far right of the sidebar header (after the From browser's downloads
/// door): the `arrow.down.circle` glyph in the header's tones, a ring while downloads run (filled
/// as far as they've got, or spinning while no size is known), and the card under it on a click.
/// A download starting opens the card, as From shows it arriving. Which rows, the ring and the
/// header geometry are CraCore's `DownloadsCard`.
@MainActor
final class SidebarDownloadsControl: NSView {
    var colors = SidebarColors() {
        didSet {
            button?.colors = colors
            ring.colors = colors
            // Live: a theme edit or macOS switching an Auto theme's half restyles an open card.
            card?.restyle(style())
        }
    }
    var active: Bool? { didSet { button?.active = active } }
    /// The focused space's palette as shown now (an Auto theme's light or dark half), for the card's
    /// surface: the sidebar's own colour.
    var palette: () -> SpacePalette? = { nil }

    private func style() -> DownloadsCardStyle {
        DownloadsCardStyle(colors: colors, palette: palette())
    }
    var showAll: () -> Void = {}
    /// The sidebar is shown in its window (a hidden one stays in the window, off to the side).
    var sidebarShown: () -> Bool = { true }

    private var button: SidebarGlyphButton?
    private let ring = DownloadsRingView()
    private var shownMark: DownloadsCard.Mark?
    private var seen: Set<UInt32>
    private(set) var card: DownloadsCardPanel?

    override init(frame: NSRect) {
        seen = Set(DownloadHistory.shared.live.filter(\.running).map(\.id))
        super.init(frame: frame)
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// 32 pt, or 28 pt where the header goes narrow.
    func setBox(_ size: CGFloat) {
        if let b = button, b.size.width == size { return }
        button?.removeFromSuperview()
        let b = SidebarGlyphButton(symbol: "arrow.down.circle", size: size, height: size, iconSize: 15.5, help: "Downloads (⇧⌘J)",
                                   colors: colors) { [weak self] in self?.toggleCard() }
        b.active = active
        b.highlighted = card != nil
        // No autoresizing: the box is set before this control has its frame, and growing with it
        // from zero doubled the button, which put the glyph 16 pt down and right of its place.
        b.frame = NSRect(x: 0, y: 0, width: size, height: size)
        addSubview(b)
        ring.removeFromSuperview()
        ring.frame = b.bounds
        ring.autoresizingMask = [.width, .height]
        b.addSubview(ring)
        button = b
        shownMark = nil
        showMark(DownloadHistory.shared.mark)
    }

    private struct Watched: Equatable {
        let mark: DownloadsCard.Mark
        let running: Set<UInt32>
    }

    /// Stops once the control is gone: the read then touches nothing observable.
    private func observe() {
        observeChanges(of: { [weak self] () -> Watched? in
            self == nil ? nil : Watched(mark: DownloadHistory.shared.mark, running: Set(DownloadHistory.shared.live.filter(\.running).map(\.id)))
        }) { [weak self] w in
            guard let self, let w else { return }
            self.showMark(w.mark)
            if DownloadsCard.started(seen: self.seen, live: DownloadHistory.shared.live), self.card == nil, self.shouldOpenOnStart {
                CraLog.note("downloads card: opened, a download started")
                self.openCard()
            }
            self.seen = w.running
        }
    }

    /// Only the window in front opens it, and only while its sidebar is on screen.
    private var shouldOpenOnStart: Bool {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor else { return false }
        // Hidden sidebar: only while it floats over the page.
        guard sidebarShown() || (window is FloatingSidebarPanel) else { return false }
        return window.isMainWindow || window.parent?.isMainWindow == true || NSApp.mainWindow == nil
    }

    private func showMark(_ mark: DownloadsCard.Mark) {
        guard mark != shownMark, let button else { return }
        shownMark = mark
        if mark == .idle {
            button.setSymbol("arrow.down.circle", iconSize: 15.5, help: "Downloads (⇧⌘J)")
        } else {
            button.setGlyph(nil, help: "Downloads (⇧⌘J)")
        }
        ring.mark = mark
    }

    func toggleCard() {
        if let card { card.dismiss() } else { openCard() }
    }

    func openCard() {
        guard card == nil, let window, let button else { return }
        let panel = DownloadsCardPanel(style: style())
        panel.onShowAll = { [weak self] in self?.showAll() }
        panel.onClose = { [weak self] in
            self?.card = nil
            self?.button?.highlighted = false
        }
        card = panel
        button.highlighted = true
        panel.show(under: window.convertToScreen(button.convert(button.bounds, to: nil)), in: window)
    }

    func closeCard() { card?.dismiss() }

    /// The card's state for a scenario: "open=1 rows=<n> mark=<idle|spinning|progress 0.42> clear=1"
    /// and each row's name and subtitle.
    var debugState: String {
        let rows = DownloadHistory.shared.card
        let mark: String = switch DownloadHistory.shared.mark {
        case .idle: "idle"
        case .spinning: "spinning"
        case .progress(let p): String(format: "progress %.2f", p)
        }
        let names = rows.map { "\($0.name) [\(DownloadsCardRowView.subtitle(for: $0))]" }.joined(separator: " | ")
        return "open=\(card == nil ? 0 : 1)\(card.map { " " + $0.debugStyle } ?? "") rows=\(rows.count) mark=\(mark) clear=\(DownloadHistory.shared.canClear ? 1 : 0)"
            + (names.isEmpty ? "" : " " + names)
    }
}

/// The ring drawn over the downloads button while downloads run.
@MainActor
private final class DownloadsRingView: NSView {
    var colors = SidebarColors() { didSet { paint() } }
    var mark: DownloadsCard.Mark = .idle { didSet { update() } }
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private static let diameter: CGFloat = 15

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for l in [track, arc] {
            l.fillColor = nil
            l.lineWidth = 1.5
            l.lineCap = .round
            l.actions = ["strokeEnd": NSNull(), "path": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer?.addSublayer(l)
        }
        update()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let box = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
        // Starts at 12 o'clock and runs clockwise (the layer is flipped: y down).
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: box.midX, y: box.midY), radius: Self.diameter / 2,
                    startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: false)
        for l in [track, arc] {
            l.bounds = box
            l.position = CGPoint(x: bounds.midX.rounded(), y: bounds.midY.rounded())
            l.path = path
            l.contentsScale = window?.backingScaleFactor ?? 2
        }
    }

    private func paint() {
        track.strokeColor = colors.separator.cgColor
        arc.strokeColor = colors.textSecondary.cgColor
    }

    private func update() {
        paint()
        isHidden = mark == .idle
        switch mark {
        case .idle:
            arc.removeAnimation(forKey: "spin")
        case .progress(let p):
            arc.removeAnimation(forKey: "spin")
            arc.transform = CATransform3DIdentity
            arc.strokeEnd = max(0.02, CGFloat(p))
        case .spinning:
            arc.strokeEnd = 0.25
            if arc.animation(forKey: "spin") == nil {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = 2 * Double.pi
                spin.duration = 0.9
                spin.repeatCount = .infinity
                arc.add(spin, forKey: "spin")
            }
        }
        needsLayout = true
    }
}

/// The card's colours, all the sidebar's: its surface is the space's sidebar colour made opaque and
/// lifted (DownloadsCard.surface), and every ink, fill and line comes from the space's SidebarColors,
/// so a light sidebar has a light card with dark inks, a dark one a dark card, and an Auto theme
/// follows macOS with the sidebar.
struct DownloadsCardStyle {
    let colors: SidebarColors
    let fill: NSColor

    init(colors: SidebarColors, palette: SpacePalette?) {
        self.colors = colors
        let dark = colors.isDark
        var top = dark ? RGB(0.16, 0.16, 0.17) : RGB(0.96, 0.96, 0.96)
        var alpha = 1.0
        if let palette, let first = palette.gradientColors.first, let c = NSColor(first).usingColorSpace(.sRGB) {
            top = RGB(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
            alpha = palette.gradientAlpha * Double(c.alphaComponent)
        }
        fill = NSColor(DownloadsCard.surface(sidebar: top, alpha: alpha, dark: dark))
    }

    var appearance: NSAppearance? { NSAppearance(named: colors.isDark ? .darkAqua : .aqua) }
}

/// The card: RECENT DOWNLOADS and Clear, the rows (running first, then newest), "Nothing downloaded
/// yet" when there are none, and View all downloads (Library ▸ Downloads). A piece of the sidebar's
/// surface (DownloadsCardStyle) with a hairline border, a soft shadow and an arrow up to the button. A click on a
/// finished row opens the file, its magnifier shows it in the Finder, a running row's ✕ cancels it,
/// and a right-click has the downloads list's menu (pause, resume, hide, move to Trash…). A click
/// anywhere else closes it.
@MainActor
final class DownloadsCardPanel: NSPanel {
    var onClose: (() -> Void)?
    var onShowAll: (() -> Void)?
    private var anchor = NSRect.zero
    private var monitors: [Any] = []
    private var closing = false
    private let view: DownloadsCardView

    init(style: DownloadsCardStyle) {
        view = DownloadsCardView(style: style)
        super.init(contentRect: NSRect(x: 0, y: 0, width: DownloadsCard.width, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        appearance = style.appearance
        contentView = view
        view.onResize = { [weak self] in self?.fit() }
        view.onOpened = { [weak self] in self?.dismiss() }
        view.onShowAll = { [weak self] in
            self?.dismiss()
            self?.onShowAll?()
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The card's fill as drawn now and whether it is dark, for `downloadsPanel=state`.
    var debugStyle: String { view.debugStyle }

    func restyle(_ style: DownloadsCardStyle) {
        appearance = style.appearance
        view.restyle(style)
        invalidateShadow()
    }

    private var arrowX: CGFloat = DownloadsCard.width / 2

    /// Keeps the top (the arrow's tip) where it is when the rows change.
    private func fit() {
        let h = view.preferredHeight
        guard abs(frame.height - h) > 0.5 else { return }
        let top = frame.maxY
        setFrame(NSRect(x: frame.minX, y: top - h, width: DownloadsCard.width, height: h), display: true)
    }

    /// Opens under `button` (a rect on screen), the arrow's tip 6 pt below it, kept on its screen.
    func show(under button: NSRect, in parent: NSWindow) {
        anchor = button
        let h = view.preferredHeight
        let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        var x = (button.midX - DownloadsCard.width / 2).rounded()
        x = min(max(x, screen.minX + 8), screen.maxX - 8 - DownloadsCard.width)
        arrowX = button.midX - x
        view.arrowX = arrowX
        setFrame(NSRect(x: x, y: button.minY - 6 - h, width: DownloadsCard.width, height: h), display: true)
        parent.addChildWindow(self, ordered: .above)
        orderFront(nil)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] e in
            guard let self else { return e }
            if e.window === self || self.view.menuOpen { return e }
            let onAnchor = self.anchor.contains(NSEvent.mouseLocation)
            self.dismiss()
            guard onAnchor else { return e }
            // The button acts on mouse-up: eat that one too, or it opens the card again.
            var up: Any?
            up = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { _ in
                if let m = up { NSEvent.removeMonitor(m) }
                up = nil
                return nil
            }
            return nil
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        } as Any)
        NotificationCenter.default.addObserver(self, selector: #selector(parentChanged), name: NSWindow.willCloseNotification, object: parent)
    }

    @objc private func parentChanged() { dismiss() }

    func dismiss() {
        guard !closing else { return }
        closing = true
        view.stop()
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        NotificationCenter.default.removeObserver(self)
        parent?.removeChildWindow(self)
        orderOut(nil)
        onClose?()
    }
}

@MainActor
private final class DownloadsCardView: NSView {
    var onResize: (() -> Void)?
    var onOpened: (() -> Void)?
    var onShowAll: (() -> Void)?
    var arrowX: CGFloat = DownloadsCard.width / 2 { didSet { needsDisplay = true } }
    var menuOpen = false
    private var style: DownloadsCardStyle
    private let title = NSTextField.sidebarLabel(size: 11, weight: .semibold)
    private let clear: DownloadsCardTextButton
    private let empty = NSTextField.sidebarLabel(size: 13)
    private let footer: DownloadsCardFooter
    private var rows: [DownloadsCardRowView] = []
    private var ticker: Timer?
    private var stopped = false

    static let arrowHeight: CGFloat = 6
    var preferredHeight: CGFloat { CGFloat(DownloadsCard.height(rows: rows.count)) + Self.arrowHeight }

    init(style: DownloadsCardStyle) {
        self.style = style
        clear = DownloadsCardTextButton(title: "Clear")
        footer = DownloadsCardFooter()
        super.init(frame: NSRect(x: 0, y: 0, width: DownloadsCard.width, height: 100))
        addSubview(title)
        clear.action = { DownloadHistory.shared.clear() }
        addSubview(clear)
        empty.stringValue = "Nothing downloaded yet"
        addSubview(empty)
        footer.action = { [weak self] in self?.onShowAll?() }
        addSubview(footer)
        restyle(style)
        observe()
        // The ages ("54 seconds ago") tick while the card is up.
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rows.forEach { $0.refreshSubtitle() } }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var debugStyle: String {
        let c = style.fill.usingColorSpace(.sRGB) ?? style.fill
        let hex = String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                         Int((c.blueComponent * 255).rounded()))
        return "fill=\(hex) dark=\(style.colors.isDark ? 1 : 0)"
    }

    func restyle(_ style: DownloadsCardStyle) {
        self.style = style
        // RECENT DOWNLOADS and the empty line in the sidebar's tertiary ink.
        title.attributedStringValue = NSAttributedString(string: "RECENT DOWNLOADS", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .kern: 0.4, .foregroundColor: style.colors.textTertiary,
        ])
        empty.textColor = style.colors.textTertiary
        clear.style = style
        footer.style = style
        for r in rows { r.style = style }
        needsDisplay = true
    }

    func stop() {
        stopped = true
        ticker?.invalidate()
        ticker = nil
    }

    private struct Watched: Equatable {
        let rows: [DownloadHistory.Listed]
        let canClear: Bool
        let thumbnails: Int
    }

    /// Stops once the card has closed: the read then touches nothing observable.
    private func observe() {
        observeChanges(of: { [weak self] () -> Watched? in
            guard let self, !self.stopped else { return nil }
            let h = DownloadHistory.shared
            return Watched(rows: h.card, canClear: h.canClear, thumbnails: h.thumbnails.count)
        }) { [weak self] w in
            guard let self, let w else { return }
            self.update(w.rows, canClear: w.canClear)
        }
    }

    private func update(_ listed: [DownloadHistory.Listed], canClear: Bool) {
        while rows.count < listed.count {
            let r = DownloadsCardRowView(style: style)
            r.onOpened = { [weak self] in self?.onOpened?() }
            r.onMenu = { [weak self] open in self?.menuOpen = open }
            rows.append(r)
            addSubview(r)
        }
        while rows.count > listed.count { rows.removeLast().removeFromSuperview() }
        for (r, l) in zip(rows, listed) { r.show(l) }
        clear.enabled = canClear
        empty.isHidden = !listed.isEmpty
        needsLayout = true
        onResize?()
    }

    override func layout() {
        super.layout()
        let w = bounds.width, top = Self.arrowHeight
        let inset = CGFloat(DownloadsCard.inset)
        title.frame = NSRect(x: 16 - SidebarText.inset, y: top + 14, width: 200, height: 15)
        clear.frame = NSRect(x: w - 12 - clear.width, y: top + 9, width: clear.width, height: 24)
        var y = top + CGFloat(DownloadsCard.headerHeight) + inset
        for r in rows {
            r.frame = NSRect(x: inset, y: y, width: w - 2 * inset, height: CGFloat(DownloadsCard.rowHeight))
            y += CGFloat(DownloadsCard.rowHeight)
        }
        if rows.isEmpty {
            empty.frame = NSRect(x: 16 - SidebarText.inset, y: y + 13, width: w - 32, height: 18)
            y += CGFloat(DownloadsCard.emptyHeight)
        }
        y += inset
        footer.frame = NSRect(x: inset, y: y, width: w - 2 * inset, height: CGFloat(DownloadsCard.footerHeight) - inset)
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, a = Self.arrowHeight, half: CGFloat = 6
        let body = NSBezierPath(roundedRect: NSRect(x: 0, y: a, width: w, height: bounds.height - a),
                                xRadius: CGFloat(SidebarMoreMenu.cornerRadius), yRadius: CGFloat(SidebarMoreMenu.cornerRadius))
        let mid = min(max(arrowX, CGFloat(SidebarMoreMenu.cornerRadius) + half), w - CGFloat(SidebarMoreMenu.cornerRadius) - half)
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: mid - half, y: a + 0.5))
        arrow.line(to: NSPoint(x: mid, y: 0))
        arrow.line(to: NSPoint(x: mid + half, y: a + 0.5))
        arrow.close()
        let shape = NSBezierPath()
        shape.append(body)
        shape.append(arrow)
        style.fill.setFill()
        body.fill()
        arrow.fill()
        // The hairline border: the outline stroked inside the edge, clipped to the card's shape.
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        style.colors.separator.setStroke()
        body.lineWidth = 2
        body.stroke()
        let tip = NSBezierPath()
        tip.move(to: NSPoint(x: mid - half, y: a + 0.5))
        tip.line(to: NSPoint(x: mid, y: 0))
        tip.line(to: NSPoint(x: mid + half, y: a + 0.5))
        tip.lineWidth = 2
        tip.stroke()
        NSGraphicsContext.restoreGraphicsState()
        // Where the arrow opens into the body, no line.
        style.fill.setFill()
        NSRect(x: mid - half + 1.5, y: a, width: 2 * half - 3, height: 1.5).fill()
        // A faint hairline, inset, between the files and the way to all of them.
        style.colors.separator.setFill()
        NSRect(x: 16, y: footer.frame.minY - 1, width: w - 32, height: 1).fill()
    }
}

/// One download: icon or thumbnail, name, what it is doing; the reveal or cancel button at the end.
@MainActor
final class DownloadsCardRowView: NSView, NSDraggingSource {
    var onOpened: (() -> Void)?
    var onMenu: ((Bool) -> Void)?
    var style: DownloadsCardStyle { didSet { applyStyle() } }
    private var listed: DownloadHistory.Listed?
    private let icon = NSImageView()
    private let name = NSTextField.sidebarLabel(size: 13, weight: .medium)
    private let status = NSTextField.sidebarLabel(size: 11)
    private let bar = CALayer()
    private let barFill = CALayer()
    private let trailing = DownloadsCardIconButton()
    private var hovering = false { didSet { if hovering != oldValue { updateFill() } } }
    private var downAt: NSPoint?

    init(style: DownloadsCardStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)
        name.lineBreakMode = .byTruncatingMiddle
        addSubview(name)
        addSubview(status)
        bar.cornerRadius = 1
        barFill.cornerRadius = 1
        bar.addSublayer(barFill)
        layer?.addSublayer(bar)
        addSubview(trailing)
        applyStyle()
    }

    /// Name in the sidebar's primary ink, status in its secondary, the bar on its separator line.
    private func applyStyle() {
        let c = style.colors
        name.textColor = c.textPrimary
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.backgroundColor = c.separator.cgColor
        barFill.backgroundColor = c.textSecondary.cgColor
        CATransaction.commit()
        trailing.colors = c
        updateFill()
        refreshSubtitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var finished: DownloadHistory.Entry? {
        if case .finished(let e)? = listed { return e }
        return nil
    }

    /// The line under the name: Arc's subtitle (DownloadRow), "Failed to Download" in red.
    static func subtitle(for l: DownloadHistory.Listed, now: Date = Date()) -> String {
        switch l {
        case .finished(let e): return DownloadRow.subtitle(.finished(at: e.date), now: now)
        case .live(let live): return DownloadRow.subtitle(live.row, now: now)
        }
    }

    func show(_ l: DownloadHistory.Listed) {
        listed = l
        let history = DownloadHistory.shared
        name.stringValue = l.name
        var image: NSImage?
        switch l {
        case .finished(let e):
            image = history.thumbnail(for: e.path) ?? NSWorkspace.shared.icon(forFile: e.path)
            trailing.configure(symbol: "magnifyingglass", help: "Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: e.path)])
            }
        case .live(let live):
            image = NSWorkspace.shared.icon(for: UTType(filenameExtension: (live.name as NSString).pathExtension) ?? .data)
            if live.running {
                trailing.configure(symbol: "xmark.circle.fill", help: "Cancel Download") { history.control(live.id, .cancel) }
            } else {
                trailing.configure(symbol: "xmark", help: "Hide from list") { history.hide(l) }
            }
        }
        icon.image = image
        icon.alphaValue = {
            if case .live(let live) = l, !live.running { return 0.45 }
            return 1
        }()
        refreshSubtitle()
        needsLayout = true
    }

    func refreshSubtitle() {
        guard let listed else { return }
        let s = Self.subtitle(for: listed)
        if status.stringValue != s { status.stringValue = s }
        var failed = false, fraction: Double?
        if case .live(let l) = listed {
            failed = l.failed
            if l.running { fraction = l.total > 0 ? min(1, Double(l.received) / Double(l.total)) : nil }
        }
        status.textColor = failed ? NSColor.systemRed : style.colors.textSecondary
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.isHidden = fraction == nil
        if let fraction { barFill.frame = CGRect(x: 0, y: 0, width: bar.bounds.width * CGFloat(fraction), height: 2) }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let h = bounds.height, w = bounds.width
        icon.frame = NSRect(x: 8, y: (h - 28) / 2, width: 28, height: 28)
        trailing.frame = NSRect(x: w - 6 - 24, y: (h - 24) / 2, width: 24, height: 24)
        let x: CGFloat = 8 + 28 + 10, textW = max(0, trailing.frame.minX - 6 - x)
        let running: Bool = { if case .live(let l)? = listed { return l.running }; return false }()
        let top: CGFloat = running ? 5 : 7
        name.frame = NSRect(x: x - SidebarText.inset, y: top, width: textW + 2 * SidebarText.inset, height: 17)
        status.frame = NSRect(x: x - SidebarText.inset, y: top + 17, width: textW + 2 * SidebarText.inset, height: 14)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.frame = CGRect(x: x, y: h - 7, width: textW, height: 2)
        CATransaction.commit()
        refreshSubtitle()
    }

    private func updateFill() { layer?.backgroundColor = (hovering ? style.colors.hoverFill : .clear).cgColor }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, let entry = finished else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 3 else { return }
        downAt = nil
        let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: entry.path) as NSURL)
        item.setDraggingFrame(icon.frame, contents: icon.image ?? NSWorkspace.shared.icon(forFile: entry.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    /// A click on a finished row opens the file and closes the card.
    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        guard downAt != nil, let entry = finished, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
        onOpened?()
    }

    /// The downloads list's menu (DownloadRowMenu): Open, Copy, Show in Finder, Pause, Resume,
    /// Cancel, Hide from Cra, Move to Trash, as the row allows.
    override func rightMouseDown(with event: NSEvent) {
        guard let listed else { return }
        let menu = NSMenu()
        DownloadRowMenu.fill(menu, for: listed)
        guard !menu.items.isEmpty else { return }
        onMenu?(true)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        onMenu?(false)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : .copy
    }
}

/// A row's round icon button (reveal, cancel, hide).
@MainActor
private final class DownloadsCardIconButton: NSView {
    private let image = NSImageView()
    private var action: () -> Void = {}
    private var symbol = ""
    private var hovering = false { didSet { tint() } }
    var colors = SidebarColors() { didSet { tint() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        image.imageScaling = .scaleNone
        image.autoresizingMask = [.width, .height]
        addSubview(image)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func layout() {
        super.layout()
        image.frame = bounds
    }

    func configure(symbol: String, help: String, action: @escaping () -> Void) {
        self.action = action
        toolTip = help
        setAccessibilityLabel(help)
        guard symbol != self.symbol else { return }
        self.symbol = symbol
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        tint()
    }

    /// The sidebar's glyph tone, its primary ink under the pointer.
    private func tint() { image.contentTintColor = hovering ? colors.textPrimary : colors.glyph }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

/// The header's Clear.
@MainActor
private final class DownloadsCardTextButton: NSView {
    var action: () -> Void = {}
    var enabled = true { didSet { tint() } }
    var style: DownloadsCardStyle? { didSet { tint() } }
    private let label = NSTextField.sidebarLabel(size: 12, weight: .medium)
    private var hovering = false { didSet { tint() } }
    var width: CGFloat { ceil(label.intrinsicContentSize.width) + 12 }

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        label.stringValue = title
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        tint()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func layout() {
        super.layout()
        label.frame = NSRect(x: 6 - SidebarText.inset, y: (bounds.height - 16) / 2, width: bounds.width - 12 + 2 * SidebarText.inset, height: 16)
    }

    private func tint() {
        guard let c = style?.colors else { return }
        label.textColor = enabled ? (hovering ? c.textPrimary : c.textSecondary) : c.textTertiary
        layer?.backgroundColor = (enabled && hovering ? c.hoverFill : .clear).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if enabled, bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

/// "View all downloads ↗": Library ▸ Downloads, with the hover fill of a row.
@MainActor
private final class DownloadsCardFooter: NSView {
    var action: () -> Void = {}
    var style: DownloadsCardStyle? { didSet { tint() } }
    private let label = NSTextField.sidebarLabel(size: 13)
    private let arrow = NSImageView()
    private var hovering = false { didSet { tint() } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        label.stringValue = "View all downloads"
        addSubview(label)
        arrow.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        arrow.imageScaling = .scaleNone
        addSubview(arrow)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("View all downloads")
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func tint() {
        guard let c = style?.colors else { return }
        label.textColor = hovering ? c.textPrimary : c.textSecondary
        arrow.contentTintColor = label.textColor
        layer?.backgroundColor = (hovering ? c.hoverFill : .clear).cgColor
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 10 - SidebarText.inset, y: (bounds.height - 17) / 2, width: bounds.width - 40, height: 17)
        arrow.frame = NSRect(x: bounds.width - 10 - 16, y: (bounds.height - 16) / 2, width: 16, height: 16)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}
