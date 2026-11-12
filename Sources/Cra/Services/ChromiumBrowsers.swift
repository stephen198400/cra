import AppKit
import UniformTypeIdentifiers

/// Chromium-family browsers on this Mac, by their "User Data" folder: where File ▸ Import
/// Bookmarks… reads Bookmarks files (BookmarkImport) and where NativeMessagingHosts finds the
/// manifests desktop apps install.
struct ChromiumBrowser {
    let id: String
    let name: String
    let bundleID: String
    let dataDir: URL

    private static func at(_ id: String, _ name: String, _ bundleID: String, _ path: String) -> ChromiumBrowser {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return ChromiumBrowser(id: id, name: name, bundleID: bundleID, dataDir: support.appendingPathComponent(path, isDirectory: true))
    }

    /// Chrome first: it is where every app installs its native messaging hosts.
    static let all: [ChromiumBrowser] = [
        at("chrome", "Chrome", "com.google.Chrome", "Google/Chrome"),
        at("brave", "Brave", "com.brave.Browser", "BraveSoftware/Brave-Browser"),
        at("edge", "Edge", "com.microsoft.edgemac", "Microsoft Edge"),
        at("opera", "Opera", "com.operasoftware.Opera", "com.operasoftware.Opera"),
        at("operagx", "Opera GX", "com.operasoftware.OperaGX", "com.operasoftware.OperaGX"),
        at("vivaldi", "Vivaldi", "com.vivaldi.Vivaldi", "Vivaldi"),
        at("chromium", "Chromium", "org.chromium.Chromium", "Chromium"),
        at("helium", "Helium", "net.imput.helium", "net.imput.helium"),
    ]

    /// Arc and Dia keep their Chromium profiles a level down; only their native messaging hosts
    /// are read.
    static let arc = at("arc", "Arc", "company.thebrowser.Browser", "Arc/User Data")
    static let dia = at("dia", "Dia", "company.thebrowser.dia", "Dia/User Data")

    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
}

/// From ▸ Import Bookmarks…: another browser's bookmarks onto the bookmarks bar (BookmarkImport).
/// A Chromium-family browser is read in place; Safari keeps its data behind Full Disk Access, so
/// it comes from a file Safari exports (File ▸ Export ▸ Bookmarks…, or the .zip of File ▸ Export
/// Browsing Data to File…).
@MainActor
enum BookmarkImportPanel {
    static func run() {
        let browsers = ChromiumBrowser.all.filter { $0.isInstalled && !BookmarkImport.chromiumProfiles(userData: $0.dataDir).isEmpty }
        let alert = NSAlert()
        alert.messageText = "Import Bookmarks"
        alert.informativeText = "The browser’s bookmarks bar goes onto the bookmarks bar and the rest into Other Bookmarks. Bookmarks already here aren’t added again."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        for b in browsers { popup.addItem(withTitle: b.name) }
        popup.addItem(withTitle: "Safari (exported file)…")
        alert.accessoryView = popup
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let index = popup.indexOfSelectedItem
        if browsers.indices.contains(index) {
            let b = browsers[index]
            finish(BookmarkImport.chromium(userData: b.dataDir, browser: b.name), from: b.name)
        } else {
            importSafari()
        }
    }

    private static func importSafari() {
        let panel = NSOpenPanel()
        panel.message = "Choose the Bookmarks.html Safari exported (File ▸ Export ▸ Bookmarks…), or the .zip or folder from File ▸ Export Browsing Data to File…"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.html, .zip, .folder]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let html = safariBookmarksHTML(at: url) else {
            show("No bookmarks file", "That isn’t a bookmarks file Safari exported, and holds no Bookmarks.html.")
            return
        }
        finish(BookmarkImport.safari(html: html), from: "Safari")
    }

    /// Bookmarks.html itself, or found in an exported folder or .zip (which may wrap it in one folder).
    private static func safariBookmarksHTML(at url: URL) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if !isDir.boolValue && url.pathExtension.lowercased() != "zip" { return try? String(contentsOf: url, encoding: .utf8) }
        var folder = url
        var temp: URL?
        defer { if let temp { try? fm.removeItem(at: temp) } }
        if !isDir.boolValue {
            let dest = fm.temporaryDirectory.appendingPathComponent("cra-safari-\(UUID().uuidString)", isDirectory: true)
            temp = dest
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", url.path, dest.path]
            guard (try? p.run()) != nil else { return nil }
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            folder = dest
        }
        let subs = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for dir in [folder] + subs where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true || dir == folder {
            if let html = try? String(contentsOf: dir.appendingPathComponent("Bookmarks.html"), encoding: .utf8) { return html }
        }
        return nil
    }

    private static func finish(_ bookmarks: BookmarkImport.Bookmarks, from source: String) {
        guard !bookmarks.isEmpty else {
            show("No bookmarks to import", "\(source) has no bookmarks From can bring over.")
            return
        }
        let added = BookmarkStore.shared.importBookmarks(bar: bookmarks.bar, other: bookmarks.other)
        show(added == 0 ? "Nothing new to import" : "Bookmarks imported",
             added == 0 ? "Every bookmark from \(source) is already here." : "\(source)’s bookmarks are on the bookmarks bar and in Other Bookmarks.")
    }

    private static func show(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
