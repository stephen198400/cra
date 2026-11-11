import Foundation
import Observation

/// Chrome-style bookmarks (CraCore BookmarkTree), in bookmarks.json in the data folder. Apart from
/// the sidebar: pinned tabs stay Arc's bookmarks; these are the bar's and the importers'.
@MainActor
@Observable
final class BookmarkStore {
    static let shared = BookmarkStore()
    @ObservationIgnored private let file = JSONStore<BookmarkTree>("bookmarks.json")
    private(set) var tree: BookmarkTree

    private init() { tree = file.load(or: { BookmarkTree() }) }

    /// The Bookmarks Bar root's items, in order.
    var barItems: [BookmarkNode] { tree.bar.children ?? [] }
    var otherItems: [BookmarkNode] { tree.other.children ?? [] }

    func isBookmarked(url: String) -> Bool { tree.isBookmarked(url: url) }
    func bookmark(for url: String) -> BookmarkNode? { tree.bookmark(for: url) }
    func node(_ id: UUID) -> BookmarkNode? { tree.node(id) }

    @discardableResult
    func add(title: String, url: String, folder: UUID = BookmarkTree.barID, index: Int? = nil) -> BookmarkNode? {
        change { $0.add(title: title, url: url, folder: folder, index: index) }
    }

    @discardableResult
    func addFolder(title: String, in folder: UUID = BookmarkTree.barID) -> BookmarkNode? {
        change { $0.addFolder(title: title, in: folder) }
    }

    @discardableResult
    func remove(id: UUID) -> BookmarkNode? { change { $0.remove(id: id) } }

    @discardableResult
    func rename(id: UUID, to title: String) -> Bool { change { $0.rename(id: id, to: title) } }

    @discardableResult
    func setURL(id: UUID, to url: String) -> Bool { change { $0.setURL(id: id, to: url) } }

    @discardableResult
    func move(id: UUID, to folder: UUID, index: Int? = nil) -> Bool { change { $0.move(id: id, to: folder, index: index) } }

    /// Chrome's ⌘D / star: the page goes on the Bookmarks Bar, or every bookmark for it goes.
    /// Returns whether the page is bookmarked afterwards.
    @discardableResult
    func toggle(url: String, title: String) -> Bool {
        guard !url.isEmpty else { return false }
        if tree.isBookmarked(url: url) {
            _ = change { $0.removeAll(url: url) }
            return false
        }
        return change { $0.add(title: title, url: url) } != nil
    }

    /// Another browser's bookmarks: its bar onto the Bookmarks Bar, the rest into Other Bookmarks,
    /// without duplicating what an earlier import brought. Returns how many were added.
    @discardableResult
    func importBookmarks(bar: [BookmarkNode], other: [BookmarkNode]) -> Int {
        guard !bar.isEmpty || !other.isEmpty else { return 0 }
        return change { $0.merge(bar, into: BookmarkTree.barID) + $0.merge(other, into: BookmarkTree.otherID) }
    }

    /// Writes now (quit).
    func flush() { file.saveNow(tree) }

    private func change<R>(_ edit: (inout BookmarkTree) -> R) -> R {
        var t = tree
        let r = edit(&t)
        if t != tree {
            tree = t
            file.save(tree)
        }
        return r
    }
}
