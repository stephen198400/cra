import AppKit

/// Chrome's bookmarks bar, in AppKit: a thin row under the toolbar (at the top of the card when
/// the address is in the sidebar) with the Bookmarks Bar root's bookmarks and folders. A click opens
/// a bookmark in the pane's tab, ⌘-click or a middle click in a new tab behind it; a folder opens
/// a dropdown of what it holds (BookmarkMenuController). What doesn't fit goes in the » menu at the
/// end, as in Chrome. Bookmarks and folders drag along the bar, onto a folder (resting there opens
/// it) and in and out of the dropdowns; a link dragged in from a page or another app is bookmarked
/// where it drops.
///
/// One bar per pane card, like PaneToolbarView: it reads the stores inside an observation scope
/// and rebuilds its buttons only when what they show changed.
@MainActor
final class BookmarksBarView: NSView {
    /// Chrome's bar is 28–30 pt; From's (the reference) is 30.
    static let height: CGFloat = 30
    static let itemHeight: CGFloat = 24
    static let maxTitleWidth: CGFloat = 150
    /// The first item's icon lines up with the toolbar's first glyph (centred 21 pt in, Arc 1.171).
    static let inset: CGFloat = 8
    /// Between hover boxes: with each box's 6 pt padding, ~18 pt between one title and the next icon
    /// (Dia's bar, which the user's design follows).
    static let gap: CGFloat = 6

    var paneTabID: UUID? { didSet { if paneTabID != oldValue { update(build()) } } }
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let favicons: FaviconCache
    private var bookmarks: BookmarkStore { .shared }

    private struct Model: Equatable {
        struct Item: Equatable { let node: BookmarkNode; let icon: NSImage? }
        /// So two tabs' bars never compare equal (a retarget applies its model directly).
        var tabID: UUID?
        var items: [Item] = []
        var fill = NSColor.white
        var fg = NSColor.black.withAlphaComponent(0.8)
        var fgDim = NSColor.black.withAlphaComponent(0.5)
        var hover = NSColor.black.withAlphaComponent(0.06)
        var hairline = NSColor.black.withAlphaComponent(0.08)
    }

    private var model = Model()
    private var itemViews: [BookmarkBarItemView] = []
    private let overflow = ToolbarGlyphButton()
    private let hairline = NSView()
    /// Bookmarks laid past the bar's end, in the » menu.
    private var overflowed: [BookmarkNode] = []
    /// Where a drag over the bar would drop: the line between two items, or a folder lit up.
    private let dropIndicator = NSView()
    private var drop: (payload: BookmarkDropping.Payload, slot: BookmarkDropSlot)?
    private var springWork: DispatchWorkItem?

