import SwiftUI

/// Settings ▸ Tabs. Dia draws this pane as a two-column form of checkboxes, whose titles didn't
/// say what each one did. Cra gives every setting a line saying what it changes.
/// Links have a pane of their own, as in Arc.
struct TabsPane: View {
    @Environment(SidebarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        SettingsCardPane {
            // The address bar is always in the toolbar here (Dia): #305's sidebar/toolbar choice is gone.
            SettingsHeader("Bookmarks")
            SettingsFeatureCard {
                // Chrome's bookmarks bar, not in Arc (bookmarks.json; Arc's bookmarks are pinned tabs).
                SettingsToggleRow("Show bookmarks bar",
                                  detail: "A row of your bookmarks under the toolbar. \(KeyBindingRegistry.shared.action("toggleBookmarksBar")?.primary?.display ?? "⇧⌘B") switches it, \(KeyBindingRegistry.shared.action("toggleBookmark")?.primary?.display ?? "⌘D") or the star in the address bookmarks the page.",
                                  isOn: $store.settings.showBookmarksBar)
            }
            .padding(.top, 12)

            SettingsHeader("Sidebar").padding(.top, 20)
            SettingsFeatureCard {
                SettingsToggleRow("New tabs at the top",
                                  detail: "A new tab goes above your other tabs instead of below them.",
                                  isOn: $store.settings.newTabsAtTop)
                SettingsCardDivider()
                SettingsToggleRow("New Tab button above tabs",
                                  detail: "The + New Tab row sits at the top of the tab list, where you can always reach it.",
                                  isOn: $store.settings.newTabButtonAtTop)
                SettingsCardDivider()
                SettingsToggleRow("Folder previews",
                                  detail: "Hover over a closed folder to see the tabs inside it.",
                                  isOn: $store.settings.folderPreviews)
                SettingsCardDivider()
                SettingsToggleRow("Colorful favorite outline",
                                  detail: "The open favorite gets a rim in its logo’s colors instead of a plain one.",
                                  isOn: $store.settings.favoriteLogoOutline)
                SettingsCardDivider()
                // Arc's single-space mode ("Hide Space Header" on the space's menu), for people who
                // don't use spaces.
                SettingsToggleRow("Space header with one space",
                                  detail: "Show the space’s name at the top and its icon at the bottom of the sidebar, even while you have only one space.",
                                  isOn: $store.settings.showSpaceHeaderOnSingleSpace)
            }

            SettingsHeader("Pages").padding(.top, 20)
            SettingsFeatureCard {
                SettingsToggleRow("Edge to edge",
                                  detail: "Pages fill the window, with no margin or rounded corners around them.",
                                  isOn: $store.settings.edgeToEdgeContent)
                SettingsCardDivider()
                SettingsToggleRow("Automatic Picture in Picture",
                                  detail: "Switch away from a tab playing a video and the video keeps playing in a small floating window. A site you set in its site controls keeps its own choice.",
                                  isOn: $store.settings.autoPictureInPicture)
            }

            SettingsHeader("Tabs and Favorites").padding(.top, 20)
            SettingsFeatureCard {
                SettingsToggleRow("Haptic feedback when reordering",
                                  detail: "The trackpad taps as a dragged tab moves past another one.",
                                  isOn: $store.settings.hapticFeedbackOnReorder)
                SettingsCardDivider()
                // #154: Arc's favorites, one set per profile.
                SettingsToggleRow("Share Favorites across Spaces",
                                  detail: "Spaces on the same profile show the same Favorites, as in Arc. Turning it on combines their Favorites; turning it off gives each Space its own copy.",
                                  isOn: Binding(get: { store.settings.sharedFavorites }, set: { store.setFavoritesShared($0) }))
            }

            SettingsHeader("Tab cleanup").padding(.top, 20)
            SettingsFeatureCard {
                SettingsToggleRow("Archive unused tabs",
                                  detail: "Today tabs you haven’t opened for a while move to the archive. Pinned tabs and Favorites stay.",
                                  isOn: $store.settings.autoArchiveEnabled) {
                    SettingsInlinePicker(label: "After", selection: $store.settings.autoArchive, enabled: store.settings.autoArchiveEnabled) {
                        ForEach(AutoArchiveThreshold.allCases) { Text($0.label).tag($0) }
                    }
                }
                SettingsCardDivider()
                // Tab sleeping (GitHub #153): Arc's 4 hours and nothing more unless you ask.
                SettingsToggleRow("Free memory from unused tabs",
                                  detail: "A tab you haven’t used for a while is forced out of memory and reloads when you open it.",
                                  isOn: $store.settings.tabSleepTimerEnabled) {
                    SettingsInlinePicker(label: "After", selection: $store.settings.tabSleepAfter, enabled: store.settings.tabSleepTimerEnabled) {
                        ForEach(TabSleepThreshold.allCases) { Text($0.label).tag($0) }
                    }
                }
                SettingsCardDivider()
                SettingsToggleRow("Free memory when the Mac runs short",
                                  detail: "While macOS is short of memory, the tabs hidden longest are forced out of it, a few at a time.",
                                  isOn: $store.settings.tabSleepOnMemoryPressure)
            }
            SettingsFootnote(tabSleepNote)
        }
    }

    /// Says which tabs stay in memory, before the user finds out.
    private var tabSleepNote: String {
        let s = store.settings
        let note = "Tabs playing sound, recording or holding text you typed stay in memory."
        guard s.tabSleepTimerEnabled, TabSleepPolicy.timer(s.tabSleepAfter).keepsRecentTabs else { return note }
        return note + (s.tabSleepOnMemoryPressure ? " So do the 10 tabs you used last, unless the Mac is short of memory." : " So do the 10 tabs you used last.")
    }
}
