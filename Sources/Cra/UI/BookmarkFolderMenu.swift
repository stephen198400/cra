import AppKit

extension NSPasteboard.PasteboardType {
    /// A bookmark or folder dragged from the bar or a folder's dropdown: its id.
    static let fromBookmark = NSPasteboard.PasteboardType("dk.kildahl.from.bookmark")
    /// The title another app (or a page) gives a dragged link.
    static let urlName = NSPasteboard.PasteboardType("public.url-name")
}

/// What a drop onto the bar or a dropdown carries, and how it lands (CraCore BookmarkDrag decides
/// where; this reads the pasteboard and edits the store).
@MainActor
enum BookmarkDropping {
    enum Payload: Equatable {
        /// One of ours, moved.
        case node(UUID)
        /// A link from the address field, a page or another app: a new bookmark.
        case link(url: String, title: String)
    }

    static let types: [NSPasteboard.PasteboardType] = [.fromBookmark, .URL]

    static func payload(from pb: NSPasteboard) -> Payload? {
        if let s = pb.string(forType: .fromBookmark), let id = UUID(uuidString: s) { return .node(id) }
        guard let url = NSURL(from: pb) as URL?, let scheme = url.scheme?.lowercased(),
              scheme != "javascript", scheme != "data" else { return nil }
        let raw = url.absoluteString
        let name = pb.string(forType: .urlName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .link(url: raw, title: name?.isEmpty == false ? name! : (url.host ?? raw))
    }

    /// The pasteboard item a drag of `node` writes: our id, and a bookmark's address for a drop
    /// anywhere else (a page, the Finder).
    static func pasteboardItem(for node: BookmarkNode) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(node.id.uuidString, forType: .fromBookmark)
        if let url = node.url {
            item.setString(url, forType: .URL)
            item.setString(url, forType: .string)
            item.setString(node.displayTitle, forType: .urlName)
        }
        return item
    }

    /// Where the drop at `slot` among `parent`'s `children` goes; nil when it can't.
    static func target(_ p: Payload, at slot: BookmarkDropSlot, parent: UUID,
                       children: [BookmarkNode]) -> (folder: UUID, index: Int?)? {
        switch p {
        case .node(let id):
            return BookmarkDrag.destination(of: id, at: slot, parent: parent, children: children, in: BookmarkStore.shared.tree)
        case .link:
            switch slot {
            case .insert(let i): return (parent, min(max(0, i), children.count))
            case .into(let i): return children.indices.contains(i) && children[i].isFolder ? (children[i].id, nil) : nil
            }
        }
    }

    static func operation(_ p: Payload) -> NSDragOperation {
        if case .node = p { return .move }
        return .copy
    }

    @discardableResult
    static func perform(_ p: Payload, at target: (folder: UUID, index: Int?)) -> Bool {
        switch p {
        case .node(let id): return BookmarkStore.shared.move(id: id, to: target.folder, index: target.index)
        case .link(let url, let title): return BookmarkStore.shared.add(title: title, url: url, folder: target.folder, index: target.index) != nil
        }
    }

    /// A picture of `view` for the drag.
    static func snapshot(of view: NSView) -> NSImage {
        let image = NSImage(size: view.bounds.size)
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            image.addRepresentation(rep)
        }
        return image
    }

    static let dragThreshold: CGFloat = 3
    /// Resting a drag on a folder this long opens its dropdown (Chrome's spring-loaded folders).
    static let springDelay: TimeInterval = 0.5
}

/// A folder's dropdown under the bookmarks bar, and the folders' dropdowns cascading from it. A
/// panel rather than an NSMenu so its rows can be dragged and dropped on: reordered, moved out to
/// the bar, into a subfolder, or a link dropped in.
@MainActor
final class BookmarkMenuController {
    static let shared = BookmarkMenuController()