    init(paneTabID: UUID?, store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.paneTabID = paneTabID
        self.store = store
        self.ui = ui
        self.actions = actions
        self.favicons = favicons
        super.init(frame: .zero)
        wantsLayer = true
        hairline.wantsLayer = true
        addSubview(hairline)
        overflow.isHidden = true
        overflow.action = { [weak self] in self?.showOverflowMenu() }
        addSubview(overflow)
        dropIndicator.wantsLayer = true
        dropIndicator.layer?.cornerRadius = 1
        dropIndicator.isHidden = true
        addSubview(dropIndicator)
        registerForDraggedTypes(BookmarkDropping.types)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Bookmarks Bar")
        update(build())
        // The bookmarks, their favicons and the page's colour: rebuilt when any of them changes.
        observeChanges(of: { [weak self] in self?.build() ?? Model() }) { [weak self] m in self?.update(m) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: Model

    private func update(_ m: Model) {
        guard m != model else { return }
        let old = model
        model = m
        apply(old: old)
    }

    private func build() -> Model {
        var m = Model()
        m.tabID = paneTabID
        m.items = bookmarks.barItems.map { node in
            Model.Item(node: node, icon: node.url.flatMap { favicons.image(for: $0) })
        }
        // The toolbar's colour rule (ToolbarColor), so bar and toolbar read as one strip.
        let item = paneTabID.flatMap { store.item($0) } ?? store.selectedTab(window: ui.windowID)
        let nav = item.map { ui.navState(for: $0.id) } ?? TabNavState()
        let palette = store.focusedSpace(window: ui.windowID).theme.palette
        if item?.isEmptyTab == true {
            m.fill = palette.isDark ? NSColor.white.withAlphaComponent(0.025) : NSColor.black.withAlphaComponent(0.03)
            m.fg = NSColor(palette.textSecondary)
            m.fgDim = NSColor(palette.textTertiary)
            m.hover = palette.isDark ? NSColor.white.withAlphaComponent(0.1) : NSColor.black.withAlphaComponent(0.06)
            m.hairline = .clear
            return m
        }
        // Dia's bar: the toolbar's own fill and inks, no rule between them, one band with the site's header.
        // A Developer Mode site's toolbar is the space's developer colour; the bar follows it.
        let inSplit = ui.splitPaneIDs.count > 1
        if !inSplit, let url = item?.tab?.url, store.settings.isDeveloperMode(url: url) {
            let theme = store.focusedSpace(window: ui.windowID).theme
            m.fill = theme.developerBarColor
            let ink = NSColor.white.blended(withFraction: 0.07, of: m.fill) ?? .white
            m.fg = ink
            m.fgDim = ink.withAlphaComponent(0.75)
            m.hover = NSColor.white.withAlphaComponent(0.08)
            m.hairline = .clear
            return m
        }
        let hex = ToolbarColor.hex(reported: nav.themeColor, remembered: item?.tab?.themeColor)
        let light = (hex.flatMap(HexColor.luminance) ?? 1) > 0.6
        m.fill = hex.map { NSColor(hex: $0) } ?? .white
        m.fg = light ? NSColor.black.withAlphaComponent(0.8) : NSColor(hex: "#E4E0D4")
        m.fgDim = light ? NSColor.black.withAlphaComponent(0.6) : NSColor(hex: "#F0E6CC").withAlphaComponent(0.9)
        m.hover = light ? NSColor.black.withAlphaComponent(0.06) : NSColor.white.withAlphaComponent(0.1)
        m.hairline = .clear
        return m
    }

    private func apply(old: Model) {
        let m = model
        layer?.backgroundColor = m.fill.cgColor
        hairline.layer?.backgroundColor = m.hairline.cgColor
        overflow.configure(symbol: "chevron.right.2", image: nil, help: "More Bookmarks", enabled: true, width: 24, iconSize: 11,
                           tint: m.fgDim, hover: m.hover)
        overflow.cornerRadius = 6
        dropIndicator.layer?.backgroundColor = m.fg.cgColor
        if m.items != old.items || itemViews.count != m.items.count {
            itemViews.forEach { $0.removeFromSuperview() }
            itemViews = m.items.map { item in
                let v = BookmarkBarItemView(node: item.node)
                v.onOpen = { [weak self] node, newTab in self?.open(node, newTab: newTab) }
                v.onFolder = { [weak self] node, anchor, press in self?.toggleFolder(node, under: anchor, press: press) }
                v.onHover = { [weak self] node, anchor in self?.hovered(node, anchor) }
                v.menuProvider = { [weak self] node in self?.itemMenu(node) }
                addSubview(v, positioned: .below, relativeTo: dropIndicator)
                return v
            }
            // A dropdown that's open shows the change (a Delete or Rename from its rows' menu).
            BookmarkMenuController.shared.reload()
        }
        for (v, item) in zip(itemViews, m.items) {
            v.style(icon: item.icon, fg: m.fg, fgDim: m.fgDim, hover: m.hover)
            v.menuOpen = item.node.isFolder && BookmarkMenuController.shared.isRoot(item.node.id, in: self)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        hairline.frame = NSRect(x: 0, y: h - 1, width: w, height: 1)
        // A little high of centre: the bar's top meets the toolbar, its bottom the page.
        let y = ((h - Self.itemHeight) / 2).rounded(.down)
        let widths = itemViews.map(\.idealWidth)
        let gap = Self.gap
        let total = widths.reduce(0, +) + gap * CGFloat(max(0, widths.count - 1))
        let room = w - 2 * Self.inset
        let overflowW: CGFloat = 24
        let fitsAll = total <= room
        let limit = fitsAll ? room : room - overflowW - gap
        var x = Self.inset
        overflowed = []
        for (v, vw) in zip(itemViews, widths) {
            if x - Self.inset + vw <= limit + 0.5, overflowed.isEmpty {
                v.isHidden = false
                v.frame = NSRect(x: x, y: y, width: vw, height: Self.itemHeight)
                x += vw + gap
            } else {
                v.isHidden = true
                overflowed.append(v.node)
            }
        }
        overflow.isHidden = overflowed.isEmpty
        overflow.frame = NSRect(x: w - Self.inset - overflowW, y: y, width: overflowW, height: Self.itemHeight)
    }

    // MARK: Opening

    private func open(_ node: BookmarkNode, newTab: Bool) {
        guard let url = node.url else { return }
        actions.openBookmark(url, newTab, paneTabID)
    }

    /// A click on a folder opens its dropdown; on the folder whose dropdown that click just closed,
    /// it stays closed.
    private func toggleFolder(_ node: BookmarkNode, under anchor: BookmarkBarItemView, press: Int?) {
        let menus = BookmarkMenuController.shared
        if let c = menus.closingEvent, c.folder == node.id, c.number == press { return }
        if menus.isRoot(node.id, in: self) { menus.closeAll(); return }
        menus.open(node, under: anchor, bar: self)
    }

    /// With a dropdown open, the pointer moving onto another folder opens that one, as along a menu bar.
    private func hovered(_ node: BookmarkNode, _ anchor: BookmarkBarItemView) {
        let menus = BookmarkMenuController.shared
        guard node.isFolder, menus.isOpen(in: self), !menus.isRoot(node.id, in: self),
              NSEvent.pressedMouseButtons == 0 else { return }
        menus.open(node, under: anchor, bar: self)
    }

    // MARK: For the dropdowns

    func openFromMenu(_ node: BookmarkNode, newTab: Bool) { open(node, newTab: newTab) }

    func openAll(in folder: UUID) {
        let urls = bookmarks.node(folder)?.allBookmarks.compactMap(\.url) ?? []
        for u in urls { actions.openBookmark(u, true, paneTabID) }
    }

    func favicon(for node: BookmarkNode) -> NSImage? { node.url.flatMap { favicons.image(for: $0) } }

    // MARK: Dropping

    private func slot(for info: NSDraggingInfo) -> BookmarkDropSlot {
        let x = convert(info.draggingLocation, from: nil).x
        let spans = itemViews.filter { !$0.isHidden }.map {
            BookmarkDrag.Span(start: $0.frame.minX, end: $0.frame.maxX, isFolder: $0.node.isFolder)
        }
        return BookmarkDrag.slot(at: x, in: spans)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        BookmarkMenuController.shared.watchDrag()
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let payload = BookmarkDropping.payload(from: sender.draggingPasteboard) else { return clearDrop() }
        let s = slot(for: sender)
        guard BookmarkDropping.target(payload, at: s, parent: BookmarkTree.barID, children: bookmarks.barItems) != nil else {
            return clearDrop()
        }
        if drop?.slot != s { setDrop(payload, s) }
        return BookmarkDropping.operation(payload)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { _ = clearDrop() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let payload = BookmarkDropping.payload(from: sender.draggingPasteboard) else { return false }
        let s = slot(for: sender)
        _ = clearDrop()
        guard let t = BookmarkDropping.target(payload, at: s, parent: BookmarkTree.barID, children: bookmarks.barItems) else { return false }
        return BookmarkDropping.perform(payload, at: t)
    }

    private func setDrop(_ payload: BookmarkDropping.Payload, _ s: BookmarkDropSlot) {
        drop = (payload, s)
        springWork?.cancel()
        springWork = nil
        let visible = itemViews.filter { !$0.isHidden }
        for v in itemViews { v.dropTarget = false }
        switch s {
        case .insert(let i):
            let x: CGFloat
            if visible.isEmpty {
                x = Self.inset
            } else if i < visible.count {
                x = visible[i].frame.minX - (i == 0 ? 2 : Self.gap / 2)
            } else {
                x = visible[visible.count - 1].frame.maxX + Self.gap / 2
            }
            let h = Self.itemHeight - 4
            dropIndicator.frame = NSRect(x: x - 1, y: ((bounds.height - h) / 2).rounded(.down), width: 2, height: h)
            dropIndicator.isHidden = false
        case .into(let i):
            dropIndicator.isHidden = true
            guard visible.indices.contains(i) else { break }
            let v = visible[i]
            v.dropTarget = true
            // Resting on the folder opens it, so the drop can go somewhere inside.
            let work = DispatchWorkItem { [weak self, weak v] in
                MainActor.assumeIsolated {
                    guard let self, let v, v.dropTarget, case .into? = self.drop?.slot else { return }
                    BookmarkMenuController.shared.open(v.node, under: v, bar: self, byDrag: true)
                }
            }
            springWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + BookmarkDropping.springDelay, execute: work)
        }
    }

    private func clearDrop() -> NSDragOperation {
        springWork?.cancel()
        springWork = nil
        if drop != nil {
            drop = nil
            dropIndicator.isHidden = true
            for v in itemViews { v.dropTarget = false }
        }
        return []
    }

    private func showOverflowMenu() {
        let menu = NSMenu()
        for n in overflowed { menu.addItem(menuItem(for: n)) }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: overflow.bounds.maxY + 4), in: overflow)
    }

    /// A folder's contents, its folders as submenus, then Chrome's Open All.
    private func folderMenu(_ folder: BookmarkNode) -> NSMenu {
        let menu = NSMenu(title: folder.title)
        let kids = folder.children ?? []
        if kids.isEmpty {
            menu.addItem(withTitle: "(empty)", action: nil, keyEquivalent: "").isEnabled = false
            return menu
        }
        for n in kids { menu.addItem(menuItem(for: n)) }
        let urls = folder.allBookmarks.compactMap(\.url)
        if urls.count > 1 {
            menu.addItem(.separator())
            menu.addItem(BarMenuAction.item("Open All (\(urls.count)) in New Tabs") { [weak self] in
                for u in urls { self?.actions.openBookmark(u, true, self?.paneTabID) }
            })
        }
        return menu
    }

    private func menuItem(for node: BookmarkNode) -> NSMenuItem {
        if node.isFolder {
            let item = NSMenuItem(title: node.title.isEmpty ? "Untitled Folder" : node.title, action: nil, keyEquivalent: "")
            item.image = SidebarSymbols.image("folder", size: 13)
            item.submenu = folderMenu(node)
            return item
        }
        let item = BarMenuAction.item(node.displayTitle) { [weak self] in
            // ⌘ with the menu's click opens it behind, like ⌘-click on the bar.
            let newTab = NSApp.currentEvent?.modifierFlags.contains(.command) == true
            self?.open(node, newTab: newTab)
        }
        let icon = node.url.flatMap { favicons.image(for: $0) } ?? SidebarSymbols.image("globe", size: 13)
        item.image = icon.map { Self.menuIcon($0) }
        item.toolTip = node.url
        return item
    }

    private static func menuIcon(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    // MARK: Context menus

    func itemMenu(_ node: BookmarkNode) -> NSMenu {
        let menu = NSMenu()
        if let url = node.url {
            menu.addItem(BarMenuAction.item("Open in New Tab") { [weak self] in self?.open(node, newTab: true) })
            menu.addItem(.separator())
            menu.addItem(BarMenuAction.item("Edit…") { [weak self] in self?.edit(node) })
            menu.addItem(BarMenuAction.item("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            })
        } else {
            let urls = node.allBookmarks.compactMap(\.url)
            let all = BarMenuAction.item("Open All in New Tabs") { [weak self] in
                for u in urls { self?.actions.openBookmark(u, true, self?.paneTabID) }
            }
            all.isEnabled = !urls.isEmpty
            menu.addItem(all)
            menu.addItem(.separator())
            menu.addItem(BarMenuAction.item("Rename…") { [weak self] in self?.edit(node) })
        }
        menu.addItem(BarMenuAction.item("Delete") { BookmarkStore.shared.remove(id: node.id) })
        menu.addItem(.separator())
        menu.addItem(hideItem())
        return menu
    }

    private func hideItem() -> NSMenuItem {
        BarMenuAction.item("Hide Bookmarks Bar", shortcut: "toggleBookmarksBar") { [weak self] in
            self?.store.settings.showBookmarksBar = false
        }
    }

    /// The empty part of the bar.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(BarMenuAction.item("Add Folder…") { [weak self] in self?.addFolder() })
        menu.addItem(.separator())
        menu.addItem(hideItem())
        return menu
    }

    /// Edit… (title and address) for a bookmark, Rename… for a folder.
    private func edit(_ node: BookmarkNode) {
        let alert = NSAlert()
        alert.messageText = node.isFolder ? "Rename Folder" : "Edit Bookmark"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let title = NSTextField(string: node.title)
        title.placeholderString = "Name"
        let url = NSTextField(string: node.url ?? "")
        url.placeholderString = "URL"
        let fields = node.isFolder ? [title] : [title, url]
        let stack = NSStackView(views: fields)
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: CGFloat(fields.count) * 22 + CGFloat(fields.count - 1) * 8)
        for f in fields { f.frame.size.width = 300 }
        alert.accessoryView = stack
        alert.window.initialFirstResponder = title
        let save = {
            BookmarkStore.shared.rename(id: node.id, to: title.stringValue)
            let typed = url.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !node.isFolder, !typed.isEmpty {
                BookmarkStore.shared.setURL(id: node.id, to: SuggestionEngine.looksLikeURL(typed) ? SuggestionEngine.urlFromInput(typed) : typed)
            }
        }
        if let window {
            alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { save() } }
        } else if alert.runModal() == .alertFirstButtonReturn {
            save()
        }
    }

    private func addFolder() {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: "New Folder")
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 22)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let add = { _ = BookmarkStore.shared.addFolder(title: field.stringValue.isEmpty ? "New Folder" : field.stringValue) }
        if let window {
            alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { add() } }
        } else if alert.runModal() == .alertFirstButtonReturn {
            add()
        }
    }
}

