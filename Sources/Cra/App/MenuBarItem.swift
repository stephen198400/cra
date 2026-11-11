import AppKit

/// The menu bar item of Settings ▸ Advanced ▸ "Keep Cra in the menu bar" (GitHub #231). Arc has
/// none, so it is a plain macOS status item: Cra's C mark as a template image, and a menu that
/// AppDelegate builds each time it opens (the shortcuts follow Settings ▸ Shortcuts).
@MainActor
final class MenuBarItem: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let build: (NSMenu) -> Void

    init(build: @escaping (NSMenu) -> Void) {
        self.build = build
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = Self.icon
        item.button?.setAccessibilityLabel("From")
        item.button?.toolTip = "From"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func remove() { NSStatusBar.system.removeStatusItem(item) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        build(menu)
    }

    /// This fork's mark is a globe, like its app icon. 16 pt, like the system's own items.
    static let icon: NSImage = {
        let image = NSImage(systemSymbolName: "globe", accessibilityDescription: "From")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) ?? NSImage()
        image.isTemplate = true
        return image
    }()
}