    fileprivate(set) var panels: [BookmarkMenuPanel] = []
    private weak var bar: BookmarksBarView?
    private weak var anchor: BookmarkBarItemView?
    private weak var returnKeyWindow: NSWindow?
    private var clickMonitor: Any?
    private var resignObserver: Any?
    private var dragWatch: Timer?
    /// The drag source while a drag from a dropdown runs (its panel may close under it).
    private var dragSource: NSView?
    /// The mouse-down that closed the dropdown, so the release on its own folder doesn't reopen it.
    private(set) var closingEvent: (folder: UUID, number: Int)?

    var rootFolderID: UUID? { panels.first?.folderID }
    var isOpen: Bool { !panels.isEmpty }

    func isRoot(_ folder: UUID, in bar: BookmarksBarView) -> Bool { rootFolderID == folder && self.bar === bar }
    func isOpen(in bar: BookmarksBarView) -> Bool { isOpen && self.bar === bar }

    // MARK: Opening and closing

    func open(_ folder: BookmarkNode, under anchor: BookmarkBarItemView, bar: BookmarksBarView, byDrag: Bool = false) {
        if isRoot(folder.id, in: bar), self.anchor === anchor { return }
        guard let host = anchor.window else { return }
        let wasOpen = isOpen
        closeAll(restoreFocus: false)
        self.bar = bar
        self.anchor = anchor
        let panel = BookmarkMenuPanel(folderID: folder.id, level: 0, controller: self)
        let rect = host.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        present(panel, host: host, topLeft: NSPoint(x: rect.minX, y: rect.minY - 4), avoid: nil)
        anchor.menuOpen = true
        installMonitors()
        if !byDrag, NSEvent.pressedMouseButtons == 0 {
            if !wasOpen { returnKeyWindow = NSApp.keyWindow }
            panel.makeKey()
        }
    }

    /// Opens `folder` beside `row`, closing deeper dropdowns.
    func openSubmenu(_ folder: UUID, from row: BookmarkMenuRowView, level: Int) {
        if panels.count > level + 1, panels[level + 1].folderID == folder { return }
        close(above: level)
        guard let parent = panels.indices.contains(level) ? panels[level] : nil, let host = parent.parent else { return }
        let rect = parent.convertToScreen(row.convert(row.bounds, to: nil))
        let panel = BookmarkMenuPanel(folderID: folder, level: level + 1, controller: self)
        present(panel, host: host, topLeft: NSPoint(x: parent.frame.maxX - 2, y: rect.maxY + BookmarkMenuMetrics.padding),
                avoid: parent.frame)
        parent.list.openFolder = folder
    }