/// One bookmark or folder on the bar: favicon (or folder glyph), title up to 150 pt, and a small
/// chevron after a folder's name. A nameless bookmark is its icon alone, in a square.
@MainActor
final class BookmarkBarItemView: NSView, NSDraggingSource {
    let node: BookmarkNode
    var onOpen: (BookmarkNode, Bool) -> Void = { _, _ in }
    /// A click on a folder, with the number of the mouse-down that began it.
    var onFolder: (BookmarkNode, BookmarkBarItemView, Int?) -> Void = { _, _, _ in }
    var onHover: (BookmarkNode, BookmarkBarItemView) -> Void = { _, _ in }
    var menuProvider: ((BookmarkNode) -> NSMenu?)?
    /// A drag rests on this folder: it lights up as it would hovered.
    var dropTarget = false { didSet { if dropTarget != oldValue { refreshFill() } } }
    /// This folder's dropdown is open.
    var menuOpen = false { didSet { if menuOpen != oldValue { refreshFill() } } }
    private var press: NSEvent?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var hover = NSColor.clear
    private var hovering = false { didSet { if hovering != oldValue { refreshFill() } } }
    private var pressed = false { didSet { if pressed != oldValue { refreshFill() } } }

    private var unnamed: Bool { !node.isFolder && node.title.isEmpty }
    /// The hover box's padding either side, and the 16 pt favicon.
    static let pad: CGFloat = 6
    static let icon: CGFloat = 16

