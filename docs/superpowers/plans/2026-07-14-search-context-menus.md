# Search Result Context Menus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a long-press context menu to every Search result type (post, community, comment, user, instance), with the post menu reaching full parity with the feed's menu via a builder extracted from `PostListViewController` and shared.

**Architecture:** One small context-menu *builder* per entity type (`Spud/Utils/ContextMenus/`), each producing a `UIMenu` from an entity row + a per-entity *host* delegate protocol. The post builder is extracted from `PostListViewController`'s inline menu so the feed and Search produce the identical menu. Search attaches all five via `contextMenuConfigurationForRowAt`, dispatched by result type.

**Tech Stack:** Swift 6 (strict concurrency, `@MainActor`), UIKit (`UIContextMenuConfiguration`/`UIMenu`/`UIAction`), Swift Testing, GRDB-backed services (unchanged).

## Global Constraints

- **No emojis** in code, comments, docs, or commit messages.
- **Commit trailers** on every commit, verbatim:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY
  ```
- **Conventional commits** (`feat:`/`refactor:`/`test:`/`docs:`); small, focused commits.
- **Stage explicit paths** — never `git add -A`; never stage `Spud.xcodeproj` (gitignored, generated) or the cosmetically-modified `SpudSnapshotTests/__Snapshots__/**` git-annex PNGs.
- **New files require `make project`** (XcodeGen regenerates the gitignored `Spud.xcodeproj`) before they build.
- **Swift Testing** unit tests: `import Testing` (+ `import UIKit`/`import Foundation` as needed), `struct`/`@MainActor struct` suites, `@Test func`, `#expect`/`#require`. Tests must verify real behavior (assert the produced `UIMenu` tree), not mocks.
- **Swift 6 strict concurrency:** host protocols are `@MainActor protocol …: UIViewController`. Builders are `@MainActor enum`s with static functions. No data races.
- **The feed menu must stay byte-for-byte identical** after extraction — Task 1 is a refactor, not a redesign.
- **Enrichment is mapping-only** — no new network calls; the search response's `CommentView`/`CommunityView`/`PersonView` already carry the added fields. Existing search-cell snapshots (`SpudSnapshotTests/SearchResultCellsSnapshotTests.swift`) must stay byte-identical (added fields are menu-only, not rendered).
- **Sign-in gate:** every mutating action reuses the existing `presentSignInGate(title:)` (a shared `UIViewController` extension) when `accountScope.isSignedOut`.
- **Verify** `git branch --show-current` is `feat/search-context-menus` before each commit.
- Build/test from the worktree root `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/search-context-menus` with `make build` / `make test` / `make test-only ONLY=<target>`. SourceKit "No such module" editor squiggles are known-unreliable — trust the build.

---

## File Structure

- Create `Spud/Utils/ContextMenus/PostContextMenuBuilder.swift` — `PostContextMenuHost` protocol + `PostContextMenuBuilder` (Task 1).
- Create `Spud/Utils/ContextMenus/CommunityContextMenuBuilder.swift` — `CommunityContextMenuHost` + builder (Task 3).
- Create `Spud/Utils/ContextMenus/CommentContextMenuBuilder.swift` — `CommentContextMenuHost` + builder (Task 4).
- Create `Spud/Utils/ContextMenus/UserContextMenuBuilder.swift` — `UserContextMenuHost` + builder (Task 5).
- Create `Spud/Utils/ContextMenus/InstanceContextMenuBuilder.swift` — `InstanceContextMenuHost` + builder (Task 6).
- Modify `Spud/Scenes/PostList/PostListViewController.swift` — adopt the extracted builder (Task 1).
- Modify `Spud/Scenes/Search/SearchViewController.swift` — conform to the hosts + attach menus (Tasks 2-6).
- Modify `Spud/Scenes/Search/SearchResults.swift` — enrich `SearchCommunityResult`/`SearchCommentResult`/`SearchUserResult` (Tasks 3-5).
- Create `SpudTests/PostContextMenuBuilderTests.swift`, `SpudTests/CommunityContextMenuBuilderTests.swift`, `SpudTests/CommentContextMenuBuilderTests.swift`, `SpudTests/UserContextMenuBuilderTests.swift`, `SpudTests/InstanceContextMenuBuilderTests.swift`.
- Modify `SpudUITests/SpudUITests.swift` — Search nav UITests (Tasks 2, 3, 5).
- Modify `docs/features/search.md`, `docs/features/README.md` (Task 6).

---

## Task 1: Extract `PostContextMenuBuilder` + feed adoption

**Files:**
- Create: `Spud/Utils/ContextMenus/PostContextMenuBuilder.swift`
- Modify: `Spud/Scenes/PostList/PostListViewController.swift:2177-2321` (replace inline menu assembly with a builder call)
- Test: `SpudTests/PostContextMenuBuilderTests.swift`

**Interfaces:**
- Consumes: `PostVoteDispatching`/`PostSaveDispatching` (`Spud/Utils/PostActions.swift:40,84` — `vote(serverPostId:action:)`, `toggleSaved(serverPostId:)`, `currentSavedState(serverPostId:) -> Bool`, `postActionsAccountScope`), `PostReminderDispatching` (`PostListViewController.swift:1920` — `remindMeMenuTarget(serverPostId:) -> RemindMeMenuTarget?`, `makeRemindMeMenu(for:) -> UIMenu`), `PostListRow` (`SpudDataKit`), `GeneralAppearance` (`appearanceService.general`, provides `upvoteIcon`/`downvoteIcon`), `MuteDuration`.
- Produces (used by Task 2):
  - `@MainActor protocol PostContextMenuHost: PostSaveDispatching, PostReminderDispatching` with members below.
  - `enum PostContextMenuBuilder { static func menu(forServerPostId: Int64, host: PostContextMenuHost, upvoteIcon: UIImage?, downvoteIcon: UIImage?) -> UIMenu }`

- [ ] **Step 1: Write the failing builder test**

Create `SpudTests/PostContextMenuBuilderTests.swift`. It drives the builder with a fake host and asserts the produced `UIMenu` tree. Helper `titles(of:)` recursively flattens a menu's action/submenu titles.

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import Testing
@testable import Spud

@MainActor
struct PostContextMenuBuilderTests {
    /// Flattens a menu into the ordered titles of its actions and nested menus.
    private func allTitles(_ menu: UIMenu) -> [String] {
        menu.children.flatMap { element -> [String] in
            switch element {
            case let action as UIAction: [action.title]
            case let submenu as UIMenu: [submenu.title] + allTitles(submenu)
            default: []
            }
        }
    }

    private func hasDestructive(_ menu: UIMenu, title: String) -> Bool {
        menu.children.contains { element in
            if let submenu = element as? UIMenu {
                return submenu.children.contains {
                    ($0 as? UIAction).map { $0.title == title && $0.attributes.contains(.destructive) } ?? false
                }
            }
            return false
        }
    }

    @Test func includesCoreActionsAndDestructiveSafety() {
        let host = FakePostContextMenuHost(row: .fixture(communityName: "news", creatorName: "alice", isSaved: false))
        let menu = PostContextMenuBuilder.menu(forServerPostId: 42, host: host, upvoteIcon: nil, downvoteIcon: nil)
        let titles = allTitles(menu)
        #expect(titles.contains("Upvote"))
        #expect(titles.contains("Downvote"))
        #expect(titles.contains("Save"))
        #expect(titles.contains("Reply"))
        #expect(titles.contains("Share"))
        #expect(titles.contains("Cross-post"))
        #expect(titles.contains("Visit c/news"))
        #expect(titles.contains("View u/alice"))
        #expect(titles.contains("Hide"))
        #expect(hasDestructive(menu, title: "Block u/alice"))
        #expect(hasDestructive(menu, title: "Report"))
    }

    @Test func saveTitleReflectsSavedState() {
        let host = FakePostContextMenuHost(row: .fixture(isSaved: true))
        let menu = PostContextMenuBuilder.menu(forServerPostId: 1, host: host, upvoteIcon: nil, downvoteIcon: nil)
        #expect(allTitles(menu).contains("Unsave"))
    }

    @Test func omitsFeedOnlySubmenusWhenHostReturnsNil() {
        // A host that provides no cross-post siblings and no moderation (the
        // Search case) yields a menu without those submenus.
        let host = FakePostContextMenuHost(row: .fixture())
        let menu = PostContextMenuBuilder.menu(forServerPostId: 1, host: host, upvoteIcon: nil, downvoteIcon: nil)
        let titles = allTitles(menu)
        #expect(!titles.contains("Also posted in"))
    }

    @Test func upvoteInvokesHostVote() async {
        let host = FakePostContextMenuHost(row: .fixture())
        let menu = PostContextMenuBuilder.menu(forServerPostId: 7, host: host, upvoteIcon: nil, downvoteIcon: nil)
        // Locate and perform the Upvote action's handler.
        performAction(titled: "Upvote", in: menu)
        // The fake records the vote call synchronously via the Task; yield once.
        await Task.yield()
        #expect(host.votedPostIds.contains(7))
    }

    private func performAction(titled title: String, in menu: UIMenu) {
        for element in menu.children {
            if let action = element as? UIAction, action.title == title {
                action.performWithSender(nil, target: nil)
                return
            }
            if let submenu = element as? UIMenu {
                performAction(titled: title, in: submenu)
            }
        }
    }
}
```

Note: `UIAction.performWithSender(_:target:)` invokes the action handler in tests. `PostListRow.fixture(...)` is a test factory — if one does not exist, add a minimal `extension PostListRow { static func fixture(...) }` in this test file (check first with `grep -rn "extension PostListRow" SpudTests/`; reuse the existing fixture if present, matching its parameter names). `FakePostContextMenuHost` is defined in Step 3.

- [ ] **Step 2: Run the test to verify it fails**

Run: `make test-only ONLY=SpudTests`
Expected: build FAILS — "cannot find 'PostContextMenuBuilder' in scope" / "cannot find type 'PostContextMenuHost'".

- [ ] **Step 3: Create the host protocol + builder**

Create `Spud/Utils/ContextMenus/PostContextMenuBuilder.swift`. The `menu(...)` body is the feed's existing menu assembly (`PostListViewController.swift:2191-2318`) relocated verbatim, with each `self?.<method>(serverPostId:)` call rewired to `host.<method>(serverPostId:)` and `self?.viewModel.row(forServerPostId:)` to `host.postContextRow(forServerPostId:)`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// The per-screen action surface a `PostContextMenuBuilder` menu drives. Any
/// screen that shows a post row (the feed, Search) conforms so it gets the
/// identical long-press menu. Refines the shared vote/save/remind dispatch
/// protocols so vote/save/Remind-Me route through the same outbox/ReminderService
/// paths on every screen.
///
/// The four `…Submenu` members have default implementations (below) so a host
/// only overrides the ones it supports: the feed overrides cross-post-siblings
/// and moderation (feed-only state); Search inherits their nil defaults.
@MainActor
protocol PostContextMenuHost: PostSaveDispatching, PostReminderDispatching {
    /// The feed row for `serverPostId`, or nil if it isn't currently loaded.
    func postContextRow(forServerPostId serverPostId: Int64) -> PostListRow?

    func postReply(serverPostId: Int64)
    func postShare(serverPostId: Int64)
    func postCrossPost(serverPostId: Int64)
    func postVisitCommunity(serverPostId: Int64)
    func postViewAuthor(serverPostId: Int64)
    func postHide(serverPostId: Int64)
    func postBlockAuthor(serverPostId: Int64)
    func postReport(serverPostId: Int64)
    /// Mutes the post's community for `duration` (client-local). Called by the
    /// default `postMuteCommunitySubmenu`.
    func postMuteCommunity(serverPostId: Int64, duration: MuteDuration)

    /// The "Also posted in" cross-post jump submenu, or nil when the post has no
    /// collapsed siblings. Default: nil (Search has no cross-post grouping).
    func postCrossPostSiblingsSubmenu(serverPostId: Int64) -> UIMenu?
    /// The moderation submenu, or nil when the viewer doesn't moderate the
    /// community. Default: nil (Search has no moderation context).
    func postModerationSubmenu(serverPostId: Int64) -> UIMenu?
}

@MainActor
extension PostContextMenuHost {
    func postCrossPostSiblingsSubmenu(serverPostId _: Int64) -> UIMenu? { nil }
    func postModerationSubmenu(serverPostId _: Int64) -> UIMenu? { nil }

    /// The "Remind Me…" submenu, built from the shared `PostReminderDispatching`
    /// target, or nil when the row isn't loaded. Shared across hosts.
    func postRemindMeSubmenu(serverPostId: Int64) -> UIMenu? {
        guard let target = remindMeMenuTarget(serverPostId: serverPostId) else { return nil }
        return makeRemindMeMenu(for: target)
    }

    /// The "Mute c/…" duration submenu, or nil when the community can't be
    /// resolved. Shared across hosts (muting is client-local).
    func postMuteCommunitySubmenu(serverPostId: Int64) -> UIMenu? {
        guard
            let row = postContextRow(forServerPostId: serverPostId),
            let communityName = row.communityName.isEmpty ? nil : row.communityName,
            row.communityActorId != nil
        else { return nil }
        let actions = MuteDuration.allCases.map { duration in
            UIAction(title: duration.menuTitle) { [weak self] _ in
                self?.postMuteCommunity(serverPostId: serverPostId, duration: duration)
            }
        }
        return UIMenu(
            title: String(format: NSLocalizedString("Mute %@", comment: "Context-menu action to mute a community; %@ is the c/ community handle"), "c/\(communityName)"),
            image: UIImage(systemName: "bell.slash"),
            children: actions
        )
    }
}

/// Builds the shared post long-press menu. The single source of truth for the
/// post context menu's structure, used by the feed and Search so the two never
/// drift. Pure: every action calls back into `host`; the builder performs no
/// side effects itself.
@MainActor
enum PostContextMenuBuilder {
    static func menu(
        forServerPostId serverPostId: Int64,
        host: PostContextMenuHost,
        upvoteIcon: UIImage?,
        downvoteIcon: UIImage?
    ) -> UIMenu {
        let upvoteAction = UIAction(
            title: NSLocalizedString("Upvote", comment: ""),
            image: upvoteIcon
        ) { [weak host] _ in
            Task { await host?.vote(serverPostId: serverPostId, action: .upvote) }
        }
        let downvoteAction = UIAction(
            title: NSLocalizedString("Downvote", comment: ""),
            image: downvoteIcon
        ) { [weak host] _ in
            Task { await host?.vote(serverPostId: serverPostId, action: .downvote) }
        }

        let isSaved = host.postContextRow(forServerPostId: serverPostId)?.isSaved ?? false
        let saveAction = UIAction(
            title: isSaved
                ? NSLocalizedString("Unsave", comment: "Context-menu action to unsave a post")
                : NSLocalizedString("Save", comment: "Context-menu action to save a post"),
            image: UIImage(systemName: isSaved ? "bookmark.slash" : "bookmark")
        ) { [weak host] _ in
            host?.toggleSaved(serverPostId: serverPostId)
        }

        let replyAction = UIAction(
            title: NSLocalizedString("Reply", comment: "Context-menu action to reply to a post"),
            image: UIImage(systemName: "arrowshape.turn.up.left")
        ) { [weak host] _ in host?.postReply(serverPostId: serverPostId) }

        let shareAction = UIAction(
            title: NSLocalizedString("Share", comment: "Context-menu action to share a post"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak host] _ in host?.postShare(serverPostId: serverPostId) }

        let crossPostAction = UIAction(
            title: NSLocalizedString("Cross-post", comment: "Context-menu action to re-share a post to another community"),
            image: UIImage(systemName: "arrow.triangle.branch")
        ) { [weak host] _ in host?.postCrossPost(serverPostId: serverPostId) }

        let row = host.postContextRow(forServerPostId: serverPostId)

        let visitCommunityAction = UIAction(
            title: String(
                format: NSLocalizedString("Visit %@", comment: "Context-menu action to open a post's community; %@ is the c/ community handle"),
                row.map { "c/\($0.communityName)" } ?? NSLocalizedString("community", comment: "Generic community noun")
            ),
            image: UIImage(systemName: "person.3")
        ) { [weak host] _ in host?.postVisitCommunity(serverPostId: serverPostId) }

        let viewAuthorAction = UIAction(
            title: row?.creatorName.map {
                String(format: NSLocalizedString("View %@", comment: "Context-menu action to open a post author's profile; %@ is the u/ author handle"), "u/\($0)")
            } ?? NSLocalizedString("View author", comment: "Context-menu action to open a post author's profile"),
            image: UIImage(systemName: "person.crop.circle")
        ) { [weak host] _ in host?.postViewAuthor(serverPostId: serverPostId) }

        let hideAction = UIAction(
            title: NSLocalizedString("Hide", comment: "Context-menu action to hide a post from the feed"),
            image: UIImage(systemName: "eye.slash")
        ) { [weak host] _ in host?.postHide(serverPostId: serverPostId) }

        let blockAction = UIAction(
            title: row?.creatorName.map {
                String(format: NSLocalizedString("Block %@", comment: "Context-menu action to block a post author; %@ is the u/ author handle"), "u/\($0)")
            } ?? NSLocalizedString("Block author", comment: "Context-menu action to block a post author"),
            image: UIImage(systemName: "hand.raised"),
            attributes: .destructive
        ) { [weak host] _ in host?.postBlockAuthor(serverPostId: serverPostId) }

        let reportAction = UIAction(
            title: NSLocalizedString("Report", comment: "Context-menu action to report a post"),
            image: UIImage(systemName: "flag"),
            attributes: .destructive
        ) { [weak host] _ in host?.postReport(serverPostId: serverPostId) }

        var voteChildren: [UIMenuElement] = [upvoteAction, downvoteAction, saveAction]
        if let remindMe = host.postRemindMeSubmenu(serverPostId: serverPostId) {
            voteChildren.append(remindMe)
        }
        let voteGroup = UIMenu(options: .displayInline, children: voteChildren)
        let shareGroup = UIMenu(options: .displayInline, children: [replyAction, shareAction, crossPostAction])

        var navChildren: [UIMenuElement] = [visitCommunityAction, viewAuthorAction]
        if let crossPostMenu = host.postCrossPostSiblingsSubmenu(serverPostId: serverPostId) {
            navChildren.append(crossPostMenu)
        }
        let navGroup = UIMenu(options: .displayInline, children: navChildren)

        var hideChildren: [UIMenuElement] = [hideAction]
        if let muteMenu = host.postMuteCommunitySubmenu(serverPostId: serverPostId) {
            hideChildren.append(muteMenu)
        }
        let hideGroup = UIMenu(options: .displayInline, children: hideChildren)
        let safetyGroup = UIMenu(options: .displayInline, children: [blockAction, reportAction])

        var children: [UIMenuElement] = [voteGroup, shareGroup, navGroup, hideGroup]
        if let modMenu = host.postModerationSubmenu(serverPostId: serverPostId) {
            children.append(modMenu)
        }
        children.append(safetyGroup)
        return UIMenu(title: "", children: children)
    }
}
```

Add the fake host to the test file `SpudTests/PostContextMenuBuilderTests.swift` (it conforms via the shared protocols' requirements; `AccountScope`/`AlertServiceType` come from a test double — reuse whatever `SpudTests` already uses to satisfy `PostVoteDispatching`, e.g. `grep -rn "PostVoteDispatching\|postActionsAccountScope" SpudTests/` for an existing fake; if none, the fake's `postActionsAccountScope`/`postActionsAlertService` can be backed by the existing `SpudTests` account-scope/alert doubles):

```swift
@MainActor
final class FakePostContextMenuHost: UIViewController, PostContextMenuHost {
    var row: PostListRow
    private(set) var votedPostIds: [Int64] = []
    init(row: PostListRow) { self.row = row; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    // PostVoteDispatching / PostSaveDispatching
    var postActionsAccountScope: AccountScope { /* reuse SpudTests' account-scope double */ fatalError("wire to test double") }
    var postActionsAlertService: AlertServiceType { /* reuse SpudTests' alert double */ fatalError("wire to test double") }
    func currentSavedState(serverPostId: Int64) -> Bool { row.isSaved }
    func vote(serverPostId: Int64, action: VoteStatus.Action) async { votedPostIds.append(serverPostId) }

    // PostReminderDispatching
    func remindMeMenuDidChange() { }
    func remindMeMenuTarget(serverPostId: Int64) -> RemindMeMenuTarget? { nil }

    // PostContextMenuHost
    func postContextRow(forServerPostId serverPostId: Int64) -> PostListRow? { row }
    func postReply(serverPostId: Int64) { }
    func postShare(serverPostId: Int64) { }
    func postCrossPost(serverPostId: Int64) { }
    func postVisitCommunity(serverPostId: Int64) { }
    func postViewAuthor(serverPostId: Int64) { }
    func postHide(serverPostId: Int64) { }
    func postBlockAuthor(serverPostId: Int64) { }
    func postReport(serverPostId: Int64) { }
    func postMuteCommunity(serverPostId: Int64, duration: MuteDuration) { }
}
```

Note: the fake overrides `vote(...)` (a protocol-extension default) to record the call — that is legal because the fake declares its own `vote`. To satisfy `postActionsAccountScope`/`postActionsAlertService`, wire them to whatever doubles `SpudTests` already provides for post-action tests; if the only realistic way to get an `AccountScope` in `SpudTests` is a real in-memory scope, the `upvoteInvokesHostVote` test may instead assert via a simpler recording host that overrides `vote`. Keep the assertion on real menu structure regardless.

- [ ] **Step 4: Adopt the builder in the feed (menu byte-identical)**

In `PostListViewController.swift`:
1. Add the four host methods it doesn't already name, as thin wrappers over its existing private methods, and conform. It already conforms to `PostSaveDispatching` (`:1899`) and `PostReminderDispatching` (`:1920`). Add a conformance:

```swift
// MARK: - PostContextMenuHost

