# Search: Open a Pasted Lemmy URL — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the Search field contains a Lemmy URL (post / comment / community / user / instance), show an "Open in Spud" row at the top of results that navigates to that object via the app's existing internal routing.

**Architecture:** A pure `SearchURLDetector` wraps `LemmyURLParser.classify` (known instances + mentions) and adds an unknown-host fallback for Lemmy-shaped paths, returning a `SearchURLSuggestion`. `SearchViewModel` computes the suggestion synchronously on each keystroke and skips the text-search network call while one is present. `SearchViewController` renders a dedicated top section and routes the tap locally (mirroring `PostDetailViewController`'s link handling), using federated `resolveObject` for `.objectAtURL`.

**Tech Stack:** Swift 6, UIKit, GRDB (Explorer directory lookup), `@Observable` view model, `ObservationStream`, XCTest + pointfreeco SnapshotTesting.

## Global Constraints

- Swift 6.0 language mode; `SWIFT_STRICT_CONCURRENCY = complete`. View model and VC are `@MainActor`.
- No emojis in code, comments, or commit messages. Conventional commit subjects (`feat:`, `test:`, etc.).
- After adding/removing source files, run `make project` (XcodeGen) before building.
- Build/test on the iPhone 17 Pro simulator: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`. Snapshot tests run on the `SpudSnapshots` test plan; first run records refs and fails, rerun verifies (any sim — cell snapshots pin display scale).
- Commit message footer (both lines):
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP`
- App-target unit tests use **XCTest** + `@testable import Spud` (see `SpudTests/LemmyURLParserTests.swift`), NOT Swift Testing.
- Stage explicit paths when committing (never `git add -A`): the working tree has unrelated dirty snapshot PNGs.

---

## File Structure

- `Spud/Scenes/Search/SearchURLDetector.swift` — NEW. Pure detection: `SearchURLSuggestion` + `SearchURLDetector.detect`.
- `SpudTests/SearchURLDetectorTests.swift` — NEW. Detector unit tests.
- `Spud/Scenes/Search/SearchViewModel.swift` — MODIFY. Inject `isKnownInstance`; add `urlSuggestion`; set it in `queryChanged`; skip search when present.
- `SpudTests/SearchViewModelURLSuggestionTests.swift` — NEW. View-model wiring tests.
- `Spud/Scenes/Search/Cells/SearchOpenURLCell.swift` — NEW. The "Open in Spud" cell.
- `SpudSnapshotTests/SearchOpenURLCellSnapshotTests.swift` — NEW. Cell snapshot.
- `Spud/Scenes/Search/SearchViewController.swift` — MODIFY. New section + cell registration + render + tap routing helpers.

---

## Task 1: SearchURLDetector (pure detection + tests)

**Files:**
- Create: `Spud/Scenes/Search/SearchURLDetector.swift`
- Test: `SpudTests/SearchURLDetectorTests.swift`

**Interfaces:**
- Consumes: `LemmyURLParser.classify(url:isKnownInstance:) -> URL.SpudInternalLink?`; `URL.SpudInternalLink` (cases `.post`, `.person`, `.community`, `.objectAtURL`, `.instance`); `InstanceActorId(from:)` (from `SpudUtilKit`).
- Produces:
  - `struct SearchURLSuggestion { enum Kind: Hashable { case post, comment, community, user, instance }; let kind: Kind; let link: URL.SpudInternalLink; let displayURL: String }`
  - `enum SearchURLDetector { static func detect(query: String, isKnownInstance: (String) -> Bool) -> SearchURLSuggestion? }`

- [ ] **Step 1: Write the failing tests**

Create `SpudTests/SearchURLDetectorTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import XCTest
@testable import Spud

final class SearchURLDetectorTests: XCTestCase {
    private let known: (String) -> Bool = { ["lemmy.world", "beehaw.org"].contains($0) }

    private func detect(_ s: String) -> SearchURLSuggestion? {
        SearchURLDetector.detect(query: s, isKnownInstance: known)
    }

    // Known instance: classify drives kind + link.
    func test_knownPost_isPostKind_objectAtURL() throws {
        let s = try XCTUnwrap(detect("https://lemmy.world/post/123"))
        XCTAssertEqual(s.kind, .post)
        guard case let .objectAtURL(url) = s.link else { return XCTFail("expected .objectAtURL") }
        XCTAssertEqual(url.absoluteString, "https://lemmy.world/post/123")
    }

    func test_knownComment_isCommentKind() throws {
        let s = try XCTUnwrap(detect("https://lemmy.world/comment/9"))
        XCTAssertEqual(s.kind, .comment)
        guard case .objectAtURL = s.link else { return XCTFail("expected .objectAtURL") }
    }

    func test_knownUser_isUserKind() throws {
        let s = try XCTUnwrap(detect("https://beehaw.org/u/alice"))
        XCTAssertEqual(s.kind, .user)
    }

    func test_knownCommunity_isCommunityKind_communityLink() throws {
        let s = try XCTUnwrap(detect("https://lemmy.world/c/technology"))
        XCTAssertEqual(s.kind, .community)
        guard case let .community(name, instance) = s.link else { return XCTFail("expected .community") }
        XCTAssertEqual(name, "technology")
        XCTAssertEqual(instance.host, "lemmy.world")
    }

    func test_bareKnownInstance_isInstanceKind() throws {
        let s = try XCTUnwrap(detect("https://beehaw.org"))
        XCTAssertEqual(s.kind, .instance)
        guard case .instance = s.link else { return XCTFail("expected .instance") }
    }

    // Unknown host: path-shape fallback -> objectAtURL with derived kind.
    func test_unknownPost_isOffered_objectAtURL() throws {
        let s = try XCTUnwrap(detect("https://small.example/post/1"))
        XCTAssertEqual(s.kind, .post)
        guard case let .objectAtURL(url) = s.link else { return XCTFail("expected .objectAtURL") }
        XCTAssertEqual(url.absoluteString, "https://small.example/post/1")
    }

    func test_unknownComment_isOffered() throws {
        let s = try XCTUnwrap(detect("https://small.example/comment/7"))
        XCTAssertEqual(s.kind, .comment)
    }

    func test_unknownUser_isOffered() throws {
        let s = try XCTUnwrap(detect("https://small.example/u/bob"))
        XCTAssertEqual(s.kind, .user)
    }

    func test_unknownCommunity_isOffered_objectAtURL() throws {
        let s = try XCTUnwrap(detect("https://small.example/c/games"))
        XCTAssertEqual(s.kind, .community)
        guard case .objectAtURL = s.link else { return XCTFail("expected .objectAtURL for unknown host") }
    }

    // Negatives.
    func test_bareUnknownHost_isNil() {
        XCTAssertNil(detect("https://example.com"))
    }

    func test_plainText_isNil() {
        XCTAssertNil(detect("cats"))
        XCTAssertNil(detect("how to make pasta"))
    }

    func test_nonHttpScheme_isNil() {
        XCTAssertNil(detect("mailto:a@b.com"))
        XCTAssertNil(detect("info.ddenis.spud://internal/post?postId=1&instance=x"))
    }

    func test_unknownNonLemmyPath_isNil() {
        XCTAssertNil(detect("https://news.example/article/abc"))
    }

    func test_postWithNonNumericId_isNil() {
        XCTAssertNil(detect("https://small.example/post/notanumber"))
    }

    func test_displayURL_dropsScheme() throws {
        let s = try XCTUnwrap(detect("https://lemmy.world/post/123"))
        XCTAssertEqual(s.displayURL, "lemmy.world/post/123")
    }

    func test_whitespaceIsTrimmed() throws {
        let s = try XCTUnwrap(detect("  https://lemmy.world/post/123  "))
        XCTAssertEqual(s.kind, .post)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: FAIL — `Cannot find 'SearchURLDetector' in scope` / `SearchURLSuggestion` undefined.

- [ ] **Step 3: Write the implementation**

Create `Spud/Scenes/Search/SearchURLDetector.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// A Lemmy URL detected in the search field, ready to render as an "Open in
/// Spud" row and to route on tap.
struct SearchURLSuggestion {
    enum Kind: Hashable {
        case post, comment, community, user, instance
    }

    let kind: Kind
    let link: URL.SpudInternalLink
    let displayURL: String
}

/// Detects whether a search query is a Lemmy URL and produces a routable
/// suggestion. Pure and side-effect free; the caller supplies `isKnownInstance`
/// (Explorer directory lookup), mirroring `LemmyURLParser`.
///
/// Known-instance URLs and mentions go through `LemmyURLParser.classify`. As a
/// fallback, Lemmy-shaped paths on UNKNOWN hosts (`/post/<id>`, `/comment/<id>`,
/// `/c/<name>`, `/u/<name>`) are still offered — the path is a strong Lemmy
/// signal — and resolved federally on tap via `.objectAtURL`. A bare host with
/// no Lemmy-shaped path on an unknown instance is not offered (it cannot be
/// identified as Lemmy).
enum SearchURLDetector {
    static func detect(query: String, isKnownInstance: (String) -> Bool) -> SearchURLSuggestion? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            return nil
        }

        // Known instances + mentions: reuse the canonical classifier.
        if let link = LemmyURLParser.classify(url: url, isKnownInstance: isKnownInstance) {
            return SearchURLSuggestion(
                kind: kind(forKnownLink: link, path: url.path),
                link: link,
                displayURL: displayString(url)
            )
        }

        // Unknown-host fallback: trust Lemmy-shaped paths, resolve federally.
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        let kind: SearchURLSuggestion.Kind
        switch parts[0] {
        case "post":
            guard Int32(parts[1]) != nil else { return nil }
            kind = .post
        case "comment":
            guard Int32(parts[1]) != nil else { return nil }
            kind = .comment
        case "u":
            kind = .user
        case "c":
            kind = .community
        default:
            return nil
        }
        return SearchURLSuggestion(kind: kind, link: .objectAtURL(url: url), displayURL: displayString(url))
    }

    /// classify maps post/user/comment on known instances to `.objectAtURL`;
    /// recover the precise kind from the path so the row label is accurate.
    private static func kind(
        forKnownLink link: URL.SpudInternalLink,
        path: String
    ) -> SearchURLSuggestion.Kind {
        switch link {
        case .post: return .post
        case .person: return .user
        case .community: return .community
        case .instance: return .instance
        case .objectAtURL:
            let parts = path.split(separator: "/").map(String.init)
            switch parts.first {
            case "comment": return .comment
            case "u": return .user
            default: return .post
            }
        }
    }

    /// Host + path with the scheme dropped, for a compact secondary label.
    private static func displayString(_ url: URL) -> String {
        let host = url.host ?? ""
        return url.path.isEmpty ? host : host + url.path
    }
}
```

- [ ] **Step 4: Add the file to the project and run tests**

Run: `make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: PASS — all `SearchURLDetectorTests` green.

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/Search/SearchURLDetector.swift SpudTests/SearchURLDetectorTests.swift
git commit -m "feat: detect a Lemmy URL in the search query (SearchURLDetector)