    private func present(_ panel: BookmarkMenuPanel, host: NSWindow, topLeft: NSPoint, avoid: NSRect?) {
        guard panel.reload() else { return }
        panel.appearance = host.effectiveAppearance
        let screen = (host.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        var size = panel.list.idealSize
        size.height = min(size.height, max(80, topLeft.y - screen.minY - 4))
        var origin = NSPoint(x: topLeft.x, y: topLeft.y - size.height)
        if origin.x + size.width > screen.maxX {
            // A submenu that doesn't fit on the right opens to the left of its parent.
            origin.x = avoid.map { $0.minX - size.width + 2 } ?? (screen.maxX - size.width)
        }
        origin.x = max(origin.x, screen.minX)
        origin.y = max(origin.y, screen.minY)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        host.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        panel.invalidateShadow()
        panels.append(panel)
    }

    func close(above level: Int) {
        while panels.count > level + 1 {
            let p = panels.removeLast()
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
        }
        if panels.indices.contains(level) { panels[level].list.openFolder = nil }
    }

    func closeAll(restoreFocus: Bool = true) {
        guard isOpen else { return }
        let wasKey = panels.contains { $0.isKeyWindow }
        close(above: -1)
        anchor?.menuOpen = false
        anchor = nil
        removeMonitors()
        if restoreFocus, wasKey, let w = returnKeyWindow, w.isVisible { w.makeKey() }
        returnKeyWindow = nil
    }

    /// The bookmarks changed (a context menu's Delete or Rename): every dropdown shows them again;
    /// one whose folder went closes.
    func reload() {
        guard isOpen, dragSource == nil else { return }
        for (i, p) in panels.enumerated() where !p.reload() {
            close(above: i - 1)
            if i == 0 { closeAll() }
            return
        }
        for p in panels {
            var f = p.frame
            let top = f.maxY
            let floor = (p.screen ?? NSScreen.main)?.visibleFrame.minY ?? 0
            f.size = NSSize(width: p.list.idealSize.width, height: min(p.list.idealSize.height, max(80, top - floor - 4)))
            f.origin.y = top - f.height
            p.setFrame(f, display: true)
        }
    }

    private func installMonitors() {
        if clickMonitor == nil {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] e in
                MainActor.assumeIsolated {
                    guard let self, !self.panels.contains(where: { $0 === e.window }) else { return }
                    if let id = self.rootFolderID { self.closingEvent = (id, e.eventNumber) }
                    self.closeAll(restoreFocus: false)
                }
                return e
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closeAll(restoreFocus: false) }
            }
        }
    }

    private func removeMonitors() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
        resignObserver = nil
    }

    // MARK: Dragging

    /// A drag began from a dropdown row, or entered the bar or a dropdown: once the button is up
    /// (dropped or given up), the dropdowns go, as Chrome's do.
    func watchDrag(source: NSView? = nil) {
        if let source { dragSource = source }
        guard dragWatch == nil else { return }
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.dragWatch?.invalidate()
                self.dragWatch = nil
                self.dragSource = nil
                self.closeAll(restoreFocus: false)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        dragWatch = t
    }

    // MARK: Rows' actions

    func activate(_ node: BookmarkNode, newTab: Bool) {
        let bar = self.bar
        closeAll()
        bar?.openFromMenu(node, newTab: newTab)
    }

    func openAll(in folder: UUID) {
        let bar = self.bar
        closeAll()
        bar?.openAll(in: folder)
    }

    func contextMenu(for node: BookmarkNode) -> NSMenu? { bar?.itemMenu(node) }

    func icon(for node: BookmarkNode) -> NSImage? { bar?.favicon(for: node) }
}

enum BookmarkMenuMetrics {
    static let rowHeight: CGFloat = 22
    static let padding: CGFloat = 5
    static let separator: CGFloat = 11
    static let minWidth: CGFloat = 180
    static let maxWidth: CGFloat = 340
    static let corner: CGFloat = 8
    static let font = NSFont.menuFont(ofSize: 13)
}

/// One dropdown: a menu-material panel holding a scrolling list of rows.
final class BookmarkMenuPanel: NSPanel {
    let folderID: UUID
    let depth: Int
    let list: BookmarkMenuListView
    private let scroll = NSScrollView()
    private weak var controller: BookmarkMenuController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @MainActor init(folderID: UUID, level: Int, controller: BookmarkMenuController) {
        self.folderID = folderID
        self.depth = level
        self.controller = controller
        list = BookmarkMenuListView(folderID: folderID, level: level, controller: controller)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = BookmarkMenuMetrics.corner
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = list
        scroll.autoresizingMask = [.width, .height]
        effect.addSubview(scroll)
        contentView = effect
        scroll.frame = effect.bounds
    }

    /// Rebuilds the rows from the store; false when the folder is gone.
    @MainActor func reload() -> Bool {
        guard let folder = BookmarkStore.shared.node(folderID), folder.isFolder else { return false }
        list.show(folder)
        return true
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        list.frame.size.width = scroll.contentSize.width
    }

    override func cancelOperation(_ sender: Any?) { MainActor.assumeIsolated { controller?.closeAll() } }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            MainActor.assumeIsolated { controller?.closeAll() }
            return
        }
        // ← closes a submenu, as in a menu.
        if event.keyCode == 123, depth > 0 {
            MainActor.assumeIsolated { controller?.close(above: depth - 1) }
            return
        }
        super.keyDown(with: event)
    }
}

