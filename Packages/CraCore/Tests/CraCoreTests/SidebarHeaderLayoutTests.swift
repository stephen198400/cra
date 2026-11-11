import CraCore
import Testing

/// The sidebar header row: the traffic lights and the downloads button. Arc's header layouts
/// (issue #287: toggle and ← → ↻, or ← → ••• under 212 pt) are gone; the toolbar has the
/// navigation (ToolbarComposition).
struct SidebarHeaderLayoutTests {
    @Test func theRowHoldsOnlyDownloads() {
        #expect(SidebarHeaderLayout.items() == [.downloads])
        #expect(SidebarHeaderLayout.items(developerPage: true) == [.downloads], "a Developer Mode page adds no navigation")
        #expect(!SidebarHeaderLayout.isNarrow(width: 212) && SidebarHeaderLayout.isNarrow(width: 211))
    }

    /// The ••• popover's tones from Arc's "Lab" theme (shadedDark 0.437, 0.336, −0.080):
    /// fill (17, 13, 0) and hovered row (81, 70, 26), within a channel step.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/287"))
    func moreMenuTones() {
        let ink = RGB(0.437, 0.336, -0.080)
        func bytes(_ c: RGB) -> [Double] { [c.r, c.g, c.b].map { ($0 * 255).rounded() } }
        let fill = bytes(SidebarMoreMenu.fill(shadedDark: ink)), hi = bytes(SidebarMoreMenu.highlight(shadedDark: ink))
        for (got, want) in zip(fill + hi, [17, 13, 0, 81, 70, 26] as [Double]) { #expect(abs(got - want) <= 2) }
        #expect(SidebarMoreMenu.height(rows: 2) == 96)
    }
}
