import Foundation
import CraCore
import Testing

/// The menu on several picked sidebar tabs (GitHub #356): Arc's sections, Copy URLs and Share for
/// all of them at once.
struct PickedTabsMenuTests {
    private func rows(_ picks: PickedTabsMenu.Picks) -> [String] {
        PickedTabsMenu.shown(for: picks).map { $0.map { PickedTabsMenu.title($0, for: picks) }.joined(separator: "|") }
    }

    /// Arc 1.17x, read over AX on 11 Nov 2026 with two Today tabs picked.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/356"))
    func todayTabsGetArcsRows() {
        #expect(rows(.init(count: 2)) == [
            "Copy Links",
            "Change Icon…|Mute",
            "Open in Split View|Duplicate|Move to|New Folder with 2 Items",
            "Archive Tabs|Archive Tabs Below",
        ])
        let dimmed = PickedTabsMenu.shown(for: .init(count: 2)).joined().filter { !PickedTabsMenu.isEnabled($0, for: .init(count: 2)) }
        #expect(dimmed == ["changeIcon", "mute", "archiveBelow"])
    }

    /// The same Arc with an Easel among the picks: no tab-only rows, and Archive Items.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/356"))
    func anEaselLeavesOutTheTabOnlyRows() {
        #expect(rows(.init(count: 3, anyEasel: true)) == [
            "Copy Links",
            "Open in Split View|Move to|New Folder with 3 Items",
            "Archive Items",
        ])
    }

    /// A pinned tab picked with a Today one, right-clicked: the tab menu without Archive Tabs Below.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/356"))
    func aPinnedRowHasNoArchiveTabsBelow() {
        #expect(rows(.init(count: 2, clickedInToday: false)).last == "Archive Tabs")
    }

    /// Five picks: Open in Split View stays, dimmed (a split takes four).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/356"))
    func splitViewIsDimmedPastFourPicks() {
        #expect(PickedTabsMenu.shows("openInSplitView", for: .init(count: 5)))
        #expect(!PickedTabsMenu.isEnabled("openInSplitView", for: .init(count: 5)))
        #expect(PickedTabsMenu.isEnabled("openInSplitView", for: .init(count: 4)))
        #expect(!PickedTabsMenu.shows("openInSplitView", for: .init(count: 3, anyInSplit: true)))
    }

    @Test func muteActsOnceSomethingPlaysOrIsMuted() {
        #expect(PickedTabsMenu.isEnabled("mute", for: .init(count: 2, anySound: true)))
        #expect(PickedTabsMenu.title("mute", for: .init(count: 2, allMuted: true)) == "Unmute")
        #expect(PickedTabsMenu.isEnabled("mute", for: .init(count: 2, allMuted: true)))
    }

}