/// The rows of one dropdown, and its drop target.
@MainActor
final class BookmarkMenuListView: NSView {
    let folderID: UUID
    let level: Int
    private weak var controller: BookmarkMenuController?
    private var rows: [BookmarkMenuRowView] = []
    var debugRows: [BookmarkMenuRowView] { rows }
    private var extras: [NSView] = []
    private let indicator = NSView()
    private var springWork: DispatchWorkItem?
    private var hoverWork: DispatchWorkItem?
    private var drop: (payload: BookmarkDropping.Payload, slot: BookmarkDropSlot)?
    private(set) var idealSize = NSSize(width: BookmarkMenuMetrics.minWidth, height: 40)
    /// The folder whose submenu is open beside this one: its row stays highlighted.
    var openFolder: UUID? { didSet { refreshHighlights() } }

    init(folderID: UUID, level: Int, controller: BookmarkMenuController) {
        self.folderID = folderID
        self.level = level
        self.controller = controller
        super.init(frame: .zero)
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 1
        indicator.isHidden = true
        registerForDraggedTypes(BookmarkDropping.types)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(_ folder: BookmarkNode) {
        (rows as [NSView] + extras).forEach { $0.removeFromSuperview() }
        extras = []
        let kids = folder.children ?? []
        rows = kids.map { BookmarkMenuRowView(kind: .node($0), list: self, icon: controller?.icon(for: $0)) }
        var all: [NSView] = rows
        if kids.isEmpty {
            let empty = BookmarkMenuRowView(kind: .empty, list: self, icon: nil)
            extras.append(empty)
            all.append(empty)
        }
        let urls = folder.allBookmarks.compactMap(\.url)
        if urls.count > 1 {
            let sep = NSBox()
            sep.boxType = .separator
            extras.append(sep)
            all.append(sep)
            let openAll = BookmarkMenuRowView(kind: .openAll(urls.count), list: self, icon: nil)
            extras.append(openAll)
            all.append(openAll)
        }
        let p = BookmarkMenuMetrics.padding
        var y = p
        var width = BookmarkMenuMetrics.minWidth
        for v in all {
            addSubview(v)
            if v is NSBox {
                v.frame = NSRect(x: 10, y: y + (BookmarkMenuMetrics.separator - 1) / 2, width: 0, height: 1)
                y += BookmarkMenuMetrics.separator
            } else {
                v.frame = NSRect(x: 0, y: y, width: 0, height: BookmarkMenuMetrics.rowHeight)
                y += BookmarkMenuMetrics.rowHeight
            }
            if let r = v as? BookmarkMenuRowView { width = max(width, r.idealWidth) }
        }
        addSubview(indicator)
        width = min(width, BookmarkMenuMetrics.maxWidth)
        idealSize = NSSize(width: width, height: y + p)
        frame.size = idealSize
        indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        needsLayout = true
        refreshHighlights()
    }

    override func layout() {
        super.layout()
        for v in subviews where v !== indicator {
            let inset: CGFloat = v is NSBox ? 10 : 0
            v.frame = NSRect(x: inset, y: v.frame.minY, width: bounds.width - 2 * inset, height: v.frame.height)
        }
    }

    // MARK: Hover

    func hover(_ row: BookmarkMenuRowView?) {
        hoverWork?.cancel()
        hoverWork = nil
        for r in rows { r.hovered = r === row }
        guard let row, case .node(let n) = row.kind else { return }
        // Back on the folder whose submenu is open: only what's deeper than that goes.
        if n.isFolder, openFolder == n.id { controller?.close(above: level + 1); return }
        let work = DispatchWorkItem { [weak self, weak row] in
            MainActor.assumeIsolated {
                guard let self, let row, row.hovered else { return }
                if n.isFolder {
                    self.controller?.openSubmenu(n.id, from: row, level: self.level)
                } else {
                    self.controller?.close(above: self.level)
                }
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (n.isFolder ? 0.2 : 0.3), execute: work)
    }

    func click(_ row: BookmarkMenuRowView, newTab: Bool) {
        switch row.kind {
        case .node(let n):
            if n.isFolder {
                controller?.openSubmenu(n.id, from: row, level: level)
            } else {
                controller?.activate(n, newTab: newTab)
            }
        case .openAll:
            controller?.openAll(in: folderID)
        case .empty:
            break
        }
    }

    func contextMenu(for node: BookmarkNode) -> NSMenu? { controller?.contextMenu(for: node) }

    func dragBegan(from row: BookmarkMenuRowView) { controller?.watchDrag(source: row) }

    private func refreshHighlights() {
        for r in rows {
            guard case .node(let n) = r.kind else { continue }
            let lit = dropFolderIndex.map { rows.indices.contains($0) && rows[$0] === r } ?? false
            r.dropTarget = n.isFolder && (openFolder == n.id || lit)
        }
    }

    private var dropFolderIndex: Int? {
        if case .into(let i)? = drop?.slot { return i }
        return nil
    }

    // MARK: Dropping

    private var children: [BookmarkNode] { BookmarkStore.shared.node(folderID)?.children ?? [] }

    private func slot(for info: NSDraggingInfo) -> BookmarkDropSlot {
        let y = convert(info.draggingLocation, from: nil).y
        let spans = rows.map { r -> BookmarkDrag.Span in
            let folder: Bool
            if case .node(let n) = r.kind { folder = n.isFolder } else { folder = false }
            return BookmarkDrag.Span(start: r.frame.minY, end: r.frame.maxY, isFolder: folder)
        }
        return BookmarkDrag.slot(at: y, in: spans)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.watchDrag()
        hover(nil)
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let payload = BookmarkDropping.payload(from: sender.draggingPasteboard) else { return clear() }
        let s = slot(for: sender)
        guard BookmarkDropping.target(payload, at: s, parent: folderID, children: children) != nil else { return clear() }
        if drop?.slot != s { setDrop(payload, s) }
        return BookmarkDropping.operation(payload)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { _ = clear() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let payload = BookmarkDropping.payload(from: sender.draggingPasteboard) else { return false }
        let s = slot(for: sender)
        _ = clear()
        guard let t = BookmarkDropping.target(payload, at: s, parent: folderID, children: children) else { return false }
        return BookmarkDropping.perform(payload, at: t)
    }

    private func setDrop(_ payload: BookmarkDropping.Payload, _ s: BookmarkDropSlot) {
        drop = (payload, s)
        springWork?.cancel()
        springWork = nil
        switch s {
        case .insert(let i):
            let y: CGFloat
            if rows.isEmpty { y = BookmarkMenuMetrics.padding } else if i < rows.count { y = rows[i].frame.minY } else { y = rows[rows.count - 1].frame.maxY }
            indicator.frame = NSRect(x: 8, y: y - 1, width: bounds.width - 16, height: 2)
            indicator.isHidden = false
        case .into(let i):
            indicator.isHidden = true
            guard rows.indices.contains(i), case .node(let n) = rows[i].kind else { break }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, case .into(let j)? = self.drop?.slot, j == i, self.rows.indices.contains(i) else { return }
                    self.controller?.openSubmenu(n.id, from: self.rows[i], level: self.level)
                }
            }
            springWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + BookmarkDropping.springDelay, execute: work)
        }
        refreshHighlights()
    }

