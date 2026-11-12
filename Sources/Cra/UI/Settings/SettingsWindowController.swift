import AppKit
import SwiftUI

/// Callbacks the panes hand back to the app.
struct SettingsActions {
    var importData: () -> Void = {}
    var openURL: (String) -> Void = { _ in }
    /// A page in a space on that profile (nil is Default), e.g. its chrome://settings/languages.
    var openProfilePage: (String, UUID?) -> Void = { _, _ in }
    var exportDiagnostics: () -> Void = {}
    var newProfile: () -> Void = {}
}

/// The panes in Dia's Settings sidebar (Dia 1.54.2: Account, Tabs, Privacy, Profiles, Skills,
/// Apps, Shortcuts, Advanced). Cra has no account or AI skills/apps; General
/// (system integration) and Extensions take rows instead; Links is Arc's Links pane.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, tabs, links, privacy, profiles, extensions, shortcuts, performance, advanced
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .tabs: return "Tabs"
        case .links: return "Links"
        case .privacy: return "Privacy"
        case .profiles: return "Profiles"
        case .extensions: return "Extensions"
        case .shortcuts: return "Shortcuts"
        case .performance: return "Performance"
        case .advanced: return "Advanced"
        }
    }

    /// Dia's sidebar glyphs are SF Symbols (compared against the running Dia's icons).
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .tabs: return "square.on.square"
        case .links: return "link"
        case .privacy: return "hand.raised"
        case .profiles: return "person"
        case .extensions: return "puzzlepiece.extension"
        case .shortcuts: return "keyboard"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .advanced: return "gearshape.2"
        }
    }
}

/// The selected pane.
@MainActor
@Observable
final class SettingsNavigation {
    private(set) var pane: SettingsPane = .general
    /// The window is on screen: panes that refresh (Performance) stop while it is closed or covered.
    var isOpen = false
    /// Counts each time Settings is brought up: panes showing what changed elsewhere (a profile's
    /// languages, set on Chromium's page) read it again.
    private(set) var shown = 0
    func didShow() { shown += 1 }

    func show(_ p: SettingsPane) {
        guard p != pane else { return }
        pane = p
    }
}

/// Settings in a window of its own, the panes as tabs across its top (as the user's From
/// browser has them): the pane's name on the row of the window's buttons, the tabs under it,
/// the pane below. Colours stay Cra's: the selected tab is accent-filled while the window is key.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let nav = SettingsNavigation()

    func show(_ pane: SettingsPane) { nav.show(pane) }
    var debugPane: String { nav.pane.rawValue }
    func didShow() { nav.didShow() }

    init(store: SidebarStore, bindings: KeyBindingRegistry, sync: SettingsSyncService, actions: SettingsActions) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsMetrics.windowSize),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Settings"
        window.titleVisibility = .hidden
        // The content view draws the title and tabs under the transparent titlebar.
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true

        window.contentViewController = NSHostingController(rootView: SettingsContent(nav: nav, actions: actions)
            .environment(store).environment(bindings).environment(sync))
        window.setFrame(NSRect(origin: .zero, size: SettingsMetrics.windowSize), display: false)
        window.centerOnTestScreen()
        // On screen: shown and not entirely covered (the window needn't be key).
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [nav] note in
                MainActor.assumeIsolated {
                    guard let w = note.object as? NSWindow else { return }
                    let open = note.name != NSWindow.willCloseNotification && w.occlusionState.contains(.visible)
                    if nav.isOpen != open { nav.isOpen = open }
                }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// The window's top: the pane's name centred on the row of the window's buttons, the tabs under it.
struct SettingsTabBar: View {
    let nav: SettingsNavigation

    var body: some View {
        VStack(spacing: 6) {
            Text(nav.pane.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.8))
                .lineLimit(1)
                .padding(.horizontal, 90)
                .frame(height: SettingsMetrics.titleRowHeight)
            HStack(spacing: 2) {
                ForEach(SettingsPane.allCases) { SettingsTab(pane: $0, nav: nav) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

/// One pane's tab: its glyph over its name. Selected: accent fill and white while the window is
/// key, otherwise a grey fill with accent-coloured content (Cra's source-list colours).
struct SettingsTab: View {
    let pane: SettingsPane
    let nav: SettingsNavigation
    @Environment(\.controlActiveState) private var activeState
    @State private var hovering = false

    var body: some View {
        let selected = nav.pane == pane
        let key = activeState == .key
        let ink: Color = selected ? (key ? .white : .accentColor) : (hovering ? .primary : .primary.opacity(0.62))
        Button { nav.show(pane) } label: {
            VStack(spacing: 3) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 17))
                    .frame(height: 22)
                Text(pane.title)
                    .font(.system(size: 11, weight: selected ? .medium : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(ink)
            .frame(minWidth: 52)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? (key ? Color.accentColor : Color.primary.opacity(0.1))
                               : (hovering ? Color.primary.opacity(0.06) : Color.clear)))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        // With Keyboard navigation on, the window's first focus landed on a tab and drew a ring
        // around a pane that isn't the selected one; the selection fill is the indicator.
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help(pane.title)
    }
}

struct SettingsContent: View {
    let nav: SettingsNavigation
    let actions: SettingsActions

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(nav: nav)
            Divider()
            Group {
                switch nav.pane {
                case .general: GeneralPane()
                case .tabs: TabsPane()
                case .links: LinksPane()
                case .privacy: PrivacyPane(actions: actions)
                case .profiles: ProfilesPane(nav: nav, actions: actions)
                case .extensions: ExtensionsPane(actions: actions)
                case .shortcuts: ShortcutsPane()
                case .performance: PerformancePane(nav: nav, actions: actions)
                case .advanced: AdvancedPane(actions: actions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Scroll views can draw into the ignored titlebar safe area. Keep every
            // pane inside its viewport below the fixed navigation row.
            .clipped()
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}
