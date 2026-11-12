import CraCore
import Foundation
import Testing

/// Settings ▸ Advanced "When opening Cra, start on a new tab" (X DM 7 Nov 2026).
struct LaunchStartTests {
    @Test func offByDefaultAsInArc() throws {
        #expect(AppSettings().startOnNewTab == false, "Arc opens on the tab in use last")
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.startOnNewTab == false, "a settings.json from before the setting keeps Arc's launch")
        var on = AppSettings()
        on.startOnNewTab = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on)).startOnNewTab)
    }

    @Test(arguments: [
        (true, LaunchStart.Launch.opened, true),
        (false, .opened, false),
        // A link from another app opens its own tab, and that is what the window shows.
        (true, .forLink, false),
        (true, .firstRun, false),
    ])
    func startsOnNewTab(enabled: Bool, launch: LaunchStart.Launch, expected: Bool) {
        #expect(LaunchStart.startsOnNewTab(enabled: enabled, launch: launch) == expected)
    }

    @Test func launchKind() {
        #expect(LaunchStart.launch(firstRun: false, withLinks: false) == .opened)
        #expect(LaunchStart.launch(firstRun: false, withLinks: true) == .forLink)
        #expect(LaunchStart.launch(firstRun: true, withLinks: true) == .firstRun)
    }
}
