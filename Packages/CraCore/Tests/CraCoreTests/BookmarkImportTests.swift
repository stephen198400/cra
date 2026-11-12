import CraCore
import Foundation
import Testing

/// From ▸ Import Bookmarks…: Chromium's Bookmarks files and Safari's exported Bookmarks.html.
struct BookmarkImportTests {
    private static let chromiumFile = Data(#"""
    {"roots": {
      "bookmark_bar": {"type": "folder", "name": "Bookmarks bar", "children": [
        {"type": "url", "name": "Docs", "url": "https://example.com/docs", "date_added": "13300000000000000"},
        {"type": "folder", "name": "Reading", "children": [
          {"type": "url", "name": "Read", "url": "https://example.com/read"},
          {"type": "url", "name": "Local", "url": "file:///Users/me/notes.html"}]},
        {"type": "folder", "name": "Empty", "children": []}]},
      "other": {"type": "folder", "children": [{"type": "url", "name": "Other", "url": "https://example.com/other"}]},
      "synced": {"type": "folder", "children": [{"type": "url", "name": "Phone", "url": "https://example.com/phone"}]}
    }}
    """#.utf8)

    @Test func chromiumBarAndTheRest() {
        let bm = BookmarkImport.chromium(bookmarksFile: Self.chromiumFile)
        #expect(bm.bar.map(\.title) == ["Docs", "Reading"], "empty folders are left out")
        #expect(bm.bar[1].children?.compactMap(\.url) == ["https://example.com/read"], "only web pages come over")
        #expect(bm.other.compactMap(\.url) == ["https://example.com/other", "https://example.com/phone"], "other, then mobile")
        #expect(abs(bm.bar[0].dateAdded.timeIntervalSince1970 - (13_300_000_000 - 11_644_473_600)) < 1, "Chromium's 1601 epoch")
        #expect(BookmarkImport.chromium(bookmarksFile: Data("{".utf8)).isEmpty, "a broken file gives nothing")
    }

    @Test func chromiumProfilesAfterTheFirstGoIntoOtherBookmarks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-bookmark-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for dir in ["Default", "Profile 2", "Profile 3"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        try Self.chromiumFile.write(to: root.appendingPathComponent("Default/Bookmarks"))
        try Self.chromiumFile.write(to: root.appendingPathComponent("Profile 2/Bookmarks"))
        try Data(#"{"profile": {"info_cache": {"Profile 2": {"name": "Work"}}}}"#.utf8).write(to: root.appendingPathComponent("Local State"))
        #expect(BookmarkImport.chromiumProfiles(userData: root).map(\.name) == ["Default", "Work"], "a profile without bookmarks is skipped")
        let bm = BookmarkImport.chromium(userData: root, browser: "Chrome")
        #expect(bm.bar.map(\.title) == ["Docs", "Reading"])
        #expect(bm.other.map(\.title) == ["Other", "Phone", "Chrome · Work"])
        #expect(bm.other.last?.children?.map(\.title) == ["Docs", "Reading", "Other", "Phone"])
    }

    @Test func safariFavoritesAreTheBar() {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
          <DT><H3 FOLDED>Favorites</H3>
          <DL><p>
            <DT><A HREF="https://example.com/a">A &amp; B</A>
          </DL><p>
          <DT><H3>Work</H3>
          <DL><p>
            <DT><A HREF="https://example.com/w">W</A>
            <DT><A HREF="javascript:alert(1)">Script</A>
          </DL><p>
          <DT><H3 id="com.apple.ReadingList">Reading List</H3>
          <DL><p><DT><A HREF="https://example.com/later">Later</A></DL><p>
          <DT><A HREF="https://example.com/loose">Loose</A>
        </DL><p>
        """
        let bm = BookmarkImport.safari(html: html)
        #expect(bm.bar.map(\.title) == ["A & B", "Loose"], "Favorites and loose bookmarks on the bar")
        #expect(bm.other.map(\.title) == ["Work"] && bm.other[0].children?.compactMap(\.url) == ["https://example.com/w"])
        #expect(!bm.bar.contains { $0.url == "https://example.com/later" } && !bm.other.contains { $0.title == "Reading List" })
    }

    @Test func importingTwiceAddsNothing() {
        let bm = BookmarkImport.chromium(bookmarksFile: Self.chromiumFile)
        var tree = BookmarkTree()
        #expect(tree.merge(bm.bar, into: BookmarkTree.barID) > 0)
        let before = tree
        _ = tree.merge(BookmarkImport.chromium(bookmarksFile: Self.chromiumFile).bar, into: BookmarkTree.barID)
        #expect(tree == before)
    }
}
