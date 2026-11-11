import CraCore
import Foundation
import Testing

/// The sidebar header's downloads button and its card.
struct DownloadsCardTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func live(_ id: UInt32, at offset: Double, received: Int64 = 0, total: Int64 = 0,
                      failed: Bool = false, cancelled: Bool = false) -> DownloadList.Live {
        var l = DownloadList.Live(id: id, name: "f\(id).bin", path: "/d/f\(id).bin", started: t0.addingTimeInterval(offset),
                                  received: received, total: total, percent: 0, updated: t0)
        l.failed = failed
        l.cancelled = cancelled
        return l
    }

    private func entry(_ name: String, at offset: Double) -> DownloadList.Entry {
        DownloadList.Entry(id: UUID(), path: "/d/" + name, date: t0.addingTimeInterval(offset))
    }

    @Test func theMarkFollowsWhatRuns() {
        #expect(DownloadsCard.mark([]) == .idle)
        // Ended ones don't count.
        #expect(DownloadsCard.mark([live(1, at: 0, failed: true), live(2, at: 0, cancelled: true)]) == .idle)
        // No size known yet: spinning, not an empty ring.
        #expect(DownloadsCard.mark([live(1, at: 0, received: 500)]) == .spinning)
        #expect(DownloadsCard.mark([live(1, at: 0, received: 250, total: 1000)]) == .progress(0.25))
        // Two together, one of unknown size counting as not started.
        #expect(DownloadsCard.mark([live(1, at: 0, received: 500, total: 1000), live(2, at: 1, received: 9)]) == .progress(0.5))
    }

    @Test func rowsPutRunningFirstThenNewestAndStopAtTheLimit() {
        let old = entry("old.zip", at: 0), gone = entry("gone.zip", at: 5), new = entry("new.pdf", at: 10)
        let failed = live(7, at: 20, failed: true), running = live(8, at: 2, received: 1, total: 10)
        let rows = DownloadsCard.rows(entries: [old, gone, new], live: [failed, running]) { $0 != gone.path }
        #expect(rows.map(\.name) == ["f8.bin", "f7.bin", "new.pdf", "old.zip"])
        let many = (0..<10).map { entry("e\($0)", at: Double($0)) }
        let limited = DownloadsCard.rows(entries: many, live: []) { _ in true }
        #expect(limited.count == DownloadsCard.limit)
        #expect(limited.first?.name == "e9")
        #expect(DownloadsCard.rows(entries: [], live: []) { _ in true }.isEmpty)
    }

    @Test func clearLeavesRunningDownloads() {
        let running = live(1, at: 0, received: 1, total: 2), failed = live(2, at: 1, failed: true)
        #expect(!DownloadsCard.canClear(entries: [], live: []))
        #expect(!DownloadsCard.canClear(entries: [], live: [running]))
        #expect(DownloadsCard.canClear(entries: [], live: [running, failed]))
        #expect(DownloadsCard.canClear(entries: [entry("a", at: 0)], live: []))
        #expect(DownloadsCard.afterClear(live: [running, failed]).map(\.id) == [1])
    }

    @Test func aNewRunningDownloadOpensTheCard() {
        let a = live(1, at: 0, received: 1, total: 2)
        #expect(DownloadsCard.started(seen: [], live: [a]))
        #expect(!DownloadsCard.started(seen: [1], live: [a]))
        #expect(!DownloadsCard.started(seen: [], live: [live(2, at: 0, failed: true)]))
        #expect(!DownloadsCard.started(seen: [], live: []))
    }

    /// The button sits 6 pt from the sidebar's edge, 32 pt, or 28 pt under 212 pt, and stays clear
    /// of the traffic lights (they and their margin end at 77 pt) down to the 164 pt minimum.
    @Test func theButtonAtTheHeadersRightEnd() {
        #expect(DownloadsCard.button(width: 260) == (222, 32))
        #expect(DownloadsCard.button(width: 211) == (177, 28))
        #expect(DownloadsCard.button(width: 164).x == 130)
        for w in stride(from: 164.0, through: 400, by: 1) {
            let b = DownloadsCard.button(width: w)
            #expect(b.x + b.size == w - SidebarHeaderLayout.edgeInset)
            #expect(b.x >= 77)
        }
    }

    @Test func cardHeight() {
        #expect(DownloadsCard.height(rows: 0) == 38 + 44 + 12 + 44)
        #expect(DownloadsCard.height(rows: 3) == 38 + 132 + 12 + 44)
    }

    /// The card is the sidebar's colour, opaque and lifted: lighter than the sidebar, keeping its hue,
    /// light on a light sidebar and dark on a dark one.
    @Test func surfaceIsALiftedPieceOfTheSidebar() {
        func luma(_ c: RGB) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
        let yellow = RGB(0.97, 0.84, 0.35), navy = RGB(0.05, 0.06, 0.2)
        let light = DownloadsCard.surface(sidebar: yellow, alpha: 1, dark: false)
        #expect(luma(light) > luma(yellow) && luma(light) > 0.8)
        #expect(light.b < light.r)  // still yellow
        let dark = DownloadsCard.surface(sidebar: navy, alpha: 1, dark: true)
        #expect(luma(dark) > luma(navy) && luma(dark) < 0.2)
        #expect(dark.b > dark.r)  // still blue
        // Translucent: flattened over the material, never transparent or out of range.
        let thin = DownloadsCard.surface(sidebar: navy, alpha: 0.4, dark: true)
        #expect(abs(thin.r - (0.2 * 0.6 + 0.05 * 0.4) * 0.93 - 0.07) < 1e-9)
        for c in [light, dark, thin] { #expect([c.r, c.g, c.b].allSatisfy { (0...1).contains($0) }) }
    }
}