$(printf 'Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP')"
```

---

## Task 2: SearchViewModel wiring (urlSuggestion + skip search)

**Files:**
- Modify: `Spud/Scenes/Search/SearchViewModel.swift`
- Test: `SpudTests/SearchViewModelURLSuggestionTests.swift`

**Interfaces:**
- Consumes: `SearchURLDetector.detect`, `SearchURLSuggestion` (Task 1); existing `AccountScope`, `AlertServiceType`.
- Produces: `SearchViewModel.init(accountScope:alertService:isKnownInstance:)`; `var urlSuggestion: SearchURLSuggestion?` (observable, `private(set)`).

- [ ] **Step 1: Write the failing test**

Create `SpudTests/SearchViewModelURLSuggestionTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit
import XCTest
@testable import Spud

@MainActor
final class SearchViewModelURLSuggestionTests: XCTestCase {
    private func makeViewModel(
        isKnownInstance: @escaping (String) -> Bool = { _ in false }
    ) throws -> SearchViewModel {
        let appDatabase = try AppDatabase.inMemory()
        let accountService = AccountService(appDatabase: appDatabase)
        let scope = accountService.scope(forAccountKeychainId: "test")
        return SearchViewModel(
            accountScope: scope,
            alertService: AlertService(),
            isKnownInstance: isKnownInstance
        )
    }