extension PostListViewController: PostContextMenuHost {
    func postContextRow(forServerPostId serverPostId: Int64) -> PostListRow? {
        viewModel.row(forServerPostId: serverPostId)
    }
    func postReply(serverPostId: Int64) { replyToPost(serverPostId: serverPostId) }
    func postShare(serverPostId: Int64) { sharePost(serverPostId: serverPostId) }
    func postCrossPost(serverPostId: Int64) { crossPostPost(serverPostId: serverPostId) }
    func postVisitCommunity(serverPostId: Int64) { visitCommunity(serverPostId: serverPostId) }
    func postViewAuthor(serverPostId: Int64) { viewAuthor(serverPostId: serverPostId) }
    func postHide(serverPostId: Int64) { hidePost(serverPostId: serverPostId) }
    func postBlockAuthor(serverPostId: Int64) { blockAuthor(serverPostId: serverPostId) }
    func postReport(serverPostId: Int64) { reportPost(serverPostId: serverPostId) }
    func postMuteCommunity(serverPostId: Int64, duration: MuteDuration) {
        muteCommunity(serverPostId: serverPostId, duration: duration)
    }
    // Feed-only submenus keep the feed's existing behavior (override the nil defaults).
    func postCrossPostSiblingsSubmenu(serverPostId: Int64) -> UIMenu? {
        crossPostSiblingsMenu(serverPostId: serverPostId)
    }
    func postModerationSubmenu(serverPostId: Int64) -> UIMenu? {
        postModerationMenu(serverPostId: serverPostId)
    }
}
```

2. Replace the inline menu body (`PostListViewController.swift:2191-2318`, the `actionProvider` closure's contents from `let upvoteAction` through `return UIMenu(...)`) with a builder call, preserving the outer `UIContextMenuConfiguration` (identifier + previewProvider) unchanged:

```swift
            actionProvider: { [weak self] _ in
                guard
                    let self,
                    case let .post(serverPostId) = dataSource.itemIdentifier(for: indexPath)
                else { return nil }
                return PostContextMenuBuilder.menu(
                    forServerPostId: serverPostId,
                    host: self,
                    upvoteIcon: generalAppearance.upvoteIcon,
                    downvoteIcon: generalAppearance.downvoteIcon
                )
            }