    init(node: BookmarkNode) {
        self.node = node
        super.init(frame: .zero)
        wantsLayer = true
        // The toolbar glyph buttons' rounded hover box (PaneToolbarView: 7 pt).
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.stringValue = node.isFolder && node.title.isEmpty ? "Untitled Folder" : node.title
        label.isHidden = unnamed
        chevron.image = SidebarSymbols.image("chevron.down", size: 8, weight: .semibold)
        chevron.isHidden = !node.isFolder
        for v in [icon, label, chevron] as [NSView] { addSubview(v) }
        toolTip = node.url ?? node.title
        setAccessibilityElement(true)
        setAccessibilityRole(node.isFolder ? .menuButton : .button)
        setAccessibilityLabel(node.displayTitle)
    }

    required init?(coder: NSCoder) { fatalError() }

    func style(icon image: NSImage?, fg: NSColor, fgDim: NSColor, hover: NSColor) {
        self.hover = hover
        if node.isFolder {
            icon.image = SidebarSymbols.image("folder", size: 13)
            icon.contentTintColor = fg
        } else if let image {
            icon.image = image
            icon.contentTintColor = image.isTemplate ? fgDim : nil
        } else {
            icon.image = SidebarSymbols.image("globe", size: 13)
            icon.contentTintColor = fgDim
        }
        label.textColor = fg
        chevron.contentTintColor = fgDim
        refreshFill()
    }