    func test_urlQuery_setsSuggestion_andDoesNotSearch() throws {
        let viewModel = try makeViewModel()
        viewModel.queryChanged("https://small.example/post/1")
        XCTAssertNotNil(viewModel.urlSuggestion)
        XCTAssertEqual(viewModel.urlSuggestion?.kind, .post)
        // No search was scheduled: phase stays .initial (scheduleSearch sets .loading).
        XCTAssertEqual(viewModel.phase, .initial)
    }

    func test_plainTextQuery_clearsSuggestion_andSearches() throws {
        let viewModel = try makeViewModel()
        viewModel.queryChanged("https://small.example/post/1")
        XCTAssertNotNil(viewModel.urlSuggestion)

        viewModel.queryChanged("cats")
        XCTAssertNil(viewModel.urlSuggestion)
        // A search was scheduled: scheduleSearch sets phase to .loading synchronously.
        XCTAssertEqual(viewModel.phase, .loading)
    }

    func test_emptyQuery_clearsSuggestion() throws {
        let viewModel = try makeViewModel()
        viewModel.queryChanged("https://small.example/post/1")
        viewModel.queryChanged("")
        XCTAssertNil(viewModel.urlSuggestion)
        XCTAssertEqual(viewModel.phase, .initial)
    }
}
```

> If `AccountService.init`, `AppDatabase.inMemory()`, or `AlertService()` differ from the above, check `SpudTests/HistoryViewModelTests.swift` for the exact fixtures the app target uses and match them; the behavior assertions stay the same.

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 .../build_and_test.py --scheme Spud`
Expected: FAIL — `SearchViewModel` has no `isKnownInstance:` initializer parameter / no `urlSuggestion`.

