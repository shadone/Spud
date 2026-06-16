# Markdown Renderer — Phase 5 (Snapshot Breadth + Edge Cases) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Lock in the design spec's edge-case redlines with tests — raw HTML as literal text, malformed/orphaned footnotes, long unbroken URLs, deeply nested quotes, wide tables, and the mention/link/community visual distinction — adding unit + snapshot coverage and fixing any genuinely-broken behavior that's cheap, while documenting the rest as known limitations.

**Architecture:** Pure additive testing in `SpudMarkdownKit` (no integration). New unit-test file for parser/lexer edge cases; new snapshot-test class for the visual edge redlines; one potential targeted fix (long-URL wrapping) gated on observed behavior. Mirrors the established test patterns (`BlockParserTests`/`MarkdownParserTests`/`InlineLexerTests` for unit; `MarkdownStructuralSnapshotTests` for snapshots).

**Tech Stack:** Swift 6, XCTest, swift-snapshot-testing, XcodeGen. Worktree: `/Users/denis/dev/info.ddenis/Spud/Spud-markdown-integration` (branch `markdown-renderer-integration`, off main).

---

## Scope

Phase 5 = edge-case + breadth COVERAGE for `SpudMarkdownKit`, per the spec's "Edge cases (from the design's redlines)" and "Testing" sections (`docs/superpowers/specs/2026-06-15-markdown-renderer-design.md`). **Out of scope:** integration into Spud (Phase 6); the carried-forward known limitations that are intentional deferrals (rounded chips, footnote ref↔def smooth scroll, fence-aware preprocessors, spoiler-in-list, H6 inline formatting, depth-scaled quote styling) — these are documented, not fixed here. Most redlines are already implemented; this phase proves them and catches regressions.

## Reference — current state (from the Phase-5 exploration)

Already HANDLED + TESTED: inline/fenced code wrapping, wide-table minWidth+scroll, empty-spoiler fallback, image loading/failed/loaded states, unknown emoji literal, nested-quote parsing.
HANDLED but UNTESTED (this phase adds tests): raw HTML as literal text, malformed footnotes (orphaned ref / dead definition), long-URL detection, deeply-nested-quote rendering, mention-vs-link-vs-community visual distinction, pathologically wide table.
POSSIBLE real gap (gated fix in Task 2): long unbroken URL wrapping in prose (spec wants "break-all"; current relies on TextKit 2 default — verify by snapshot, fix only if it actually overflows).

## Conventions (every task)

BSD-2-Clause header on every new file:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//
```

**MUST `make project` before every build/test** (XcodeGen; the `.xcodeproj` is gitignored/generated). Canonical commands (run from the worktree root):
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-markdown-integration
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/<CLASS> test 2>&1 | tail -30
```
(iPhone 17 or 17 Pro — whichever is installed; reuse a booted sim if `xcrun simctl list devices | grep -i Booted` shows one.) Format before commit: `mint run swiftformat <dirs>`. `git status -uall`; stage explicit paths (never `git add -A`); do NOT touch `.remember/remember.md`. Snapshot first-run records refs + FAILS; re-run verifies — the new snapshot PNGs under `SpudMarkdownKitSnapshotTests/__Snapshots__/` are NORMAL committed files for this framework (not git-annex). No emojis in code/commits.

---

## Task 1: Edge-case parser/lexer unit tests

**Files:** Create `SpudMarkdownKitTests/EdgeCaseParsingTests.swift`

Lock current parser/lexer behavior for the untested edge redlines. These are characterization tests (assert what the code does today, which is the spec-correct behavior) — they catch regressions. Read `SpudMarkdownKitTests/BlockParserTests.swift`, `MarkdownParserTests.swift`, and `InlineLexerTests.swift` first to mirror their exact style (imports, `@testable import SpudMarkdownKit`, how they pattern-match `[MarkdownBlock]` / `[MarkdownInline]`, helper accessors). Also read `SpudMarkdownKit/Model/MarkdownBlock.swift` + `MarkdownInline.swift` for the exact case shapes, and `SpudMarkdownKit/Parsing/{MarkdownParser,BlockParser,FootnoteExtractor,InlineLexer}.swift` for the actual behavior so the assertions match reality.

