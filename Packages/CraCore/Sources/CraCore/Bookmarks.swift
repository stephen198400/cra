import Foundation

/// One bookmark or folder, Chrome's way: a folder has `children` and no `url`, a bookmark a
/// `url` and no children. Saved in bookmarks.json, apart from the sidebar (Arc has no bookmarks;
/// its pinned tabs stand in for them).
public struct BookmarkNode: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// nil for a folder.
    public var url: String?
    public var dateAdded: Date
    /// A folder's contents, in order; nil for a bookmark.
    public var children: [BookmarkNode]?

    public var isFolder: Bool { url == nil }

    public init(id: UUID = UUID(), title: String, url: String?, dateAdded: Date = Date(), children: [BookmarkNode]? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.dateAdded = dateAdded
        self.children = url == nil ? (children ?? []) : nil
    }

    public static func folder(_ title: String, id: UUID = UUID(), dateAdded: Date = Date(), children: [BookmarkNode] = []) -> BookmarkNode {
        BookmarkNode(id: id, title: title, url: nil, dateAdded: dateAdded, children: children)
    }

    /// The bookmark's title, or its address without the scheme when it has none (Chrome's bar shows
    /// a nameless bookmark as its icon alone; menus need a word).
    public var displayTitle: String {
        guard title.isEmpty, let url else { return title }
        return URL(string: url)?.host ?? url
    }

    /// Every bookmark in this subtree, depth first.
    public var allBookmarks: [BookmarkNode] {
        isFolder ? (children ?? []).flatMap(\.allBookmarks) : [self]
    }

    private enum CodingKeys: String, CodingKey { case id, title, url, dateAdded, children }

    /// Tolerant: a node without an id or date gets one, a folder's unreadable child is dropped
    /// rather than the whole file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        // Neither an address nor contents: not a node this file can use.
        if url == nil, !c.contains(.children) {
            throw DecodingError.dataCorruptedError(forKey: .url, in: c, debugDescription: "a bookmark without a url or children")
        }
        dateAdded = (try? c.decodeIfPresent(Date.self, forKey: .dateAdded)) ?? Date(timeIntervalSince1970: 0)
        if url == nil {
            let raw = (try? c.decodeIfPresent([Lossy].self, forKey: .children)) ?? []
            children = raw.compactMap(\.node)
        } else {
            children = nil
        }
    }

    private struct Lossy: Decodable {
        let node: BookmarkNode?
        init(from decoder: Decoder) throws { node = try? BookmarkNode(from: decoder) }
    }
}

/// bookmarks.json: Chrome's two roots, the Bookmarks Bar and Other Bookmarks. Their ids are fixed,
/// so a caller names a root without looking it up.
public struct BookmarkTree: Codable, Equatable, Sendable {
    public static let barID = UUID(uuidString: "B0000000-0000-0000-0000-0000000000B1")!
    public static let otherID = UUID(uuidString: "B0000000-0000-0000-0000-0000000000B2")!

    public var bar: BookmarkNode
    public var other: BookmarkNode

    public init(bar: [BookmarkNode] = [], other: [BookmarkNode] = []) {
        self.bar = .folder("Bookmarks Bar", id: Self.barID, dateAdded: Date(timeIntervalSince1970: 0), children: bar)
        self.other = .folder("Other Bookmarks", id: Self.otherID, dateAdded: Date(timeIntervalSince1970: 0), children: other)
    }

    private enum CodingKeys: String, CodingKey { case bar, other }

