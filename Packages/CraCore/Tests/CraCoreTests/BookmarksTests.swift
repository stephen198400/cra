import CraCore
import Foundation
import Testing

/// Chrome-style bookmarks (bookmarks.json): the Bookmarks Bar and Other Bookmarks roots.
struct BookmarksTests {
    @Test func aNewTreeHasTwoEmptyRootsWithFixedIDs() {
        let t = BookmarkTree()
        #expect(t.isEmpty)
        #expect(t.bar.id == BookmarkTree.barID && t.bar.title == "Bookmarks Bar" && t.bar.isFolder)
        #expect(t.other.id == BookmarkTree.otherID && t.other.title == "Other Bookmarks" && t.other.isFolder)
    }

    @Test func addPutsABookmarkAtTheEndOfTheBarByDefault() throws {
        var t = BookmarkTree()
        let a = try req(t.add(title: "A", url: "https://a.example/"))
        let b = try req(t.add(title: "B", url: "https://b.example/"))
        let first = try req(t.add(title: "First", url: "https://first.example/", index: 0))
        #expect(t.bar.children?.map(\.id) == [first.id, a.id, b.id])
        #expect(!a.isFolder && a.children == nil)
    }

    @Test func addIntoAFolderAndIntoOther() throws {
        var t = BookmarkTree()
        let docs = try req(t.addFolder(title: "Docs"))
        let swift = try req(t.add(title: "Swift", url: "https://swift.org/", folder: docs.id))
        t.add(title: "News", url: "https://news.example/", folder: BookmarkTree.otherID)
        #expect(t.node(docs.id)?.children?.map(\.id) == [swift.id])
        #expect(t.parent(of: swift.id)?.id == docs.id)
        #expect(t.other.children?.map(\.title) == ["News"])
        let r1 = t.add(title: "x", url: "https://x/", folder: swift.id)
        #expect(r1 == nil, "a bookmark is no folder")
        let r2 = t.add(title: "x", url: "https://x/", folder: UUID())
        #expect(r2 == nil)
    }

    @Test func isBookmarkedFindsAnyDepthAndIgnoresATrailingSlash() throws {
        var t = BookmarkTree()
        let docs = try req(t.addFolder(title: "Docs"))
        let deep = try req(t.addFolder(title: "Deep", in: docs.id))
        let b = try req(t.add(title: "Swift", url: "https://swift.org/", folder: deep.id))
        #expect(t.isBookmarked(url: "https://swift.org/"))
        #expect(t.isBookmarked(url: "https://swift.org"))
        #expect(t.bookmark(for: "https://swift.org")?.id == b.id)
        #expect(!t.isBookmarked(url: "https://swift.org/blog"))
        #expect(!t.isBookmarked(url: ""), "a folder has no address to match")
    }

    @Test func theBarsBookmarkComesBeforeOthers() throws {
        var t = BookmarkTree()
        t.add(title: "Other copy", url: "https://a.example/", folder: BookmarkTree.otherID)
        let bar = try req(t.add(title: "Bar copy", url: "https://a.example/"))
        #expect(t.bookmark(for: "https://a.example/")?.id == bar.id)
    }

    @Test func removeTakesAFolderWithItsContentsButNeverARoot() throws {
        var t = BookmarkTree()
        let docs = try req(t.addFolder(title: "Docs"))
        t.add(title: "Swift", url: "https://swift.org/", folder: docs.id)
        let keep = try req(t.add(title: "Keep", url: "https://keep.example/"))
        let r3 = t.remove(id: docs.id)
        #expect(r3?.title == "Docs")
        #expect(!t.isBookmarked(url: "https://swift.org/"))
        #expect(t.bar.children?.map(\.id) == [keep.id])
        let r4 = t.remove(id: BookmarkTree.barID)
        let r5 = t.remove(id: BookmarkTree.otherID)
        #expect(r4 == nil && r5 == nil)
        let r6 = t.remove(id: UUID())
        #expect(r6 == nil)
    }

    @Test func removeAllClearsEveryCopyOfAnAddress() {
        var t = BookmarkTree()
        t.add(title: "1", url: "https://a.example/")
        t.add(title: "2", url: "https://a.example", folder: BookmarkTree.otherID)
        t.add(title: "Other", url: "https://b.example/")
        let r7 = t.removeAll(url: "https://a.example/")
        #expect(r7 == 2)
        #expect(!t.isBookmarked(url: "https://a.example/") && t.isBookmarked(url: "https://b.example/"))
    }

    @Test func renameAndSetURL() throws {
        var t = BookmarkTree()
        let b = try req(t.add(title: "Old", url: "https://old.example/"))
        let f = try req(t.addFolder(title: "F"))
        let r8 = t.rename(id: b.id, to: "New")
        #expect(r8 && t.node(b.id)?.title == "New")
        let r9 = t.setURL(id: b.id, to: "https://new.example/")
        #expect(r9 && t.isBookmarked(url: "https://new.example/"))
        let r10 = t.setURL(id: f.id, to: "https://x/")
        #expect(!r10, "a folder keeps having no address")
        let r11 = t.rename(id: BookmarkTree.barID, to: "Mine")
        #expect(!r11, "the roots keep Chrome's names")
    }

