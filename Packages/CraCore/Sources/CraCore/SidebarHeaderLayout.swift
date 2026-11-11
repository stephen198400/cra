import Foundation

/// The sidebar header row. Arc 1.17x kept the sidebar toggle and ← → ↻ there (issue #287 measured
/// its regular, compact and narrow layouts); this fork puts them in the toolbar, Dia style, so the
/// row holds the traffic lights and the downloads button at its far right, `edgeInset` from the
/// sidebar's edge, 32 pt or 28 pt under `narrowBelow` (DownloadsCard.button).
public enum SidebarHeaderLayout {
    public static let narrowBelow: Double = 212
    public static let edgeInset: Double = 6

    public static func isNarrow(width: Double) -> Bool { width < narrowBelow }

    /// What the row carries after the traffic lights, left to right.
    public enum Item: Equatable, Sendable { case downloads }

    /// Only downloads: the toggle and the navigation are the toolbar's (ToolbarComposition), on a
    /// Developer Mode page too.
    public static func items(developerPage: Bool = false) -> [Item] { [.downloads] }
}

/// Arc's popover under the narrow header's ••• (Arc 1.17x, 1x window capture, 9 Nov 2026); its tones
/// are the downloads card's (DownloadsCardPanel).
public enum SidebarMoreMenu {
    public static let width: Double = 200
    public static let rowHeight: Double = 40
    /// Padding around the rows; also the highlight's inset from the panel's sides.
    public static let inset: Double = 8
    public static let cornerRadius: Double = 12
    public static let highlightRadius: Double = 8
    public static let arrowHeight: Double = 6
    public static let arrowWidth: Double = 12
    /// The arrow's tip sits this far under the button's bottom edge.
    public static let arrowGap: Double = 10
    /// Icon centre, title start and the shortcut's trailing edge, from the panel's sides.
    public static let iconCentre: Double = 27.5
    public static let titleX: Double = 50.5
    public static let shortcutTrailing: Double = 21

    public static func height(rows: Int) -> Double { 2 * inset + Double(rows) * rowHeight }

    /// The panel's fill: black with 15 % of the theme's shadedDark, half the tooltip's 30 %
    /// (Arc's yellow "Lab" theme: shadedDark (111, 86, −20) → (17, 13, 0) measured).
    public static func fill(shadedDark ink: RGB) -> RGB {
        clamped(RGB.black.mixed(with: ink, 0.15))
    }

    /// The hovered row: the fill with 41 % of shadedDark over it, then 13 % white
    /// (measured (81, 70, 26) on the same theme).
    public static func highlight(shadedDark ink: RGB) -> RGB {
        clamped(RGB.black.mixed(with: ink, 0.15).mixed(with: ink, 0.41).mixed(with: .white, 0.13))
    }

    private static func clamped(_ c: RGB) -> RGB {
        RGB(min(max(c.r, 0), 1), min(max(c.g, 0), 1), min(max(c.b, 0), 1))
    }
}
