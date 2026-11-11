import CraCore
import Foundation
import Testing

@Suite struct BookmarkDragTests {
    /// A bookmark at 0–100, a folder at 110–210, a bookmark at 220–320.
    let spans = [
        BookmarkDrag.Span(start: 0, end: 100, isFolder: false),
        BookmarkDrag.Span(start: 110, end: 210, isFolder: true),
        BookmarkDrag.Span(start: 220, end: 320, isFolder: false),
    ]

    @Test func aBookmarksHalvesDropBeforeAndAfterIt() {
        #expect(BookmarkDrag.slot(at: 10, in: spans) == .insert(0))
        #expect(BookmarkDrag.slot(at: 60, in: spans) == .insert(1))
        #expect(BookmarkDrag.slot(at: 300, in: spans) == .insert(3))
    }

    @Test func aFoldersMiddleDropsIntoItAndItsEndsBesideIt() {
        #expect(BookmarkDrag.slot(at: 115, in: spans) == .insert(1))
        #expect(BookmarkDrag.slot(at: 160, in: spans) == .into(1))
        #expect(BookmarkDrag.slot(at: 205, in: spans) == .insert(2))
    }

    @Test func gapsAndEndsDropAtTheBoundary() {
        #expect(BookmarkDrag.slot(at: -5, in: spans) == .insert(0))
        #expect(BookmarkDrag.slot(at: 105, in: spans) == .insert(1))
        #expect(BookmarkDrag.slot(at: 500, in: spans) == .insert(3))
        #expect(BookmarkDrag.slot(at: 12, in: []) == .insert(0))
    }

    /// Bar: A, Folder(Inner(X)), B.
    private func tree() throws -> (BookmarkTree, a: BookmarkNode, folder: BookmarkNode, inner: BookmarkNode, b: BookmarkNode) {
        var t = BookmarkTree()
        let a = try need(t.add(title: "A", url: "https://a.example/"))
        let folder = try need(t.addFolder(title: "Folder"))
        let inner = try need(t.addFolder(title: "Inner", in: folder.id))
        _ = try need(t.add(title: "X", url: "https://x.example/", folder: inner.id))
        let b = try need(t.add(title: "B", url: "https://b.example/"))
        return (t, a, try #require(t.node(folder.id)), try #require(t.node(inner.id)), b)
    }

    @Test func dropBookmarkIntoAFolderOnTheBar() throws {
        var (t, a, folder, _, _) = try tree()
        let kids = t.bar.children ?? []
        let d = try #require(BookmarkDrag.destination(of: a.id, at: .into(1), parent: BookmarkTree.barID, children: kids, in: t))
        #expect(d.folder == folder.id && d.index == nil)
        let moved1 = t.move(id: a.id, to: d.folder, index: d.index)
        #expect(moved1)
        #expect(t.node(folder.id)?.children?.last?.id == a.id)
        #expect(t.bar.children?.map(\.title) == ["Folder", "B"])
    }

    @Test func reorderAlongTheBarCountsTheItemsBeforeTheMove() throws {
        var (t, a, _, _, _) = try tree()
        let kids = t.bar.children ?? []
        // A dropped after B: slot 3 among A, Folder, B.
        let d = try #require(BookmarkDrag.destination(of: a.id, at: .insert(3), parent: BookmarkTree.barID, children: kids, in: t))
        let moved2 = t.move(id: a.id, to: d.folder, index: d.index)
        #expect(moved2)
        #expect(t.bar.children?.map(\.title) == ["Folder", "B", "A"])
        // Dropped just after itself: no change.
        let kids2 = t.bar.children ?? []
        let same = try #require(BookmarkDrag.destination(of: a.id, at: .insert(3), parent: BookmarkTree.barID, children: kids2, in: t))
        let before = t
        t.move(id: a.id, to: same.folder, index: same.index)
        #expect(t == before)
    }

    @Test func aFolderNeverDropsIntoItselfOrItsDescendants() throws {
        let (t, _, folder, inner, b) = try tree()
        let kids = t.bar.children ?? []
        // Onto its own middle.
        #expect(BookmarkDrag.destination(of: folder.id, at: .into(1), parent: BookmarkTree.barID, children: kids, in: t) == nil)
        // Into its subfolder, from that subfolder's dropdown.
        let innerKids = t.node(folder.id)?.children ?? []
        #expect(BookmarkDrag.destination(of: folder.id, at: .into(0), parent: folder.id, children: innerKids, in: t) == nil)
        #expect(BookmarkDrag.destination(of: folder.id, at: .insert(0), parent: inner.id, children: [], in: t) == nil)
        #expect(!t.canMove(id: folder.id, to: inner.id))
        // Onto a bookmark's middle is no folder.
        #expect(BookmarkDrag.destination(of: folder.id, at: .into(2), parent: BookmarkTree.barID, children: kids, in: t) == nil)
        // A root never moves.
        #expect(!t.canMove(id: BookmarkTree.barID, to: folder.id))
        // Legal: the subfolder out to the bar, a bookmark into the subfolder.
        #expect(t.canMove(id: inner.id, to: BookmarkTree.barID))
        #expect(t.canMove(id: b.id, to: inner.id))
    }

    @Test func aSubfolderMovesOutToTheBarAndReordersInsideItsFolder() throws {
        var (t, a, folder, inner, _) = try tree()
        let moved3 = t.move(id: a.id, to: folder.id, index: 0)
        #expect(moved3)
        #expect(t.node(folder.id)?.children?.map(\.title) == ["A", "Inner"])
        // Inner dropped above A inside the dropdown.
        let kids = t.node(folder.id)?.children ?? []
        let d = try #require(BookmarkDrag.destination(of: inner.id, at: .insert(0), parent: folder.id, children: kids, in: t))
        let moved4 = t.move(id: inner.id, to: d.folder, index: d.index)
        #expect(moved4)
        #expect(t.node(folder.id)?.children?.map(\.title) == ["Inner", "A"])
        // And out onto the bar, first.
        let moved5 = t.move(id: inner.id, to: BookmarkTree.barID, index: 0)
        #expect(moved5)
        #expect(t.bar.children?.map(\.title) == ["Inner", "Folder", "B"])
    }

    private func need<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T {
        try #require(value, sourceLocation: sourceLocation)
    }
}
