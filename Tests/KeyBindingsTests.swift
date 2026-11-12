import AppKit

/// The command list KeyBindingRegistry keeps: the built-in actions and the user's shortcuts on them,
/// through every way the list is rebuilt.
@main
enum KeyBindingsTests {
    static var failures = 0
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures += 1; print("FAIL: \(message)") }
    }

    @MainActor
    static func main() {
        recordedShortcuts()
        let registry = KeyBindingRegistry.shared
        let builtIn = registry.actions.count
        // Chrome's ⌘D bookmarks the page; Pin/Unpin moved to ⇧⌘D, and Arc's Hide Toolbar is gone (the
        // address bar always lives in the toolbar).
        expect(registry.action("toggleBookmark")?.shortcuts == [Shortcut("d", [.command])], "⌘D is Bookmark This Page")
        expect(registry.action("pinTab")?.shortcuts == [Shortcut("d", [.command, .shift])], "⇧⌘D is Pin/Unpin Tab")
        expect(registry.action("toggleToolbar") == nil, "no Hide Toolbar command")
        let id = "newFolder"
        let chord = Shortcut("j", [.command, .option])
        registry.setShortcuts([chord], for: id)
        expect(registry.action(id)?.shortcuts == [chord], "a command takes a shortcut")

        // keybindings.json written by another Mac (settings sync): the shortcuts that file gives.
        let synced = Shortcut("k", [.command, .option])
        let file = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CRA_DATA_DIR"]!).appendingPathComponent("keybindings.json")
        try! JSONEncoder().encode([id: [synced]]).write(to: file)
        registry.reloadOverrides()
        expect(registry.actions.count == builtIn, "a synced keybindings.json keeps the list")
        expect(registry.action(id)?.shortcuts == [synced], "and its shortcuts come from the synced file")

        let builtInShortcuts = KeyBindingRegistry.defaults.first { $0.id == id }?.shortcuts
        registry.resetShortcuts(for: id)
        expect(registry.action(id)?.shortcuts == builtInShortcuts, "a reset command goes back to its own shortcut")
        registry.setShortcuts([chord], for: id)
        registry.resetOverrides()
        expect(registry.action(id)?.shortcuts == builtInShortcuts && registry.actions.count == builtIn, "Reset All restores the list")

        print("Key bindings: \(checks) checks, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    @MainActor
    static func recordedShortcuts() {
        let shifted: NSEvent.ModifierFlags = [.command, .shift]
        let digits: [(UInt16, String, String)] = [
            (18, "!", "1"), (19, "@", "2"), (20, "#", "3"), (21, "$", "4"), (23, "%", "5"),
            (22, "^", "6"), (26, "&", "7"), (28, "*", "8"), (25, "(", "9"), (29, ")", "0"),
            (19, "\"", "2"), (21, "¤", "4"),
        ]
        let cases = digits.map { ($0.0, $0.1, shifted, Optional($0.2)) } + [
            (19, "2", .command, "2"), (0, "A", shifted, "a"),
            (33, "{", shifted, "["), (24, "+", shifted, "="),
            (48, "\u{19}", .shift, Shortcut.tab), (0, "a", [], nil),
            (19, "@", .shift, nil),
        ]
        for (code, chars, flags, key) in cases {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                        timestamp: 0, windowNumber: 0, context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            let shortcut = Shortcut.from(event: event)
            expect(shortcut?.key == key, "record \(chars) with \(flags.rawValue) as \(key ?? "none")")
            guard let shortcut else { continue }
            expect(shortcut.flags == flags, "recording keeps the modifiers")
            expect(shortcut.matches(event), "the recorded shortcut matches its original press")
            let saved = try! JSONEncoder().encode(shortcut)
            expect(try! JSONDecoder().decode(Shortcut.self, from: saved) == shortcut, "the recorded shortcut survives saving")
            if let digit = digits.first(where: { $0.0 == code })?.2, flags.contains(.shift) {
                expect(shortcut.display == "⇧⌘\(digit)", "show the digit alongside Shift and Command")
            }
        }
    }
}