```

3. The feed's now-unused inline `makeMuteCommunityMenu(serverPostId:communityName:)` (`:1798`) is superseded by the shared `postMuteCommunitySubmenu`; delete it and its now-unused helper only if nothing else calls it (`grep -n "makeMuteCommunityMenu" Spud/Scenes/PostList/PostListViewController.swift` — if the only caller was the inline menu, remove it; otherwise leave it). Keep `muteCommunity(serverPostId:duration:)` (now called by the host method).

- [ ] **Step 5: Run tests + build; verify feed menu unchanged**

Run: `make test-only ONLY=SpudTests` — the builder tests pass.
Run: `make build` — the app compiles (feed adopts the builder).
Expected: green. The feed's long-press menu is structurally identical (same groups/titles/order); this is verified by the builder unit test asserting the full structure and by the existing feed UITest.

- [ ] **Step 6: Format + commit**

Run: `mint run swiftformat Spud/Utils/ContextMenus/PostContextMenuBuilder.swift Spud/Scenes/PostList/PostListViewController.swift SpudTests/PostContextMenuBuilderTests.swift`

```bash
git add Spud/Utils/ContextMenus/PostContextMenuBuilder.swift \
        Spud/Scenes/PostList/PostListViewController.swift \
        SpudTests/PostContextMenuBuilderTests.swift