- [ ] **Step 1: Write the tests** in `SpudMarkdownKitTests/EdgeCaseParsingTests.swift`. Cover exactly these cases (use `MarkdownParser.parse(_:)` as the entry point; mirror the assertion helpers used in the sibling test files):

  1. **Raw HTML renders as literal text, never parsed.** Input `"a <b>x</b> c"` → the paragraph's inlines must contain the literal `<b>` / `</b>` (or the run text `a <b>x</b> c`) as `.text`, NOT a `.strong`/emphasis. And a block-level `"<div>raw</div>"` must parse without crashing (assert `MarkdownParser.parse("<div>raw</div>")` returns — HTMLBlock is dropped or kept literal; assert whichever the code actually does, after reading `BlockParser.swift`). Assert no link/emphasis is synthesized from the tags.

  2. **Orphaned footnote reference (ref with no definition).** Input `"See the note.[^x]"` (no `[^x]:` definition) → assert the result contains a paragraph whose inlines include a `.footnoteReference("x")` (the ref is preserved), AND there is NO `.footnotes(...)` block (definitions are empty, so the section is not appended). Confirm against `MarkdownParser.swift` (the `!definitions.isEmpty` gate) + `InlineLexer.swift`.

  3. **Dead footnote definition (definition with no in-body reference).** Input `"Body text.\n\n[^x]: an unused note."` → assert there IS a `.footnotes` block containing a footnote whose label is `"x"` and whose content renders `"an unused note."` (current behavior: definitions are appended regardless of whether a ref exists). This documents the current "show all definitions" behavior.

  4. **Long unbroken URL is detected as a single autolink.** Input a bare URL with no spaces ~90 chars long, e.g. `"https://example.com/a/very/long/path/segment/that/keeps/going/and/going/until/it/is/long.html"` → assert the paragraph's inlines contain exactly one `.link` whose URL round-trips to that string (detection works; wrapping is Task 2). Mirror `InlineLexerTests` autolink assertions.

  5. **Unknown emoji adjacent to known emoji** (extends existing coverage): input `":notreal: :penguin:"` → assert the `:notreal:` stays literal `.text` and `:penguin:` becomes the emoji inline (mirror `InlineLexerTests.test_unknownShortcodeDoesNotLeakIntoNextEmoji`). If an equivalent test already exists, SKIP this case to avoid duplication and note it.

- [ ] **Step 2: Run the tests** (`-only-testing:SpudMarkdownKitTests/EdgeCaseParsingTests`). They are characterization tests, so they should PASS once written to match actual behavior. If any case reveals behavior that is clearly WRONG vs the spec (e.g., raw HTML being parsed into emphasis, or an orphaned ref crashing), STOP and report it as DONE_WITH_CONCERNS with the specifics — do not silently "fix" by weakening the assertion. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKitTests
git add SpudMarkdownKitTests
git commit -m "test(markdown): edge-case parser coverage (raw HTML, footnotes, long URL)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Long-URL prose wrapping (observe, then fix only if it overflows)

**Files:** Create `SpudMarkdownKitSnapshotTests/MarkdownLongURLSnapshotTests.swift`; possibly Modify `SpudMarkdownKit/Rendering/MarkdownBlockRenderer.swift` or `ProseBlockView.swift` (only if Step 2 shows overflow)

The spec's redline: "prose URLs use break-all to wrap inside the column." Verify the new renderer actually does this; fix minimally if not.

- [ ] **Step 1: Add a snapshot test** at `SpudMarkdownKitSnapshotTests/MarkdownLongURLSnapshotTests.swift`, mirroring the `render(kind:width:)` helper pattern in `SpudMarkdownKitSnapshotTests/MarkdownProseSnapshotTests.swift` (copy that helper verbatim — same container/width/`systemLayoutSizeFitting` framing). Sample (a paragraph with a long unbroken URL plus surrounding prose so wrapping is visible):
```
Check out this resource before continuing:

https://example.com/a/very/long/path/segment/that/keeps/going/and/going/until/it/overflows/the/column.html

That link has the full details.
```
Add two tests: `test_longURLPost` and `test_longURLComment` (post and comment context, light trait is enough for a layout check — `assertSnapshot(of: render(kind: .post), as: .image(traits: UITraitCollection(userInterfaceStyle: .light)))`).

- [ ] **Step 2: Record + EYEBALL** the two PNGs (first run records + fails). Inspect `SpudMarkdownKitSnapshotTests/__Snapshots__/MarkdownLongURLSnapshotTests/*.png`:
  - If the long URL **wraps within the column** (breaks across lines, no horizontal overflow/clipping past the 360pt-width container): behavior is correct — re-run to verify green, then go to Step 4 (no code change).
  - If the long URL **overflows** the column (extends past the right edge / is clipped / forces the view wider): apply the minimal fix in Step 3.
  Report which case you observed (paste the dimensions / describe the render).

- [ ] **Step 3 (ONLY if overflow observed): Minimal fix.** In `MarkdownBlockRenderer.prose(_:)` (the helper that builds the paragraph style for prose `ProseBlockView`s — it currently sets `paragraph.lineHeightMultiple`), set the line-break behavior so an over-long token breaks rather than overflowing:
```swift
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineBreakStrategy = []
```
If `.byWordWrapping` + clearing `lineBreakStrategy` does not break the unbreakable URL token (re-record + eyeball), instead set `paragraph.lineBreakMode = .byCharWrapping` — accept that this is the spec's "break-all" intent, and re-record the affected prose/structural snapshots ONLY if they legitimately changed (delete the stale PNGs, re-run to record, eyeball that normal prose still reads correctly with no mid-word breaks on short words, re-run to verify). Document in the commit which approach was needed. Keep the change confined to `prose(_:)` so only paragraph-ish blocks are affected.