    private func clear() -> NSDragOperation {
        springWork?.cancel()
        springWork = nil
        if drop != nil {
            drop = nil
            indicator.isHidden = true
            refreshHighlights()
        }
        return []
    }
}

/// One row of a dropdown: a bookmark (favicon and title), a folder (glyph, title, ›), the
/// "(empty)" line or Open All.
@MainActor
final class BookmarkMenuRowView: NSView, NSDraggingSource {
    enum Kind { case node(BookmarkNode), empty, openAll(Int) }

    let kind: Kind
    private weak var list: BookmarkMenuListView?
    private let fill = NSView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var press: NSEvent?
    var hovered = false { didSet { if hovered != oldValue { refresh() } } }
    var dropTarget = false { didSet { if dropTarget != oldValue { refresh() } } }

    private var node: BookmarkNode? { if case .node(let n) = kind { return n } else { return nil } }

    init(kind: Kind, list: BookmarkMenuListView, icon image: NSImage?) {
        self.kind = kind
        self.list = list
        super.init(frame: .zero)
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 4
        fill.layer?.cornerCurve = .continuous
        addSubview(fill)
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.font = BookmarkMenuMetrics.font
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        chevron.image = SidebarSymbols.image("chevron.right", size: 9, weight: .semibold)
        switch kind {
        case .node(let n):
            label.stringValue = n.isFolder ? (n.title.isEmpty ? "Untitled Folder" : n.title) : n.displayTitle
            icon.image = n.isFolder ? SidebarSymbols.image("folder", size: 13) : (image.map(Self.sized) ?? SidebarSymbols.image("globe", size: 13))
            chevron.isHidden = !n.isFolder
            toolTip = n.url
            setAccessibilityRole(n.isFolder ? .menuButton : .menuItem)
        case .empty:
            label.stringValue = "(empty)"
            chevron.isHidden = true
        case .openAll(let n):
            label.stringValue = "Open All (\(n)) in New Tabs"
            chevron.isHidden = true
            setAccessibilityRole(.menuItem)
        }
        for v in [icon, label, chevron] as [NSView] { addSubview(v) }
        setAccessibilityElement(true)
        setAccessibilityLabel(label.stringValue)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func sized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    private var hasIcon: Bool { if case .node = kind { return true } else { return false } }
    private var textX: CGFloat { hasIcon ? 34 : 14 }

    var idealWidth: CGFloat {
        textX + ceil(label.attributedStringValue.size().width) + 4 + (chevron.isHidden ? 0 : 18) + 14
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let h = bounds.height
        fill.frame = bounds.insetBy(dx: 5, dy: 0)
        icon.frame = NSRect(x: 12, y: (h - 16) / 2, width: 16, height: 16)
        let lh = ceil(label.intrinsicContentSize.height)
        let right: CGFloat = chevron.isHidden ? 12 : 28
        label.frame = NSRect(x: textX, y: ((h - lh) / 2).rounded(), width: max(0, bounds.width - textX - right), height: lh)
        chevron.frame = NSRect(x: bounds.width - 12 - 9, y: (h - 9) / 2, width: 9, height: 9)
        icon.isHidden = !hasIcon
    }

    private func refresh() {
        let enabled: Bool
        if case .empty = kind { enabled = false } else { enabled = true }
        let lit = enabled && (hovered || dropTarget)
        fill.layer?.backgroundColor = (lit ? NSColor.selectedContentBackgroundColor : .clear).cgColor
        label.textColor = !enabled ? .tertiaryLabelColor : (lit ? .selectedMenuItemTextColor : .labelColor)
        chevron.contentTintColor = lit ? .selectedMenuItemTextColor : .secondaryLabelColor
        if node?.isFolder == true { icon.contentTintColor = lit ? .selectedMenuItemTextColor : .secondaryLabelColor }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { list?.hover(self) }
    override func mouseExited(with event: NSEvent) { if hovered { hovered = false } }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let node, let menu = list?.contextMenu(for: node) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        press = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let p = press, let node else { return }
        let d = hypot(event.locationInWindow.x - p.locationInWindow.x, event.locationInWindow.y - p.locationInWindow.y)
        guard d > BookmarkDropping.dragThreshold else { return }
        press = nil
        let item = NSDraggingItem(pasteboardWriter: BookmarkDropping.pasteboardItem(for: node))
        item.setDraggingFrame(bounds, contents: BookmarkDropping.snapshot(of: self))
        list?.dragBegan(from: self)
        beginDraggingSession(with: [item], event: p, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard press != nil else { return }
        press = nil
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        list?.click(self, newTab: event.modifierFlags.contains(.command))
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, let node, !node.isFolder else { return }
        list?.click(self, newTab: true)
    }

    override func menu(for event: NSEvent) -> NSMenu? { node.flatMap { list?.contextMenu(for: $0) } }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy] : [.copy]
    }
}