git commit -F- <<'EOF'
refactor: extract PostContextMenuBuilder from the feed

The post long-press menu is now produced by a shared builder driven by a
PostContextMenuHost delegate; the feed adopts it (menu unchanged) so Search
can reuse the identical menu. Builder unit tests assert the menu structure.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY
EOF
```

---

## Task 2: Search adopts the post menu

**Files:**
- Modify: `Spud/Scenes/Search/SearchViewController.swift` (conform to `PostContextMenuHost`; add `contextMenuConfigurationForRowAt`)
- Modify: `SpudUITests/SpudUITests.swift` (Search-post nav UITest)

**Interfaces:**
- Consumes: `PostContextMenuBuilder.menu(forServerPostId:host:upvoteIcon:downvoteIcon:)`, `PostContextMenuHost` (Task 1). Search seams: `viewModel.accountScope`, `viewModel.results.posts` (the current post results), `dependencies.own`/`.nested`, `accountKeychainId`, `presentSignInGate(title:)`, `alertService`, `appearanceService.general`, `dataSource.itemIdentifier(for:)`, the nav helpers `pushCommunity(name:instance:)`/`pushPerson(personId:instance:)` (`SearchViewController.swift:515,525`).
- Produces: a working post context menu in Search; nothing consumed by later tasks.

Search's post-action implementations mirror the feed's (`PostListViewController.swift:1608-1837`), adapted to Search's `viewModel.accountScope`/`dependencies`. The `PostListRow` carried by `SearchPostResult.row` provides `communityActorId`, `creatorActorId`, `creatorPersonId`, `communityName`, `creatorName`, `originalPostUrl`, `title`, `url` — the same fields the feed methods read.

- [ ] **Step 1: Write the failing Search-post nav UITest**

In `SpudUITests/SpudUITests.swift`, add a test mirroring `test_VisitCommunityFromPostContextMenu_showsNavbarActions` (`~:237`) but starting from a Search post result: stub a search response with one post, drive Search, long-press the post cell, tap "Visit c/<community>", assert the pushed community screen appears. Reuse the existing search UITest stubbing pattern (`grep -rn "search" SpudUITests/*.swift`; SBT stub for the neutral `GET /search`). If no search UITest scaffold exists, add one following `test_VisitCommunityFromPostContextMenu`'s structure (stub, launch signed-out or signed-in seed, `app.searchFields`, `.press(forDuration:)` on the cell, `app.collectionViews.buttons["Visit c/..."]`, assert nav).

```swift
func test_Search_PostResultContextMenu_VisitCommunity() throws {
    // Stub GET /search -> one post in community "tincidunt" (reuse the search
    // fixture shape); enter a query, long-press the post row, tap Visit, assert
    // the community screen's navbar action appears (same assertion style as
    // test_VisitCommunityFromPostContextMenu_showsNavbarActions).
    // ... concrete stub + steps mirroring the cited existing test ...
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `make test-only ONLY=SpudUITests` (or the full `make test`).
Expected: FAIL — long-press produces no menu yet (no `contextMenuConfigurationForRowAt` in Search), so the "Visit" button is never found.

- [ ] **Step 3: Conform `SearchViewController` to `PostContextMenuHost`**

Add an extension to `SearchViewController.swift` (place near its other extensions):

```swift
// MARK: - PostContextMenuHost (search post rows)

extension SearchViewController: PostContextMenuHost {
    // PostVoteDispatching / PostSaveDispatching
    var postActionsAccountScope: AccountScope { viewModel.accountScope }
    var postActionsAlertService: AlertServiceType { alertService }
    func currentSavedState(serverPostId: Int64) -> Bool {
        postContextRow(forServerPostId: serverPostId)?.isSaved ?? false
    }

    // PostReminderDispatching
    func remindMeMenuDidChange() { }
    func remindMeMenuTarget(serverPostId: Int64) -> RemindMeMenuTarget? {
        guard let row = postContextRow(forServerPostId: serverPostId) else { return nil }
        let instanceHost = row.communityActorId.flatMap { InstanceActorId(from: $0)?.host }
            ?? viewModel.accountScope.instanceActorId?.host
            ?? ""
        return RemindMeMenuTarget(
            postServerId: row.serverPostId,
            apId: row.originalPostUrl,
            title: row.title,
            communityName: row.communityName,
            instanceHost: instanceHost,
            thumbnailUrl: row.thumbnailUrl,
            numberOfComments: row.numberOfComments
        )
    }

    // PostContextMenuHost
    func postContextRow(forServerPostId serverPostId: Int64) -> PostListRow? {
        viewModel.results.posts.first { $0.row.serverPostId == serverPostId }?.row
    }

    func postReply(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to comment", comment: "Sign-in gate title when a signed-out user tries to comment"))
            return
        }
        Haptics.tap()
        let composer = ComposerViewController.makeSheet(
            target: .postReply(serverPostId: Lemmy.PostID(serverPostId)),
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.own
        )
        present(composer, animated: true)
    }

    func postShare(serverPostId: Int64) {
        guard let url = LinkURL.forPost(
            instance: preferencesService.shareLinkInstance,
            originalPostUrl: postContextRow(forServerPostId: serverPostId)?.originalPostUrl,
            serverPostId: serverPostId,
            instanceActorId: viewModel.accountScope.instanceActorId
        ) else { Haptics.warning(); return }
        presentShareSheet(for: url)
    }

    func postCrossPost(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to post", comment: "Sign-in gate title when a signed-out user tries to cross-post"))
            return
        }
        guard let row = postContextRow(forServerPostId: serverPostId) else { Haptics.warning(); return }
        Haptics.tap()
        let composer = NewPostViewController.makeCrossPostSheet(
            initialTitle: row.title,
            initialUrl: row.url,
            initialBody: crossPostBody(originalApId: row.originalPostUrl, originalBody: nil),
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.own
        ) { [weak self] clientToken in
            guard let window = self?.view.window as? MainWindow else { return }
            window.displayPending(clientToken: clientToken, accountKeychainId: self?.accountKeychainId ?? "")
        }
        present(composer, animated: true)
    }

    func postVisitCommunity(serverPostId: Int64) {
        guard
            let row = postContextRow(forServerPostId: serverPostId),
            let actorId = row.communityActorId,
            let instance = InstanceActorId(from: actorId)
        else { Haptics.warning(); return }
        Haptics.tap()
        pushCommunity(name: row.communityName, instance: instance)
    }

    func postViewAuthor(serverPostId: Int64) {
        guard
            let row = postContextRow(forServerPostId: serverPostId),
            let actorId = row.creatorActorId,
            let instance = InstanceActorId(from: actorId)
        else { Haptics.warning(); return }
        Haptics.tap()
        pushPerson(personId: Lemmy.PersonID(row.creatorPersonId), instance: instance)
    }

    func postHide(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to hide posts", comment: "Sign-in gate title when a signed-out user tries to hide a post"))
            return
        }
        guard viewModel.accountScope.capabilities.can(.hidePosts) else {
            presentCapabilityGate(for: .hidePosts, host: viewModel.accountScope.instanceActorId?.hostWithPort, sourceView: nil)
            return
        }
        Task { [weak self] in
            Haptics.tap()
            do {
                try await self?.viewModel.accountScope.lemmyService.hidePost(serverPostId: Lemmy.PostID(serverPostId), hidden: true)
            } catch { self?.alertService.handle(error, for: .hidePost) }
        }
    }

    func postBlockAuthor(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to block", comment: "Sign-in gate title when a signed-out user tries to block"))
            return
        }
        guard let row = postContextRow(forServerPostId: serverPostId) else { return }
        let handle = row.creatorName ?? NSLocalizedString("this user", comment: "Fallback author handle when the name is unknown")
        presentDestructiveConfirmation(
            title: String(format: NSLocalizedString("Block %@?", comment: "Block user confirmation title"), handle),
            message: NSLocalizedString("You won't see posts or comments from this user. You can unblock them later.", comment: "Block user confirmation message"),
            confirmTitle: NSLocalizedString("Block", comment: "Block user confirm button"),
            sourceView: view
        ) { [weak self] in
            Task {
                do { try await self?.viewModel.accountScope.lemmyService.setBlocked(serverPersonId: Lemmy.PersonID(row.creatorPersonId), blocked: true) }
                catch { self?.alertService.handle(error, for: .setBlockedPerson) }
            }
        }
    }

    func postReport(serverPostId: Int64) {
        guard !viewModel.accountScope.isSignedOut else {
            presentSignInGate(title: NSLocalizedString("Sign in to report", comment: "Sign-in gate title when a signed-out user tries to report"))
            return
        }
        presentReportReasonAlert(
            title: NSLocalizedString("Report post", comment: "Report post dialog title"),
            message: NSLocalizedString("Tell the moderators why you're reporting this post.", comment: "Report post dialog message")
        ) { [weak self] reason in
            Task {
                do {
                    try await self?.viewModel.accountScope.lemmyService.reportPost(serverPostId: Lemmy.PostID(serverPostId), reason: reason)
                    Haptics.success()
                    self?.presentReportSubmittedConfirmation()
                } catch { self?.alertService.handle(error, for: .reportPost) }
            }
        }
    }

    func postMuteCommunity(serverPostId: Int64, duration: MuteDuration) {
        guard let row = postContextRow(forServerPostId: serverPostId), let actorId = row.communityActorId else { Haptics.warning(); return }
        Haptics.tap()
        // Client-local mute via the same AppDatabase path Discover uses.
        Task { [weak self] in
            await self?.viewModel.accountScope.appDatabase?.muteCommunity(communityActorId: actorId, until: duration.until)
        }
    }
}
```

Notes for the implementer:
- Confirm the exact helper availability with `grep`: `presentShareSheet`, `presentReportReasonAlert`, `presentReportSubmittedConfirmation`, `presentDestructiveConfirmation`, `presentCapabilityGate`, `presentSignInGate` are shared `UIViewController` extensions (the feed uses them from `PostListViewController`). If any is NOT a shared extension but a private feed method, lift it to a `UIViewController` extension in its own small file so both screens use it (do not duplicate).
- `viewModel.accountScope.appDatabase` / the exact client-local mute call: mirror how `DiscoverViewModel.mute(_:duration:)` performs it (`Spud/Scenes/Discover/DiscoverViewModel.swift`) — it calls `AppDatabase.muteCommunitySync(...)`. Use the same `AppDatabase` mute API the feed's `viewModel.muteCommunity(communityActorId:until:)` ultimately calls; wire Search's `postMuteCommunity` to that same API (confirm the exact signature with `grep -rn "func muteCommunity" SpudDataKit/`).
- `SearchViewModel` must expose `results` (the current `SearchResults`) and `preferencesService` for the above. Confirm/add read-only access: `grep -n "var results\|preferencesService" Spud/Scenes/Search/SearchViewModel.swift`; if `results` is private, add an internal getter.

- [ ] **Step 4: Attach the menu in Search's delegate**

Add to `SearchViewController`'s `UITableViewDelegate` extension (`:585`):

```swift
    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return nil }
        switch item {
        case let .post(result):
            let general = appearanceService.general
            return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }
                return PostContextMenuBuilder.menu(
                    forServerPostId: result.row.serverPostId,
                    host: self,
                    upvoteIcon: general.upvoteIcon,
                    downvoteIcon: general.downvoteIcon
                )
            }
        case .community, .user, .comment, .instance, .openURL:
            return nil // filled in by Tasks 3-6
        }
    }
```

Confirm `SearchViewController` has `appearanceService` (`grep -n "appearanceService" Spud/Scenes/Search/SearchViewController.swift`); if not, it's on `dependencies.own` (`HasAppearanceService`) — access it the same way the feed does.

- [ ] **Step 5: make project (no new files here) + build + run tests**

Run: `make build` then `make test` (the whole plan — this touches a VC's conformances; build the test targets to catch any double gaps).
Expected: the Search-post nav UITest passes; app + tests green.

- [ ] **Step 6: Format + commit**

Run: `mint run swiftformat Spud/Scenes/Search/SearchViewController.swift SpudUITests/SpudUITests.swift` (+ `SearchViewModel.swift` if edited).

```bash
git add Spud/Scenes/Search/SearchViewController.swift SpudUITests/SpudUITests.swift
# add Spud/Scenes/Search/SearchViewModel.swift if you exposed results/preferencesService
git commit -F- <<'EOF'
feat: post context menu on search post results

SearchViewController conforms to PostContextMenuHost and attaches the shared
post menu to post results, reaching feed parity. UITest covers the
long-press -> Visit community navigation.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011EaJJgwwrWu2oxRdkAZtFY
EOF
```

---

## Task 3: Community context menu

**Files:**
- Create: `Spud/Utils/ContextMenus/CommunityContextMenuBuilder.swift`
- Modify: `Spud/Scenes/Search/SearchResults.swift:68-123` (enrich `SearchCommunityResult`)
- Modify: `Spud/Scenes/Search/SearchViewController.swift` (conform + attach for `.community`)
- Test: `SpudTests/CommunityContextMenuBuilderTests.swift`
- Modify: `SpudUITests/SpudUITests.swift` (community nav UITest)

**Interfaces:**
- Consumes: `SearchCommunityResult` (enriched), `lemmyService.setSubscribed(serverCommunityId:subscribed:)` (`LemmyService.swift:227`), `lemmyService.setBlocked(serverCommunityId:blocked:)` (`LemmyService+Safety.swift:52` — confirm which `setBlocked` overload is community), `AppDatabase.muteCommunitySync`/`isCommunityMutedSync`/`unmuteCommunitySync` (keyed by `communityActorId`), `MuteDuration`.
- Produces: `CommunityContextMenuHost` + `CommunityContextMenuBuilder.menu(for: SearchCommunityResult, host:) -> UIMenu`.

Items mirror Discover's `CommunityContextMenu` (`Spud/Scenes/Discover/CommunityContextMenu.swift`): Open, Subscribe/Unsubscribe, Mute(duration submenu)/Unmute, Share, Copy link, Block (destructive).

- [ ] **Step 1: Enrich `SearchCommunityResult`** — add `communityUrl: String` (the `community.apId` the init already resolves) and `isBlocked: Bool`.

In `SearchResults.swift`, add the two stored properties + init params + map them in `init?(view:)`:

```swift
    let communityUrl: String
    let isBlocked: Bool
```
```swift
    // in init?(view:), after computing `instance`:
        communityUrl = community.apId
        isBlocked = view.blocked
```
Confirm `Lemmy.CommunityView` exposes `blocked` (neutral view: `grep -rn "var blocked" <LemmyKit checkout>/Neutral/CommunityView.swift`). If it is not present, drop `isBlocked` from the model and resolve block state in the host from the account's block list at menu-build time instead (mirror how `CommunityViewController` reads block state); adjust the builder's Block/Unblock accordingly. Update the memberwise `init` + all its existing call sites (search `SearchCommunityResult(` — the `init?(view:)` is the production site; tests may construct it).

- [ ] **Step 2: Write the failing builder test** (`SpudTests/CommunityContextMenuBuilderTests.swift`) asserting the menu contains Open Community, Subscribe (or Unsubscribe when subscribed), Mute (or Unmute when muted), Share, Copy Link, and a destructive Block Community; and that "Open Community" invokes the host's open. Use a `FakeCommunityContextMenuHost` recording calls. Follow the `allTitles`/`performAction` helpers from Task 1.

- [ ] **Step 3: Run to verify it fails** — `make test-only ONLY=SpudTests` (missing type).

- [ ] **Step 4: Create `CommunityContextMenuBuilder.swift`** — the host protocol + builder:

```swift
@MainActor
protocol CommunityContextMenuHost: UIViewController {
    func communityOpen(_ result: SearchCommunityResult)
    func communitySetSubscribed(_ result: SearchCommunityResult, subscribed: Bool)
    func communityIsMuted(_ result: SearchCommunityResult) -> Bool
    func communityMute(_ result: SearchCommunityResult, duration: MuteDuration)
    func communityUnmute(_ result: SearchCommunityResult)
    func communityBlock(_ result: SearchCommunityResult)
}

@MainActor
enum CommunityContextMenuBuilder {
    static func menu(for result: SearchCommunityResult, host: CommunityContextMenuHost) -> UIMenu {
        // Open | Subscribe/Unsubscribe | Divider(inline groups) | Mute/Unmute | Share/Copy | Block(destructive)
        // Mirror CommunityContextMenu.swift's items exactly, as UIAction/UIMenu.
        // Share/Copy use URL(string: result.communityUrl); build a share UIAction that
        // calls host.present(UIActivityViewController...) via a host method or a shared
        // presentShareSheet(for:) extension, and a Copy action setting UIPasteboard.general.url.
        // ... concrete UIMenu assembly ...
    }
}
```
Fill in the concrete `UIMenu` assembly following the item list + copy from `CommunityContextMenu.swift:20-71` (Open Community, Subscribe/Unsubscribe with the checkmark/plus images, Mute duration submenu vs Unmute, Share via `presentShareSheet(for:)`, Copy Link via `UIPasteboard.general.url`, Block Community destructive). Group with `.displayInline` submenus matching the SwiftUI `Divider()` placements (open+subscribe | mute | share+copy | block).

- [ ] **Step 5: Conform `SearchViewController` + attach `.community`** — implement the host methods (reuse the existing `setSubscribed(result:subscribe:cell:)` at `:468` for subscribe; `communityOpen` reuses the `.community` tap push at `:600-606`; block via `lemmyService.setBlocked(serverCommunityId:blocked:)`; mute/unmute/isMuted via the `AppDatabase` mute helpers keyed by `result.communityUrl`/actorId). Replace the `.community` arm of `contextMenuConfigurationForRowAt` (Task 2 Step 4) with a real config returning `CommunityContextMenuBuilder.menu(for: result, host: self)`.

- [ ] **Step 6: Write + run a community nav UITest** (long-press community result -> "Open Community" -> asserts the pushed community screen), mirroring Task 2's UITest.

- [ ] **Step 7: `make project` (new file) + build + `make test` + format + commit** (`feat: community context menu on search community results`, trailers verbatim). Confirm `SearchResultCellsSnapshotTests` stays byte-identical (enrichment is menu-only) — run `make snapshot` only if you suspect a cell change; you shouldn't have touched cell rendering.

---

## Task 4: Comment context menu

**Files:**
- Create: `Spud/Utils/ContextMenus/CommentContextMenuBuilder.swift`
- Modify: `Spud/Scenes/Search/SearchResults.swift:170-210` (enrich `SearchCommentResult`)
- Modify: `Spud/Scenes/Search/SearchViewController.swift` (conform + attach `.comment`)
- Test: `SpudTests/CommentContextMenuBuilderTests.swift`

**Interfaces:**
- Consumes: enriched `SearchCommentResult`, the post-detail comment action path (`PostDetailViewController.swift:2177-2298` — the reference for comment Upvote/Downvote/Save/Report dispatch), `lemmyService.reportComment` (`LemmyService+Safety.swift:128`), the comment vote/save `lemmyService` calls PostDetail uses.
- Produces: `CommentContextMenuHost` + `CommentContextMenuBuilder.menu(for: SearchCommentResult, host:) -> UIMenu`.

Items: Open thread, Upvote, Downvote, Save/Unsave, Share, Copy link, View author, Report (destructive).

- [ ] **Step 1: Enrich `SearchCommentResult`** — add `creatorPersonId: Lemmy.PersonID`, `creatorActorId: String?`, `communityName: String`, `communityActorId: String?`, `isSaved: Bool`, `myVote: VoteDirection` (or the app's vote-state type). Map in `init(view:)`:
```swift
        creatorPersonId = Lemmy.PersonID(view.creator.id)
        creatorActorId = view.creator.apId
        communityName = view.community.name
        communityActorId = view.community.apId
        isSaved = view.saved
        myVote = view.myVote
```
Confirm the exact field names on the neutral `CommentView`/`Community`/`Person` (`grep -rn "saved\|apId\|myVote" <LemmyKit checkout>/Neutral/CommentView.swift`). `myVote` is `commentActions?.vote` per `CommentView.swift:102`. Update the memberwise init + call sites.

- [ ] **Step 2-3: Failing builder test + verify fail** — assert Open thread / Upvote / Downvote / Save (Unsave when saved) / Share / Copy link / View author / destructive Report; "Open thread" invokes host open.

- [ ] **Step 4: Create `CommentContextMenuBuilder.swift`** — `CommentContextMenuHost` (methods: `commentOpenThread`, `commentVote(_:direction:)`, `commentToggleSave(_:)`, `commentShare(_:)`, `commentViewAuthor(_:)`, `commentReport(_:)`) + the builder assembling the items (Save label from `result.isSaved`; Upvote/Downvote selected state from `result.myVote` if reflecting selection).

- [ ] **Step 5: Conform + attach `.comment`** — `commentOpenThread` reuses the existing `.comment` tap (`window.display(serverPostId:)` at `:617-619`); vote/save/report **mirror `PostDetailViewController`'s comment actions** (cite `:2177-2298`) using the same `lemmyService` comment vote/save/report calls (confirm signatures: `grep -rn "func vote(commentId\|func setSaved(commentId\|func reportComment" SpudDataKit/Services/Lemmy/*.swift`); `commentViewAuthor` pushes the person via `pushPerson(personId: result.creatorPersonId, instance:)` (resolve instance from `result.creatorActorId`); Share/Copy build the comment URL (mirror `LinkURL` for a comment, or the post URL + fragment — reuse whatever the post-detail comment Share uses). Replace the `.comment` arm.

- [ ] **Step 6: build + `make test` + format + commit** (`feat: comment context menu on search comment results`).

---

## Task 5: User context menu

**Files:**
- Create: `Spud/Utils/ContextMenus/UserContextMenuBuilder.swift`
- Modify: `Spud/Scenes/Search/SearchResults.swift:127-166` (optional block-state resolution note)
- Modify: `Spud/Scenes/Search/SearchViewController.swift` (conform + attach `.user`)
- Test: `SpudTests/UserContextMenuBuilderTests.swift`
- Modify: `SpudUITests/SpudUITests.swift` (user nav UITest)

**Interfaces:**
- Consumes: `SearchUserResult`, `lemmyService.setBlocked(serverPersonId:blocked:)` (`LemmyService+Safety.swift:17`), the person block-state source used by `PersonViewController` (`:1027-1058`).
- Produces: `UserContextMenuHost` + `UserContextMenuBuilder.menu(for: SearchUserResult, isBlocked: Bool, host:) -> UIMenu`.

Items: Open profile, Copy handle, Share, Block/Unblock (destructive when blocking).

- [ ] **Step 1-3: Failing test + verify fail** — assert Open profile / Copy handle / Share / destructive Block (or Unblock when `isBlocked`); Open invokes host open.

- [ ] **Step 4: Create `UserContextMenuBuilder.swift`** — `UserContextMenuHost` (`userOpen`, `userCopyHandle`, `userShare`, `userSetBlocked(_:blocked:)`) + builder. `isBlocked` is passed in (resolved by the host from the account's block list at build time — mirror `PersonViewController`'s block-state read; if not cheaply available, always show "Block user" and omit Unblock, per the spec).

- [ ] **Step 5: Conform + attach `.user`** — `userOpen` reuses the `.user` tap push (`:608-615`); `userCopyHandle` sets `UIPasteboard.general.string = result.qualifiedName`; `userShare` shares the profile URL (build from `result` actor id / instance); `userSetBlocked` gates sign-in then `lemmyService.setBlocked(serverPersonId:blocked:)` with a destructive confirmation (reuse `presentDestructiveConfirmation`). Resolve `isBlocked` for the menu from the account block list (or pass `false` and offer Block only). Replace the `.user` arm.

- [ ] **Step 6: user nav UITest** (long-press user -> Open profile -> asserts profile screen), build + `make test` + format + commit (`feat: user context menu on search user results`).

---

## Task 6: Instance context menu + docs

**Files:**
- Create: `Spud/Utils/ContextMenus/InstanceContextMenuBuilder.swift`
- Modify: `Spud/Scenes/Search/SearchViewController.swift` (conform + attach `.instance`)
- Test: `SpudTests/InstanceContextMenuBuilderTests.swift`
- Modify: `docs/features/search.md`, `docs/features/README.md`

**Interfaces:**
- Consumes: `SearchInstanceResult` (carries `record: ExplorerInstanceRecord`, `baseurl`), the sign-in/add-account flow (`SiteListRow.forTypedInstance(_:)` + the login flow used elsewhere; `InstanceActorId(from: "https://<baseurl>")`).
- Produces: `InstanceContextMenuHost` + `InstanceContextMenuBuilder.menu(for: SearchInstanceResult, host:) -> UIMenu`.

Items: Open, Copy link, Share, Add account here.

- [ ] **Step 1-3: Failing test + verify fail** — assert Open / Copy link / Share / Add account here; Open invokes host open.

- [ ] **Step 4: Create `InstanceContextMenuBuilder.swift`** — `InstanceContextMenuHost` (`instanceOpen`, `instanceCopyLink`, `instanceShare`, `instanceAddAccount`) + builder assembling the four items.

- [ ] **Step 5: Conform + attach `.instance`** — `instanceOpen` reuses `openInstance(record:)` (`:546`); `instanceCopyLink` sets `UIPasteboard.general.url = URL(string: "https://\(result.baseurl)")`; `instanceShare` shares that URL; `instanceAddAccount` presents the login flow targeted at the instance — build `InstanceActorId(from: "https://\(result.baseurl)")`, then present the same login screen the app uses for adding an account (mirror how the Account/onboarding flow presents `LoginViewController` from a `SiteListRow.forTypedInstance(instance)`; confirm the exact presentation seam with `grep -rn "LoginViewController(row:" Spud/`). Replace the `.instance` arm.

- [ ] **Step 6: Docs** — update `docs/features/search.md` (replace the "no context menu today" note ~`:109`; add Behavior + Given/When/Then scenarios: long-pressing each result type opens a menu; the post menu matches the feed; mutating actions gate when signed-out; read-only actions work signed-out; a Save from search does not live-update the search row). Update `docs/features/README.md` capability table + "Feature coverage by area" map. No `.swift` links.

- [ ] **Step 7: build + `make test` + format + commit** (`feat: instance context menu on search results + docs`).

---

## Self-Review

**Spec coverage:** §2.1 builders+delegates → all tasks; §2.2 attachment in Search → Tasks 2-6 `contextMenuConfigurationForRowAt`; §2.3 post extraction → Task 1; §3.1-3.5 the five menus → Tasks 2-6; §4 enrichment → Tasks 3 (community), 4 (comment), 5 (user block-state); §5 sign-in gate + dispatch reuse + no-live-update limitation → in every mutating action + documented in Task 6; §6 testing (builder unit tests + nav UITests + snapshots stay byte-identical) → each task; §7 out-of-scope respected (no own-comment edit/delete/moderation on comment menu; no SwiftUI CommunityContextMenu change; no live search-row observation); §8 phasing → the tasks (phase 1 split into Tasks 1+2 for reviewability); §9 docs → Task 6.

**Placeholder scan:** Tasks 1-2 carry complete code. Tasks 3-6 give complete enrichment + protocol + attachment structure with the builder `UIMenu` assembly specified by an explicit item list + the exact reuse citation (Discover `CommunityContextMenu`, PostDetail comment menu, PersonViewController block state, the login flow) — deliberate, because those actions ARE existing flows the builder must mirror, and the reviewer/implementer resolves the cited method. No "TBD"/"add error handling"/"similar to Task N".

**Type consistency:** `PostContextMenuHost`/`PostContextMenuBuilder.menu(forServerPostId:host:upvoteIcon:downvoteIcon:)` used identically in Tasks 1-2. Host method names (`postReply`/`postShare`/`postCrossPost`/`postVisitCommunity`/`postViewAuthor`/`postHide`/`postBlockAuthor`/`postReport`/`postMuteCommunity`/`postContextRow`) match between the protocol (Task 1 Step 3), the feed conformance (Task 1 Step 4), and the Search conformance (Task 2 Step 3). Enrichment field names (`communityUrl`/`isBlocked`, `creatorPersonId`/`creatorActorId`/`communityName`/`communityActorId`/`isSaved`/`myVote`) are consistent between `SearchResults.swift` edits and the builders that read them.

**Implementer verification points (call out in dispatch):** confirm `Lemmy.CommunityView.blocked` / `CommentView.saved` field names against the pinned LemmyKit checkout (Tasks 3-4 Step 1); confirm `presentShareSheet`/`presentReportReasonAlert`/`presentDestructiveConfirmation`/`presentCapabilityGate`/`presentSignInGate`/`presentReportSubmittedConfirmation` are shared `UIViewController` extensions (Task 2 Step 3 — lift any that are private-to-feed rather than duplicate); confirm the comment vote/save `lemmyService` signatures against PostDetail (Task 4 Step 5); confirm `SearchViewModel` exposes `results`/`preferencesService` (Task 2 Step 3); confirm the `AppDatabase` community-mute API name (Task 2/3).
