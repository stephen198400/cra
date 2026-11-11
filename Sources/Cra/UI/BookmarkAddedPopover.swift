import AppKit

/// Chrome's "Bookmark added" bubble under the address's star: the bookmark's name, a folder popup
/// (Bookmarks Bar, Other Bookmarks and their folders, indented), Remove and Done. The name and folder
/// are saved as they change, so closing the bubble any way keeps them; Remove takes the bookmark away.
@MainActor
final class BookmarkAddedPopover: NSViewController, NSTextFieldDelegate {
    private let bookmarkID: UUID
    private let name = NSTextField()
    private let folder = NSPopUpButton()
    private weak var popover: NSPopover?
    private var folderIDs: [UUID] = []

    static func make(bookmarkID: UUID) -> NSPopover {
        let vc = BookmarkAddedPopover(bookmarkID: bookmarkID)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = vc
        vc.popover = popover
        return popover
    }

    private init(bookmarkID: UUID) {
        self.bookmarkID = bookmarkID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let store = BookmarkStore.shared
        let node = store.node(bookmarkID)
        let title = NSTextField(labelWithString: "Bookmark added")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        name.stringValue = node?.title ?? ""
        name.placeholderString = "Name"
        name.delegate = self
        name.target = self
        name.action = #selector(done)

        let parent = store.tree.parent(of: bookmarkID)?.id ?? BookmarkTree.barID
        for (folderNode, depth) in store.tree.folders {
            let label = folderNode.id == BookmarkTree.barID ? "Bookmarks Bar"
                : folderNode.id == BookmarkTree.otherID ? "Other Bookmarks" : folderNode.displayTitle
            folder.addItem(withTitle: String(repeating: "    ", count: depth) + label)
            folderIDs.append(folderNode.id)
        }
        if let i = folderIDs.firstIndex(of: parent) { folder.selectItem(at: i) }
        folder.target = self
        folder.action = #selector(folderChanged)

        let remove = NSButton(title: "Remove", target: self, action: #selector(removeBookmark))
        remove.bezelStyle = .rounded
        let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"

        func row(_ text: String, _ control: NSView) -> NSStackView {
            let l = NSTextField(labelWithString: text)
            l.alignment = .right
            l.widthAnchor.constraint(equalToConstant: 48).isActive = true
            control.widthAnchor.constraint(equalToConstant: 220).isActive = true
            let r = NSStackView(views: [l, control])
            r.spacing = 8
            return r
        }
        let buttons = NSStackView(views: [NSView(), remove, doneButton])
        buttons.spacing = 8
        let stack = NSStackView(views: [title, row("Name", name), row("Folder", folder), buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        view = stack
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(name)
        name.currentEditor()?.selectAll(nil)
    }

    func controlTextDidChange(_ obj: Notification) { saveName() }

    private func saveName() {
        let t = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, BookmarkStore.shared.node(bookmarkID)?.title != t else { return }
        BookmarkStore.shared.rename(id: bookmarkID, to: t)
    }

    @objc private func folderChanged() {
        let i = folder.indexOfSelectedItem
        guard folderIDs.indices.contains(i), BookmarkStore.shared.tree.parent(of: bookmarkID)?.id != folderIDs[i] else { return }
        BookmarkStore.shared.move(id: bookmarkID, to: folderIDs[i])
    }

    @objc private func removeBookmark() {
        BookmarkStore.shared.remove(id: bookmarkID)
        popover?.close()
    }

    @objc private func done() {
        saveName()
        popover?.close()
    }

    /// Scenario hook: `name=<text>`, `folder=<n>` (the popup's nth row), `remove`, `done`; then what
    /// the bookmark is now.
    func debug(_ step: String) -> String {
        if step.hasPrefix("name=") {
            name.stringValue = String(step.dropFirst(5))
            saveName()
        } else if step.hasPrefix("folder="), let n = Int(step.dropFirst(7)), folderIDs.indices.contains(n) {
            folder.selectItem(at: n)
            folderChanged()
        } else if step == "remove" {
            removeBookmark()
        } else if step == "done" {
            done()
        }
        let store = BookmarkStore.shared
        guard let node = store.node(bookmarkID) else { return "removed folders=\(folder.itemTitles.count)" }
        let parent = store.tree.parent(of: bookmarkID)?.id
        let where_ = parent == BookmarkTree.barID ? "bar" : parent == BookmarkTree.otherID ? "other" : (parent.flatMap { store.node($0)?.displayTitle } ?? "?")
        return "title=\"\(node.title)\" folder=\(where_) folders=\(folder.itemTitles.joined(separator: "|"))"
    }
}