    @Test func moveBetweenFoldersAndWithinOne() throws {
        var t = BookmarkTree()
        let a = try req(t.add(title: "A", url: "https://a/"))
        let b = try req(t.add(title: "B", url: "https://b/"))
        let c = try req(t.add(title: "C", url: "https://c/"))
        // Drop A after C: index 3 counts the bar before the move.
        let r12 = t.move(id: a.id, to: BookmarkTree.barID, index: 3)
        #expect(r12)
        #expect(t.bar.children?.map(\.id) == [b.id, c.id, a.id])
        let r13 = t.move(id: c.id, to: BookmarkTree.barID, index: 0)
        #expect(r13)
        #expect(t.bar.children?.map(\.id) == [c.id, b.id, a.id])
        let r14 = t.move(id: b.id, to: BookmarkTree.otherID)
        #expect(r14)
        #expect(t.other.children?.map(\.id) == [b.id] && t.bar.children?.map(\.id) == [c.id, a.id])
    }

    @Test func aFolderDoesNotMoveIntoItself() throws {
        var t = BookmarkTree()
        let outer = try req(t.addFolder(title: "Outer"))
        let inner = try req(t.addFolder(title: "Inner", in: outer.id))
        let b = try req(t.add(title: "B", url: "https://b/"))
        let r15 = t.move(id: outer.id, to: outer.id)
        #expect(!r15)
        let r16 = t.move(id: outer.id, to: inner.id)
        #expect(!r16)
        let r17 = t.move(id: BookmarkTree.barID, to: BookmarkTree.otherID)
        #expect(!r17)
        let r18 = t.move(id: outer.id, to: b.id)
        #expect(!r18, "a bookmark is no folder")
        let r19 = t.move(id: inner.id, to: BookmarkTree.otherID)
        #expect(r19)
        #expect(t.node(outer.id)?.children?.isEmpty == true && t.other.children?.map(\.id) == [inner.id])
    }

    @Test func mergingTwiceAddsNothingTheSecondTime() {
        var t = BookmarkTree()
        let imported: [BookmarkNode] = [
            BookmarkNode(title: "A", url: "https://a/"),
            .folder("Docs", children: [BookmarkNode(title: "Swift", url: "https://swift.org/")]),
        ]
        let r20 = t.merge(imported, into: BookmarkTree.barID)
        #expect(r20 == 2)
        let r21 = t.merge(imported, into: BookmarkTree.barID)
        #expect(r21 == 0)
        #expect(t.bar.children?.map(\.title) == ["A", "Docs"])
        #expect(t.bar.children?[1].children?.map(\.title) == ["Swift"])
        let r22 = t.merge(imported, into: UUID())
        #expect(r22 == 0)
    }

    /// bookmarks.json as written: what loads is what was saved.
    @Test func bookmarksFileLoadsAsRecorded() throws {
        let (loaded, recorded) = try ModelFixtureTests.load("bookmarks.json", as: BookmarkTree.self)
        #expect(loaded == recorded)
        #expect(try ModelFixtureTests.roundTrips(loaded))
        #expect(loaded.bar.children?.count == 2 && loaded.other.children?.count == 1)
        #expect(loaded.isBookmarked(url: "https://developer.apple.com/documentation/appkit"))
        #expect(loaded.node(UUID(uuidString: "C0000000-0000-0000-0000-000000000005")!)?.displayTitle == "developer.apple.com")
    }

    /// A file with a missing root, a renamed root, an unreadable entry and an entry without an id
    /// loads what it can instead of being set aside as corrupt.
    @Test func aDamagedFileKeepsWhatItCanRead() throws {
        var (loaded, recorded) = try ModelFixtureTests.load("bookmarks-partial.json", as: BookmarkTree.self)
        let noID = try #require(loaded.bar.children?.firstIndex { $0.title == "No id" })
        loaded.bar.children?[noID].id = ModelFixtureTests.zero
        #expect(loaded == recorded)
        #expect(loaded.bar.id == BookmarkTree.barID && loaded.bar.title == "Bookmarks Bar")
        #expect(loaded.other.children == [])
    }

    @Test func showBookmarksBarIsOnByDefaultAndPersists() throws {
        #expect(AppSettings().showBookmarksBar)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.showBookmarksBar, "settings from before the bar get it on")
        var off = AppSettings()
        off.showBookmarksBar = false
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(off))
        #expect(!back.showBookmarksBar)
    }
}

/// #require can't take a mutating call (its macro captures the tree as a constant).
private func req<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T {
    try #require(value, sourceLocation: sourceLocation)
}
