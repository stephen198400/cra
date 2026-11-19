import Foundation

/// The sidebar's menu for several tabs picked with ⌘/⇧-click (GitHub #356), row for row as Arc
public enum PickedTabsMenu {
    public static let sections: [[String]] = [
        ["copyLinks"],
        ["changeIcon", "mute"],
        ["openInSplitView", "duplicate", "moveTo", "newFolder"],
        ["archive", "archiveBelow"],
    ]

    /// A split holds at most four panes (Arc's); past that Open in Split View is dimmed. With
    /// "More than four panes in a split" on, `Picks.paneLimit` is eight (#498).
    public static let maxPanes = SplitPaneLimit.arc

    /// What the menu is opened on.
    public struct Picks: Equatable, Sendable {
        public var count: Int
        /// Whether an Easel is among the picks: Arc then leaves out the tab-only rows.
        public var anyEasel: Bool
        /// Whether the row right-clicked is in Today (Archive Tabs Below shows only there).
        public var clickedInToday: Bool
        /// Whether every pick is muted already, so the row unmutes them.
        public var allMuted: Bool
        /// Whether a pick plays sound or is muted, so Mute has something to do.
        public var anySound: Bool
        /// Whether a pick is in a split already (a split doesn't nest).
        public var anyInSplit: Bool
        /// The most panes a split holds (`SplitPaneLimit`).
        public var paneLimit: Int

        public init(count: Int, anyEasel: Bool = false, clickedInToday: Bool = true, allMuted: Bool = false,
                    anySound: Bool = false, anyInSplit: Bool = false, paneLimit: Int = PickedTabsMenu.maxPanes) {
            self.count = count
            self.anyEasel = anyEasel
            self.clickedInToday = clickedInToday
            self.allMuted = allMuted
            self.anySound = anySound
            self.anyInSplit = anyInSplit
            self.paneLimit = paneLimit
        }
    }

    public static func shows(_ id: String, for picks: Picks) -> Bool {
        switch id {
        case "changeIcon", "mute", "duplicate": !picks.anyEasel
        case "archiveBelow": !picks.anyEasel && picks.clickedInToday
        case "openInSplitView": picks.count >= 2 && !picks.anyInSplit
        default: true
        }
    }

    /// Arc dims Change Icon… and Archive Tabs Below for several tabs, Open in Split View past four
    /// panes, and Mute with nothing to mute.
    public static func isEnabled(_ id: String, for picks: Picks) -> Bool {
        switch id {
        case "changeIcon", "archiveBelow": false
        case "openInSplitView": picks.count <= picks.paneLimit
        case "mute": picks.anySound || picks.allMuted
        default: true
        }
    }

    public static func title(_ id: String, for picks: Picks) -> String {
        let n = picks.count
        return switch id {
        case "copyLinks": "Copy Links"
        case "changeIcon": "Change Icon…"
        case "mute": picks.allMuted ? "Unmute" : "Mute"
        case "openInSplitView": "Open in Split View"
        case "duplicate": "Duplicate"
        case "moveTo": "Move to"
        case "newFolder": "New Folder with \(n) Items"
        case "archive": picks.anyEasel ? "Archive Items" : "Archive Tabs"
        case "archiveBelow": "Archive Tabs Below"
        default: id
        }
    }

    /// The rows that show, in sections, as the menu draws them.
    public static func shown(for picks: Picks) -> [[String]] {
        sections.map { $0.filter { shows($0, for: picks) } }.filter { !$0.isEmpty }
    }
}