    var idealWidth: CGFloat {
        if unnamed { return BookmarksBarView.itemHeight + 4 }
        // A label cell draws its text 2 pt in from each side.
        let text = min(ceil(label.attributedStringValue.size().width) + 4, BookmarksBarView.maxTitleWidth)
        return Self.pad + Self.icon + 6 + text + (node.isFolder ? 5 + 8 : 0) + Self.pad
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let s = Self.icon
        if unnamed {
            icon.frame = NSRect(x: (bounds.width - s) / 2, y: (h - s) / 2, width: s, height: s)
            return
        }
        icon.frame = NSRect(x: Self.pad, y: (h - s) / 2, width: s, height: s)
        let lh = ceil(label.intrinsicContentSize.height)
        let textX = Self.pad + s + 6
        let chevronW: CGFloat = node.isFolder ? 5 + 8 : 0
        label.frame = NSRect(x: textX, y: ((h - lh) / 2).rounded(), width: max(0, bounds.width - textX - chevronW - Self.pad), height: lh)
        chevron.frame = NSRect(x: bounds.width - Self.pad - 8, y: (h - 8) / 2, width: 8, height: 8)
    }

    private func refreshFill() {
        layer?.backgroundColor = (hovering || pressed || dropTarget || menuOpen ? hover : .clear).cgColor
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        onHover(node, self)
    }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let menu = menuProvider?(node) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        // Opens on the release, so the press can start a drag instead.
        press = event
        pressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let p = press else { return }
        let d = hypot(event.locationInWindow.x - p.locationInWindow.x, event.locationInWindow.y - p.locationInWindow.y)
        guard d > BookmarkDropping.dragThreshold else { return }
        press = nil
        pressed = false
        let item = NSDraggingItem(pasteboardWriter: BookmarkDropping.pasteboardItem(for: node))
        item.setDraggingFrame(bounds, contents: BookmarkDropping.snapshot(of: self))
        beginDraggingSession(with: [item], event: p, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard let p = press else { return }
        press = nil
        pressed = false
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if node.isFolder {
            onFolder(node, self, p.eventNumber)
        } else {
            onOpen(node, event.modifierFlags.contains(.command))
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy] : [.copy]
    }

    /// The middle button opens a bookmark in a new tab, as in Chrome.
    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, !node.isFolder, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onOpen(node, true)
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?(node) }
}

/// A menu row that runs a closure (the bar's own; PaneToolbarView keeps its own private one).
private final class BarMenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }

    @MainActor static func item(_ title: String, shortcut: String? = nil, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = BarMenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(fire), keyEquivalent: "")
        item.target = a
        item.representedObject = a
        if let shortcut { item.showShortcut(of: shortcut) }
        return item
    }
}