- [ ] **Step 4: Verify** the long-URL snapshots are green:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-markdown-integration
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitSnapshotTests/MarkdownLongURLSnapshotTests test 2>&1 | tail -12
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit** (include any re-recorded PNGs if Step 3 changed wrapping):
```bash
make project && mint run swiftformat SpudMarkdownKit SpudMarkdownKitSnapshotTests
git add SpudMarkdownKit SpudMarkdownKitSnapshotTests
git commit -m "test(markdown): long-URL prose wrapping snapshot

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
(If Step 3 applied a fix, use subject `fix(markdown): wrap long unbreakable URLs in prose (+ snapshot)`.)

---

## Task 3: Edge-case snapshot suite + final verification

**Files:** Create `SpudMarkdownKitSnapshotTests/MarkdownEdgeCaseSnapshotTests.swift`

A combined "edges" sample that visually proves the remaining redlines, in post/comment × light/dark.

- [ ] **Step 1: Write the snapshot test** at `SpudMarkdownKitSnapshotTests/MarkdownEdgeCaseSnapshotTests.swift`, mirroring the `render(kind:width:)` helper + 4-test structure of `MarkdownStructuralSnapshotTests.swift` (copy that helper verbatim). Use this sample (exercises 3-level nested quotes, a wide 6-column table, a line with a link + @mention + !community for visual distinction, raw HTML as literal text, an unknown emoji, and an empty-title spoiler):
```
Link to [the docs](https://example.com), mention @ada@lemmy.world, community !rust@lemmy.world.

Literal markup stays text: a <b>not bold</b> tag and :notarealemoji: shortcode.

> level one
> > level two
> > > level three

| Col A | Col B | Col C | Col D | Col E | Col F |
|:--|--:|:-:|:--|--:|:--|
| alpha | beta | gamma | delta | epsilon | zeta |
| 1 | 2 | 3 | 4 | 5 | 6 |

::: spoiler
hidden body with no title
:::
```
Add 4 tests: `test_edgesPostLight`, `test_edgesPostDark`, `test_edgesCommentLight`, `test_edgesCommentDark` (same `assertSnapshot(of: render(kind:), as: .image(traits:))` structure as `MarkdownStructuralSnapshotTests`).

- [ ] **Step 2: Record + EYEBALL** the 4 PNGs (first run records + fails). Inspect `SpudMarkdownKitSnapshotTests/__Snapshots__/MarkdownEdgeCaseSnapshotTests/*.png` and confirm:
  - link is underlined teal text; @mention and !community are tinted chips (visually distinct from the plain link);
  - `<b>not bold</b>` and `:notarealemoji:` render as literal text (not bold, not an emoji);
  - the quote nests three levels with increasing inset/bar;
  - the 6-column table is horizontally scrollable (in comment context it keeps its min width and scrolls under the rail);
  - the spoiler shows the muted italic "Spoiler" fallback (empty title), collapsed.
  Re-run to verify green. Report what you see.

- [ ] **Step 3: FINAL VERIFICATION** — full SpudMarkdownKit target + Spud app build:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-markdown-integration
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test 2>&1 | tail -20
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -12
```
Expected: SpudMarkdownKit `** TEST SUCCEEDED **` (all prior + the new edge unit tests + long-URL + 4 edge snapshots) and Spud app `** BUILD SUCCEEDED **`. Report the new total test count.

- [ ] **Step 4: Commit** (edge snapshot test + recorded PNGs):
```bash
make project && mint run swiftformat SpudMarkdownKitSnapshotTests
git add SpudMarkdownKitSnapshotTests
git commit -m "test(markdown): edge-case snapshot suite (nesting, wide table, chips, literal markup)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria for Phase 5

- Untested edge redlines now have unit + snapshot coverage: raw HTML literal, malformed footnotes (orphaned ref / dead definition), long URL, deeply nested quotes, wide table, mention/link/community distinction, empty-title spoiler.
- Long-URL prose wrapping is verified (and fixed if it was overflowing), with a snapshot locking it.
- Full SpudMarkdownKit target green; Spud app builds. Any genuinely-broken-but-out-of-scope behavior surfaced is documented, not silently patched.

## Known limitations carried forward (unchanged)

Rounded mention/community chips; footnote ref↔def smooth scroll; fence-aware preprocessors; spoiler-in-list extraction; H6 inline formatting; depth-scaled quote styling; the Phase-4 integration follow-ups (image `onContentSizeChange`, loaded-image VoiceOver element, media-tap haptics — all handled in Phase 6).

## Next

- **Phase 6** — integration into Spud (replace `BodyTextView`/`LinkLabel` at post + comment body call sites; wire the delegate to real navigation/media/haptics; preserve off-main parse + cache; resolve the `spud-markdown://` vs `info.ddenis.spud://` scheme mismatch). Needs a design checkpoint first.