    /// A file without a root, or with a root that is no folder, keeps the other root and starts that
    /// one empty. The roots keep their fixed ids and names whatever the file says.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func kids(_ key: CodingKeys) -> [BookmarkNode] {
            ((try? c.decodeIfPresent(BookmarkNode.self, forKey: key)) ?? nil)?.children ?? []
        }
        self.init(bar: kids(.bar), other: kids(.other))
    }

    public var isEmpty: Bool { (bar.children ?? []).isEmpty && (other.children ?? []).isEmpty }

    // MARK: Reading

    /// Two addresses are one bookmark when they differ only by a trailing slash.
    public static func sameURL(_ a: String, _ b: String) -> Bool {
        func trimmed(_ s: String) -> Substring { s.hasSuffix("/") ? s.dropLast() : Substring(s) }
        return trimmed(a) == trimmed(b)
    }

    public func node(_ id: UUID) -> BookmarkNode? {
        func find(_ n: BookmarkNode) -> BookmarkNode? {
            if n.id == id { return n }
            for c in n.children ?? [] { if let hit = find(c) { return hit } }
            return nil
        }
        return find(bar) ?? find(other)
    }

    /// The first bookmark for this address, the bar's before Other Bookmarks'.
    public func bookmark(for url: String) -> BookmarkNode? {
        (bar.allBookmarks + other.allBookmarks).first { Self.sameURL($0.url ?? "", url) }
    }

    public func isBookmarked(url: String) -> Bool { bookmark(for: url) != nil }

    /// The folder holding `id`, nil for a root or an id that isn't there.
    public func parent(of id: UUID) -> BookmarkNode? {
        func find(_ n: BookmarkNode) -> BookmarkNode? {
            guard let kids = n.children else { return nil }
            if kids.contains(where: { $0.id == id }) { return n }
            for c in kids { if let hit = find(c) { return hit } }
            return nil
        }
        return find(bar) ?? find(other)
    }

    /// Every folder with its depth, roots first: for a Move To menu.
    public var folders: [(node: BookmarkNode, depth: Int)] {
        func walk(_ n: BookmarkNode, _ d: Int) -> [(node: BookmarkNode, depth: Int)] {
            guard n.isFolder else { return [] }
            return [(n, d)] + (n.children ?? []).flatMap { walk($0, d + 1) }
        }
        return walk(bar, 0) + walk(other, 0)
    }

    // MARK: Editing

    /// Runs `edit` on the node `id` in place. False when there is no such node.
    @discardableResult
    private mutating func modify(_ id: UUID, _ edit: (inout BookmarkNode) -> Void) -> Bool {
        func walk(_ n: inout BookmarkNode) -> Bool {
            if n.id == id { edit(&n); return true }
            guard n.children != nil else { return false }
            for i in n.children!.indices where walk(&n.children![i]) { return true }
            return false
        }
        return walk(&bar) || walk(&other)
    }

    /// A bookmark at the end of `folder` (or at `index`). nil when `folder` is no folder.
    @discardableResult
    public mutating func add(title: String, url: String, folder: UUID = BookmarkTree.barID, index: Int? = nil,
                             dateAdded: Date = Date()) -> BookmarkNode? {
        insert(BookmarkNode(title: title, url: url, dateAdded: dateAdded), into: folder, at: index)
    }

    @discardableResult
    public mutating func addFolder(title: String, in folder: UUID = BookmarkTree.barID, index: Int? = nil,
                                   dateAdded: Date = Date()) -> BookmarkNode? {
        insert(.folder(title, dateAdded: dateAdded), into: folder, at: index)
    }

    @discardableResult
    private mutating func insert(_ node: BookmarkNode, into folder: UUID, at index: Int?) -> BookmarkNode? {
        guard self.node(folder)?.isFolder == true else { return nil }
        modify(folder) { f in
            let n = f.children!.count
            f.children!.insert(node, at: min(max(0, index ?? n), n))
        }
        return node
    }

    /// Takes a bookmark or folder (with what it holds) out. The roots stay.
    @discardableResult
    public mutating func remove(id: UUID) -> BookmarkNode? {
        guard id != Self.barID, id != Self.otherID, let p = parent(of: id) else { return nil }
        var removed: BookmarkNode?
        modify(p.id) { f in
            if let i = f.children!.firstIndex(where: { $0.id == id }) { removed = f.children!.remove(at: i) }
        }
        return removed
    }

    /// Every bookmark for this address goes (Chrome's star clears the page, not one of its copies).
    @discardableResult
    public mutating func removeAll(url: String) -> Int {
        var n = 0
        while let b = bookmark(for: url), remove(id: b.id) != nil { n += 1 }
        return n
    }

    @discardableResult
    public mutating func rename(id: UUID, to title: String) -> Bool {
        guard id != Self.barID, id != Self.otherID else { return false }
        return modify(id) { $0.title = title }
    }

    /// A bookmark's new address. Folders have none.
    @discardableResult
    public mutating func setURL(id: UUID, to url: String) -> Bool {
        guard node(id)?.isFolder == false else { return false }
        return modify(id) { $0.url = url }
    }

    /// Moves `id` into `folder` at `index` (its end without one). A root, or a folder into itself or
    /// one inside it, does not move. `index` counts the folder's items before the move, as a drop
    /// position does.
    @discardableResult
    public mutating func move(id: UUID, to folder: UUID, index: Int? = nil) -> Bool {
        guard canMove(id: id, to: folder), let moving = node(id), let from = parent(of: id) else { return false }
        var at = index
        if from.id == folder, let i = from.children?.firstIndex(where: { $0.id == id }), let idx = index, idx > i { at = idx - 1 }
        remove(id: id)
        return insert(moving, into: folder, at: at) != nil
    }

    /// Adds another browser's bookmarks to `folder`: a folder of the same name is filled rather than
    /// made twice, and an address the folder already has is skipped, so importing again adds nothing.
    /// Returns how many bookmarks were added.
    @discardableResult
    public mutating func merge(_ nodes: [BookmarkNode], into folder: UUID) -> Int {
        guard let target = node(folder), target.isFolder else { return 0 }
        var added = 0
        for n in nodes {
            let current = node(folder)?.children ?? []
            if n.isFolder {
                let existing = current.first { $0.isFolder && $0.title == n.title }
                let dest = existing?.id ?? insert(.folder(n.title, dateAdded: n.dateAdded), into: folder, at: nil)!.id
                added += merge(n.children ?? [], into: dest)
            } else if let url = n.url, !current.contains(where: { !$0.isFolder && Self.sameURL($0.url ?? "", url) }) {
                insert(BookmarkNode(title: n.title, url: url, dateAdded: n.dateAdded), into: folder, at: nil)
                added += 1
            }
        }
        return added
    }
}

extension BookmarkNode {
    /// Whether `id` is somewhere inside `folder`.
    static func contains(_ folder: BookmarkNode, _ id: UUID) -> Bool {
        (folder.children ?? []).contains { $0.id == id || contains($0, id) }
    }
}
