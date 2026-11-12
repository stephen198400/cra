import Foundation

/// The downloads button at the far right of the sidebar header and the card it opens (after the
/// From browser's downloads door): what is coming in, the last few files, Clear, and the Downloads
/// folder in the Finder. The button is always there; while downloads run it turns into a ring.
public enum DownloadsCard {
    /// As many rows as fit at a glance; the rest are in the Downloads folder.
    public static let limit = 6
    public static let width: Double = 300
    public static let rowHeight: Double = 44
    public static let headerHeight: Double = 38
    public static let footerHeight: Double = 44
    public static let emptyHeight: Double = 44
    /// Padding around the rows; also the hovered row's inset from the card's sides.
    public static let inset: Double = 6

    /// What the button draws.
    public enum Mark: Equatable, Sendable {
        /// The arrow.down.circle glyph: nothing running.
        case idle
        /// A ring filled this far (0…1): the running downloads' sizes are known.
        case progress(Double)
        /// A spinning arc: something runs whose size isn't known yet.
        case spinning
    }

    public static func mark(_ live: [DownloadList.Live]) -> Mark {
        let running = live.filter(\.running)
        guard !running.isEmpty else { return .idle }
        guard running.contains(where: { $0.total > 0 }), let p = DownloadList.progress(live) else { return .spinning }
        return .progress(p)
    }

    /// The card's rows, newest first: downloads still running on top, then finished files still on
    /// disk and the failed or cancelled ones of this session, at most `limit`.
    public static func rows(entries: [DownloadList.Entry], live: [DownloadList.Live], limit: Int = limit,
                            fileExists: (String) -> Bool) -> [DownloadList.Listed] {
        let running = live.filter(\.running).sorted { $0.started > $1.started }.map(DownloadList.Listed.live)
        let ended = (entries.filter { fileExists($0.path) }.map(DownloadList.Listed.finished)
            + live.filter { !$0.running }.map(DownloadList.Listed.live)).sorted { $0.date > $1.date }
        return Array((running + ended).prefix(max(0, limit)))
    }

    /// The card's height for its rows: the header, the rows (or "Nothing downloaded yet"), the footer.
    public static func height(rows: Int) -> Double {
        headerHeight + (rows == 0 ? emptyHeight : Double(rows) * rowHeight) + 2 * inset + footerHeight
    }

    /// Clear has something to do: a finished file listed, or a download that failed or was cancelled.
    /// Running downloads stay; Clear never stops one.
    public static func canClear(entries: [DownloadList.Entry], live: [DownloadList.Live]) -> Bool {
        !entries.isEmpty || live.contains { !$0.running }
    }

    /// What Clear leaves of this session's live downloads: the running ones.
    public static func afterClear(live: [DownloadList.Live]) -> [DownloadList.Live] { live.filter(\.running) }

    /// A download began that wasn't running when last looked (`seen`): the card opens to show it
    /// arriving, as From's does.
    public static func started(seen: Set<UInt32>, live: [DownloadList.Live]) -> Bool {
        live.contains { $0.running && !seen.contains($0.id) }
    }

    /// The button's box at the header's right end, `edgeInset` from the sidebar's edge: 32 pt, or
    /// 28 pt where the header goes narrow.
    public static func button(width: Double) -> (x: Double, size: Double) {
        let size = SidebarHeaderLayout.isNarrow(width: width) ? 28.0 : 32.0
        return (width - SidebarHeaderLayout.edgeInset - size, size)
    }

    /// The card's fill: a lifted piece of the sidebar. The sidebar's top colour (`sidebar`, drawn at
    /// `alpha` over the window material) is made opaque over what a translucent sidebar shows (about
    /// 20 % white on dark themes, as SpacePalette's folder ground; 93 % on light ones), then lifted
    /// toward white so the card stands off what's under it: 45 % on a light sidebar, 7 % on a dark one,
    /// where more would wash the hue out.
    public static func surface(sidebar: RGB, alpha: Double, dark: Bool) -> RGB {
        let a = max(0, min(1, alpha))
        let under = dark ? RGB(0.2, 0.2, 0.2) : RGB(0.93, 0.93, 0.93)
        let opaque = under.mixed(with: sidebar, a)
        let lifted = opaque.mixed(with: .white, dark ? 0.07 : 0.45)
        return RGB(min(max(lifted.r, 0), 1), min(max(lifted.g, 0), 1), min(max(lifted.b, 0), 1))
    }
}
