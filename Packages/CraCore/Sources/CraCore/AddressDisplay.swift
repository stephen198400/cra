import Foundation

/// What the toolbar's address shows while it isn't being edited (Dia): the site's host in the
/// bar's primary ink, then " / " and the page's title in its dim ink, the whole line truncating at
/// its tail, e.g. `sanjoseca.gov / Building Division City of San José`. A click (or ⌘L) swaps it for
/// the full URL in place.
public enum AddressDisplay {
    public struct Parts: Equatable, Sendable {
        /// Primary ink.
        public var host: String
        /// Dim ink, right after the host: " / Title", the path with Show Full URL, or nothing.
        public var detail: String
        public init(host: String, detail: String) {
            self.host = host
            self.detail = detail
        }
    }

    public static let separator = " / "

    /// `host`: the site as the bar names it (AppSettings.siteKey, else the readable URL).
    /// `path`: what follows the host when Show Full URL is on; it replaces the title.
    public static func parts(host: String, title: String, path: String = "") -> Parts {
        if !path.isEmpty { return Parts(host: host, detail: path) }
        let t = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // A page without a title of its own reports its address (or host) as one: say it once.
        guard !t.isEmpty, !names(t, host: host) else { return Parts(host: host, detail: "") }
        return Parts(host: host, detail: separator + t)
    }

    private static func names(_ title: String, host: String) -> Bool {
        var t = title.lowercased()
        for p in ["https://", "http://"] where t.hasPrefix(p) { t.removeFirst(p.count) }
        if t.hasPrefix("www.") { t.removeFirst(4) }
        if t.hasSuffix("/") { t.removeLast() }
        return t == host.lowercased()
    }
}
