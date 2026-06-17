//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents

/// Surfaces Spud's App Intents to Siri, Spotlight, and the Action button. Every
/// phrase must contain `\(.applicationName)`. Free-text parameters (search query)
/// are not interpolated into phrases; the intent requests them when run.
struct SpudAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenFeedAppIntent(),
            phrases: [
                "Open \(\.$feedType) in \(.applicationName)",
                "Open my \(.applicationName) feed",
            ],
            shortTitle: "Open Feed",
            systemImageName: "list.bullet.rectangle"
        )
        AppShortcut(
            intent: SearchLemmyAppIntent(),
            phrases: [
                "Search \(.applicationName)",
            ],
            shortTitle: "Search Lemmy",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: NewPostAppIntent(),
            phrases: [
                "New post in \(.applicationName)",
            ],
            shortTitle: "New Post",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: OpenInboxAppIntent(),
            phrases: [
                "Open my \(.applicationName) inbox",
            ],
            shortTitle: "Inbox",
            systemImageName: "tray"
        )
        AppShortcut(
            intent: OpenCommunityAppIntent(),
            phrases: [
                "Open \(\.$community) in \(.applicationName)",
            ],
            shortTitle: "Open Community",
            systemImageName: "person.3"
        )
        AppShortcut(
            intent: OpenSavedAppIntent(),
            phrases: [
                "Open my \(.applicationName) saved posts",
                "Show saved in \(.applicationName)",
            ],
            shortTitle: "Saved Posts",
            systemImageName: "bookmark.fill"
        )
    }
}