// MARK: Debug

extension BookmarkDropping {
    /// from://debug?bookmarks=<step>, for scenarios (a drag itself needs a hand on the mouse):
    /// `drop:<id>,<parent>,insert|into,<i>` drops a bookmark as the bar or a dropdown would,
    /// `link:<url>,<parent>,<i>` drops a link, `menu:<n>` opens the bar's n-th item's dropdown,
    /// `sub:<row>` the open dropdown's row's submenu, `close` closes them. Each logs the outcome.
    static func debug(_ step: String, window: NSWindow?) {
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        let args = parts.count > 1 ? parts[1].split(separator: ",").map(String.init) : []
        let menus = BookmarkMenuController.shared
        switch parts.first {
        case "drop":
            guard args.count == 4, let id = UUID(uuidString: args[0]), let parent = UUID(uuidString: args[1]),
                  let i = Int(args[3]) else { return CraLog.note("bookmarks debug: bad drop") }
            let slot: BookmarkDropSlot = args[2] == "into" ? .into(i) : .insert(i)
            let kids = BookmarkStore.shared.node(parent)?.children ?? []
            guard let t = target(.node(id), at: slot, parent: parent, children: kids) else {
                return CraLog.note("bookmarks debug: drop refused")
            }
            CraLog.note("bookmarks debug: drop \(perform(.node(id), at: t) ? "moved" : "failed")")
        case "link":
            guard args.count == 3, let parent = UUID(uuidString: args[1]), let i = Int(args[2]) else { return }
            let p = Payload.link(url: args[0], title: URL(string: args[0])?.host ?? args[0])
            let kids = BookmarkStore.shared.node(parent)?.children ?? []
            guard let t = target(p, at: .insert(i), parent: parent, children: kids) else { return CraLog.note("bookmarks debug: link refused") }
            CraLog.note("bookmarks debug: link \(perform(p, at: t) ? "added" : "failed")")
        case "menu":
            func bars(_ v: NSView) -> [BookmarksBarView] { (v as? BookmarksBarView).map { [$0] } ?? v.subviews.flatMap(bars) }
            let all = (window.map { [$0] + ($0.childWindows ?? []) } ?? []).compactMap(\.contentView).flatMap(bars)
            guard let n = args.first.flatMap(Int.init), let bar = all.first(where: { !$0.isHiddenOrHasHiddenAncestor }) ?? all.first,
                  let item = bar.subviews.compactMap({ $0 as? BookmarkBarItemView }).dropFirst(n).first, item.node.isFolder else {
                return CraLog.note("bookmarks debug: no folder there (window \(window != nil), bars \(all.count))")
            }
            menus.open(item.node, under: item, bar: bar)
            menus.debugLog()
        case "sub":
            guard let r = args.first.flatMap(Int.init) else { return }
            menus.debugOpenSubmenu(row: r)
            menus.debugLog()
        case "close":
            menus.closeAll()
            menus.debugLog()
        default:
            CraLog.note("bookmarks debug: unknown step")
        }
    }
}

extension BookmarkMenuController {
    func debugOpenSubmenu(row: Int) {
        guard let p = panels.last, let r = p.list.debugRows.dropFirst(row).first, case .node(let n) = r.kind, n.isFolder else { return }
        openSubmenu(n.id, from: r, level: p.depth)
    }

    func debugLog() {
        let shown = panels.map { p in
            "[" + p.list.debugRows.map { r -> String in
                if case .node(let n) = r.kind { return n.isFolder ? n.title + "/" : n.displayTitle }
                return "-"
            }.joined(separator: ",") + "]@\(Int(p.frame.width))x\(Int(p.frame.height))"
        }
        CraLog.note("bookmarks debug: dropdowns \(shown.isEmpty ? "none" : shown.joined(separator: " > "))")
    }
}
