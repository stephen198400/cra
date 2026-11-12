import Foundation

/// Another browser's bookmarks for the bookmarks bar (From ▸ Import Bookmarks…): a Chromium-family
/// browser's `Bookmarks` files, or the Bookmarks.html Safari exports. Its bar goes onto the
/// Bookmarks Bar and the rest into Other Bookmarks (BookmarkTree.merge, which adds nothing twice).
/// Only bookmarks come over: no tabs, history, passwords or extensions.
public enum BookmarkImport {
    public struct Bookmarks: Equatable, Sendable {
        public var bar: [BookmarkNode]
        public var other: [BookmarkNode]
        public var isEmpty: Bool { bar.isEmpty && other.isEmpty }

        public init(bar: [BookmarkNode] = [], other: [BookmarkNode] = []) {
            self.bar = bar
            self.other = other
        }
    }

    // MARK: Chromium

    /// Profile folders under a Chromium "User Data" root that hold a Bookmarks file, Default first,
    /// with the name the browser shows for each (Local State). Opera keeps its single profile in
    /// the root itself.
    public static func chromiumProfiles(userData: URL) -> [(name: String, dir: URL)] {
        let fm = FileManager.default
        let names = (try? Data(contentsOf: userData.appendingPathComponent("Local State"))).map(profileNames) ?? [:]
        let hasBookmarks = { (dir: URL) in fm.fileExists(atPath: dir.appendingPathComponent("Bookmarks").path) }
        let dirs = ((try? fm.contentsOfDirectory(atPath: userData.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted { $0 == "Default" ? true : ($1 == "Default" ? false : $0.localizedStandardCompare($1) == .orderedAscending) }
        var out = dirs.compactMap { d -> (name: String, dir: URL)? in
            let dir = userData.appendingPathComponent(d, isDirectory: true)
            return hasBookmarks(dir) ? (names[d] ?? d, dir) : nil
        }
        if out.isEmpty && hasBookmarks(userData) { out = [("Default", userData)] }
        return out
    }

    /// Local State's profile.info_cache: the name the browser shows for each profile folder.
    public static func profileNames(localState data: Data) -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (root["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else { return [:] }
        return cache.compactMapValues { ($0 as? [String: Any])?["name"] as? String }
    }

    /// Every profile of a browser: the first profile with bookmarks gives the bar and Other
    /// Bookmarks; each other profile's go into Other Bookmarks in a folder "<browser> · <profile>".
    public static func chromium(userData: URL, browser: String) -> Bookmarks {
        var out = Bookmarks()
        for p in chromiumProfiles(userData: userData) {
            guard let data = try? Data(contentsOf: p.dir.appendingPathComponent("Bookmarks")) else { continue }
            let bm = chromium(bookmarksFile: data)
            if bm.isEmpty { continue }
            if out.isEmpty {
                out = bm
            } else {
                out.other.append(.folder("\(browser) · \(p.name)", children: bm.bar + bm.other))
            }
        }
        return out
    }

    /// One profile's Bookmarks file (JSON): bookmark_bar onto the bar; other and synced (mobile)
    /// after it. Only web pages come over; empty folders are left out.
    public static func chromium(bookmarksFile data: Data) -> Bookmarks {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { return Bookmarks() }
        func convert(_ node: [String: Any]) -> BookmarkNode? {
            let name = node["name"] as? String ?? ""
            let added = (node["date_added"] as? String).flatMap(Int64.init).map(chromiumDate) ?? Date()
            if node["type"] as? String == "url", let u = node["url"] as? String, u.hasPrefix("http") {
                return BookmarkNode(title: name, url: u, dateAdded: added)
            }
            if node["type"] as? String == "folder" {
                let kids = (node["children"] as? [[String: Any]] ?? []).compactMap(convert)
                return kids.isEmpty ? nil : .folder(name, dateAdded: added, children: kids)
            }
            return nil
        }
        func children(_ key: String) -> [BookmarkNode] {
            ((roots[key] as? [String: Any])?["children"] as? [[String: Any]] ?? []).compactMap(convert)
        }
        return Bookmarks(bar: children("bookmark_bar"), other: children("other") + children("synced"))
    }

    /// Chromium's time: microseconds since 1601-01-01.
    static func chromiumDate(_ micros: Int64) -> Date {
        Date(timeIntervalSince1970: Double(micros) / 1_000_000 - 11_644_473_600)
    }

    // MARK: Safari

    /// A Netscape bookmark file (Safari's File ▸ Export ▸ Bookmarks…, or Bookmarks.html in its
    /// Export Browsing Data): `<DT><H3>` opens a folder whose items follow in a `<DL>`,
    /// `<DT><A HREF>` is a bookmark. Safari's Favorites folder is its bookmarks bar; the Reading
    /// List is left out.
    public static func safari(html: String) -> Bookmarks {
        let pattern = #"<DT><H3[^>]*>(.*?)</H3>|<DT><A [^>]*HREF="([^"]*)"[^>]*>(.*?)</A>|</DL>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return Bookmarks() }
        // Stack of open folders; the bottom one is the file's root.
        var stack: [(name: String, items: [BookmarkNode])] = [("", [])]
        func close() {
            let done = stack.removeLast()
            if !done.items.isEmpty { stack[stack.count - 1].items.append(.folder(done.name, children: done.items)) }
        }
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            if m.range(at: 1).location != NSNotFound {
                stack.append((unescape(ns.substring(with: m.range(at: 1))), []))
            } else if m.range(at: 2).location != NSNotFound {
                let url = unescape(ns.substring(with: m.range(at: 2)))
                guard url.hasPrefix("http") else { continue }
                stack[stack.count - 1].items.append(BookmarkNode(title: unescape(ns.substring(with: m.range(at: 3))), url: url))
            } else if stack.count > 1 {
                close()
            }
        }
        while stack.count > 1 { close() }
        var out = Bookmarks()
        for item in stack[0].items {
            let name = item.title.lowercased()
            if item.isFolder && ["favorites", "favourites", "favorites bar", "favourites bar"].contains(name) { out.bar += item.children ?? [] }
            else if item.isFolder && name == "reading list" { continue }
            else if item.isFolder { out.other.append(item) }
            else { out.bar.append(item) }
        }
        return out
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