- [ ] **Step 3: Implement the view-model change**

In `Spud/Scenes/Search/SearchViewModel.swift`:

Add the observable property after `lastSearchedQuery` (around line 36):

```swift
    /// Set synchronously on each keystroke when the query is a recognized Lemmy
    /// URL. While non-nil the text search is skipped (searching a URL string is
    /// meaningless) and the VC shows an "Open in Spud" row instead.
    private(set) var urlSuggestion: SearchURLSuggestion?
```

Add the stored closure with the other `@ObservationIgnored` private members (around line 48):

```swift
    @ObservationIgnored
    private let isKnownInstance: (String) -> Bool
```

Change `init` (lines 52-58) to accept and store it:

```swift
    init(
        accountScope: AccountScope,
        alertService: AlertServiceType,
        isKnownInstance: @escaping (String) -> Bool
    ) {
        self.accountScope = accountScope
        self.alertService = alertService
        self.isKnownInstance = isKnownInstance
    }
```

Replace `queryChanged` (lines 66-79) with:

```swift
    func queryChanged(_ rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        query = trimmed

        searchTask?.cancel()

        urlSuggestion = SearchURLDetector.detect(query: trimmed, isKnownInstance: isKnownInstance)

        guard !trimmed.isEmpty else {
            phase = .initial
            results = SearchResults()
            return
        }

        // A recognized URL is offered as an "Open in Spud" row; skip the search.
        guard urlSuggestion == nil else {
            phase = .initial
            results = SearchResults()
            return
        }

        scheduleSearch(query: trimmed, debounced: true)
    }
```

- [ ] **Step 3b: Update the view controller's init to supply `isKnownInstance` (keeps the app target compiling)**

`SearchViewModel.init` now requires `isKnownInstance:`, so its only call site must change in the same commit or the app target won't build.

In `Spud/Scenes/Search/SearchViewController.swift`, add an `appDatabase` accessor after the `imageService` computed property (~line 51):

```swift
    private var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }
```

Update the `viewModel = SearchViewModel(...)` call in `init` (lines 118-121) to:

```swift
        let appDatabase = dependencies.appDatabase
        viewModel = SearchViewModel(
            accountScope: dependencies.accountService.scope(forAccountKeychainId: accountKeychainId),
            alertService: dependencies.alertService,
            isKnownInstance: { host in appDatabase.explorerInstanceSync(baseurl: host) != nil }
        )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 .../build_and_test.py --scheme Spud`
Expected: app target compiles; PASS — `SearchViewModelURLSuggestionTests` green and `SearchURLDetectorTests` still green.

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/Search/SearchViewModel.swift Spud/Scenes/Search/SearchViewController.swift SpudTests/SearchViewModelURLSuggestionTests.swift
git commit -m "feat: compute Search URL suggestion and skip text search for URLs

$(printf 'Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP')"
```

---

## Task 3: SearchOpenURLCell (+ snapshot test)

**Files:**
- Create: `Spud/Scenes/Search/Cells/SearchOpenURLCell.swift`
- Test: `SpudSnapshotTests/SearchOpenURLCellSnapshotTests.swift`

**Interfaces:**
- Consumes: `SearchURLSuggestion.Kind` (Task 1).
- Produces: `final class SearchOpenURLCell: UITableViewCell` with `static let reuseIdentifier: String` and `func configure(kind: SearchURLSuggestion.Kind, displayURL: String)`.

- [ ] **Step 1: Write the implementation**

Create `Spud/Scenes/Search/Cells/SearchOpenURLCell.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The "Open in Spud" row shown at the top of Search when the query is a
/// recognized Lemmy URL. Leading arrow glyph, a primary "Open {kind} in Spud"
/// label, the URL as a secondary label, and a disclosure chevron.
final class SearchOpenURLCell: UITableViewCell {
    static let reuseIdentifier = "SearchOpenURLCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(kind: SearchURLSuggestion.Kind, displayURL: String) {
        var content = UIListContentConfiguration.subtitleCell()
        content.image = UIImage(systemName: "arrow.up.forward.app")
        content.text = String(
            format: NSLocalizedString(
                "Open %@ in Spud",
                comment: "Search row that opens a pasted Lemmy URL; %@ is the object kind (post/community/etc.)"
            ),
            Self.kindNoun(kind)
        )
        content.secondaryText = displayURL
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.lineBreakMode = .byTruncatingMiddle
        contentConfiguration = content
    }

    private static func kindNoun(_ kind: SearchURLSuggestion.Kind) -> String {
        switch kind {
        case .post: return NSLocalizedString("post", comment: "Lemmy object kind: post")
        case .comment: return NSLocalizedString("comment", comment: "Lemmy object kind: comment")
        case .community: return NSLocalizedString("community", comment: "Lemmy object kind: community")
        case .user: return NSLocalizedString("user", comment: "Lemmy object kind: user")
        case .instance: return NSLocalizedString("instance", comment: "Lemmy object kind: instance")
        }
    }
}
```

- [ ] **Step 2: Write the snapshot test**

Create `SpudSnapshotTests/SearchOpenURLCellSnapshotTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Snapshot of the "Open in Spud" search row across kinds, in light and dark.
@MainActor
final class SearchOpenURLCellSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)
    private let width: CGFloat = 390

    func test_post() {
        let cell = SearchOpenURLCell(style: .subtitle, reuseIdentifier: nil)
        cell.configure(kind: .post, displayURL: "lemmy.world/post/123456")
        assertCell(cell)
    }

    func test_community() {
        let cell = SearchOpenURLCell(style: .subtitle, reuseIdentifier: nil)
        cell.configure(kind: .community, displayURL: "lemmy.world/c/asklemmy")
        assertCell(cell)
    }

    func test_instance() {
        let cell = SearchOpenURLCell(style: .subtitle, reuseIdentifier: nil)
        cell.configure(kind: .instance, displayURL: "lemmy.world")
        assertCell(cell)
    }

    private func assertCell(
        _ cell: UITableViewCell,
        testName: String = #function,
        line: UInt = #line
    ) {
        cell.tintColor = lemmyTeal
        cell.contentView.tintColor = lemmyTeal
        cell.contentView.backgroundColor = .systemBackground
        for style in [UIUserInterfaceStyle.light, .dark] {
            cell.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
            cell.layoutIfNeeded()
            let height = cell.contentView.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
            container.backgroundColor = .systemBackground
            container.tintColor = lemmyTeal
            cell.frame = container.bounds
            container.addSubview(cell)
            container.layoutIfNeeded()
            assertSnapshot(
                matching: container,
                as: .image(
                    size: CGSize(width: width, height: height),
                    traits: UITraitCollection(traitsFrom: [
                        UITraitCollection(userInterfaceStyle: style),
                        UITraitCollection(displayScale: 2),
                    ])
                ),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }
}
```

- [ ] **Step 3: Add files, record refs, verify**

Run: `make project`
Run (records missing refs, fails first time):
`xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -only-testing:SpudSnapshotTests/SearchOpenURLCellSnapshotTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Then rerun the same command.
Expected: first run FAILS ("No reference … recorded"); second run PASSES. Inspect the recorded PNGs look like an "Open … in Spud" row.

- [ ] **Step 4: Commit (with git-annex note)**

The new snapshot PNGs live under `SpudSnapshotTests/__Snapshots__/` (git-annex tracked). Do not `git annex restage` between record and verify.

```bash
git add Spud/Scenes/Search/Cells/SearchOpenURLCell.swift \
        SpudSnapshotTests/SearchOpenURLCellSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/SearchOpenURLCellSnapshotTests
git commit -m "feat: add SearchOpenURLCell with snapshots

$(printf 'Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP')"
```

---

## Task 4: SearchViewController integration (section + render + tap routing)

**Files:**
- Modify: `Spud/Scenes/Search/SearchViewController.swift`

**Interfaces:**
- Consumes: `SearchURLSuggestion` + `.Kind` (Task 1); `viewModel.urlSuggestion`, the new `SearchViewModel.init(...:isKnownInstance:)` (Task 2); `SearchOpenURLCell` (Task 3); existing `CommunityOrLoadingViewController`, `PersonOrLoadingViewController`, `InstanceExploreViewController`, `MainWindow.display(...)`, `appDatabase.explorerInstanceSync(baseurl:)`, `viewModel.accountScope.lemmyService.resolveObject(query:)`.

> The `appDatabase` accessor and the `SearchViewModel(...isKnownInstance:)` call site were already added in Task 2 Step 3b; this task reuses that `appDatabase` accessor in `openInstance`.

- [ ] **Step 3b: Add the section, item case, and cell registration**

Register the cell in the `tableView` lazy initializer (after the four existing `register(...)` calls, ~line 82):

```swift
        tableView.register(SearchOpenURLCell.self, forCellReuseIdentifier: SearchOpenURLCell.reuseIdentifier)
```

Extend `Section` (lines 61-63) and `Item` (lines 65-70):

```swift
    private enum Section: Hashable {
        case openURL
        case results
    }

    private enum Item: Hashable {
        case openURL(kind: SearchURLSuggestion.Kind, displayURL: String)
        case post(SearchPostResult)
        case community(SearchCommunityResult)
        case user(SearchUserResult)
        case comment(SearchCommentResult)
    }
```

Add the cell to `makeDataSource`'s switch (in the closure, before `case let .post`):

```swift
            case let .openURL(kind, displayURL):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: SearchOpenURLCell.reuseIdentifier,
                    for: indexPath
                ) as! SearchOpenURLCell
                cell.configure(kind: kind, displayURL: displayURL)
                return cell
```

- [ ] **Step 3c: Observe the suggestion and render the section**

Add `viewModel.urlSuggestion` to the observed state in `startObservations` (extend the `resultsObservationTask` closure tuple, ~line 186):

```swift
            for await _ in ObservationStream.values(of: { (viewModel.urlSuggestion?.displayURL, viewModel.results.posts, viewModel.results.communities, viewModel.results.users, viewModel.results.comments, viewModel.scope) }) {
```

Replace `render()` (lines 195-215) so a suggestion takes precedence over the phase-driven states:

```swift
    private func render() {
        if let suggestion = viewModel.urlSuggestion {
            loadingIndicator.stopAnimating()
            updateContentUnavailable(.none)
            applySnapshot(suggestion: suggestion, items: [])
            return
        }

        switch viewModel.phase {
        case .initial:
            loadingIndicator.stopAnimating()
            applySnapshot(suggestion: nil, items: [])
            updateContentUnavailable(.initial)
        case .loading:
            loadingIndicator.startAnimating()
            updateContentUnavailable(.none)
        case .loaded:
            loadingIndicator.stopAnimating()
            applyResultsSnapshot()
            updateContentUnavailable(
                viewModel.results.isEmpty(for: viewModel.scope) ? .noResults : .none
            )
        case .error:
            loadingIndicator.stopAnimating()
            applySnapshot(suggestion: nil, items: [])
            updateContentUnavailable(.error)
        }
    }
```

Update `applyResultsSnapshot` (lines 217-230) to pass `suggestion: nil`, and replace `applySnapshot` (lines 232-237) with a two-section version:

```swift
    private func applyResultsSnapshot() {
        let items: [Item]
        switch viewModel.scope {
        case .posts:
            items = viewModel.results.posts.map(Item.post)
        case .communities:
            items = viewModel.results.communities.map(Item.community)
        case .users:
            items = viewModel.results.users.map(Item.user)
        case .comments:
            items = viewModel.results.comments.map(Item.comment)
        }
        applySnapshot(suggestion: nil, items: items)
    }

    private func applySnapshot(suggestion: SearchURLSuggestion?, items: [Item]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if let suggestion {
            snapshot.appendSections([.openURL])
            snapshot.appendItems(
                [.openURL(kind: suggestion.kind, displayURL: suggestion.displayURL)],
                toSection: .openURL
            )
        }
        snapshot.appendSections([.results])
        snapshot.appendItems(items, toSection: .results)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
```

- [ ] **Step 3d: Route the tap**

In `tableView(_:didSelectRowAt:)` (lines 360-391), add the `.openURL` case to the switch (before `case let .post`):

```swift
        case .openURL:
            guard let suggestion = viewModel.urlSuggestion,
                  let window = view.window as? MainWindow else { return }
            openSuggestion(suggestion.link, in: window)
```

Add the routing helpers inside the `SearchViewController` class (in the `// MARK: Actions` section, after `setSubscribed`):

```swift
    // MARK: Open-URL routing

    /// Routes a detected Lemmy URL. Mirrors PostDetailViewController's local link
    /// handling: communities/instances push directly; canonical URLs resolve
    /// federally first.
    private func openSuggestion(_ link: URL.SpudInternalLink, in window: MainWindow) {
        switch link {
        case let .community(name, instance):
            pushCommunity(name: name, instance: instance)
        case let .instance(instance):
            openInstance(instance)
        case let .objectAtURL(url):
            Task { @MainActor [weak self] in await self?.resolveAndOpen(url, in: window) }
        case let .post(postId, _):
            window.display(serverPostId: postId, accountKeychainId: accountKeychainId)
        case let .person(personId, instance):
            pushPerson(personId: personId, instance: instance)
        }
    }

    private func pushCommunity(name: String, instance: InstanceActorId) {
        let vc = CommunityOrLoadingViewController(
            communityName: name,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func pushPerson(personId: Components.Schemas.PersonID, instance: InstanceActorId) {
        let vc = PersonOrLoadingViewController(
            personId: personId,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openInstance(_ instance: InstanceActorId) {
        guard let record = appDatabase.explorerInstanceSync(baseurl: instance.host) else {
            Haptics.warning()
            return
        }
        let vc = InstanceExploreViewController(
            record: record,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    /// Resolves a canonical Lemmy URL under the current account, then routes by
    /// type. Comments open the parent post; unresolved links warn.
    private func resolveAndOpen(_ canonicalURL: URL, in window: MainWindow) async {
        let lemmyService = viewModel.accountScope.lemmyService
        let resolved = try? await lemmyService.resolveObject(query: canonicalURL.absoluteString)
        switch resolved {
        case let .post(postId, _):
            window.display(serverPostId: postId, accountKeychainId: accountKeychainId)
        case let .community(name, instance):
            pushCommunity(name: name, instance: instance)
        case let .person(personId, instance):
            pushPerson(personId: personId, instance: instance)
        case let .comment(postId, _, _):
            window.display(serverPostId: postId, accountKeychainId: accountKeychainId)
        case .unresolved, .none:
            Haptics.warning()
        }
    }
```

> If `pushPerson`'s `personId` type does not compile, match the type used by the existing `.user` result case / `PersonOrLoadingViewController` init (it is `Components.Schemas.PersonID`, as in `PostDetailViewController.pushPerson`). `ResolvedLemmyObject` case shapes are as used in `AppCoordinator.resolveAndDisplay` (`.post(postId, instance)`, `.community(name, instance)`, `.person(personId, instance)`, `.comment(postId, _, _)`, `.unresolved`).

- [ ] **Step 4: Regenerate, build, and run the suite**

Run: `make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: app target compiles; all unit tests (Tasks 1-2) PASS. Then run the SpudWidgetExtension build to confirm the shared section didn't break it:
`python3 .../build_and_test.py --scheme SpudWidgetExtension` → builds clean.

- [ ] **Step 5: Manual verification (simulator)**

Boot the iPhone 17 Pro sim, run the app, open Search, paste each of: `https://lemmy.world/post/1`, `https://lemmy.world/c/asklemmy`, `https://lemmy.world/u/someone`, `https://lemmy.world`, and a non-Lemmy URL. Expected: the first four show an "Open … in Spud" row that navigates on tap (federated ones resolve then navigate); the non-Lemmy URL shows no row and normal (empty) search. Paste a URL then edit to plain text: row disappears, normal search resumes.

- [ ] **Step 6: Commit**

```bash
git add Spud/Scenes/Search/SearchViewController.swift
git commit -m "feat: show an Open-in-Spud row in Search for pasted Lemmy URLs

$(printf 'Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP')"
```

---

## Notes / known follow-ups

- Routing the suggestion duplicates a little of `PostDetailViewController`'s and `AppCoordinator`'s resolve-and-route logic (three copies now exist). Extracting a shared `LemmyLinkRouter` is a reasonable future cleanup but is out of scope here (it would touch two working call sites).
- `AppCoordinator.open` still no-ops on `.instance`; this feature routes instances locally in Search instead. If instance links are later wanted from body text via the coordinator, add a `MainWindow.display(instance:accountKeychainId:)` and route it there.
