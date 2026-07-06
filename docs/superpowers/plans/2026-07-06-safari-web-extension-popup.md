# Safari Web Extension "Open in Spud" popup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Hello-World Safari Web Extension toolbar popup with a real one: on a known Lemmy instance (any page) a single "Open in Spud" button, and on any other page an inactive "Not a Lemmy instance" message.

**Architecture:** The content script already runs only on the bundled allowlist of Lemmy hosts, so its presence in a tab means "known instance." The popup probes the active tab's content script over `browser.runtime` messaging; a reply → show the enabled button, silence → show the inactive message. Tapping the button asks the content script to navigate the page to `info.ddenis.spud://internal/resolve?url=<page>` — the exact hand-off the in-page banner already performs.

**Tech Stack:** Manifest V3 Safari Web Extension (plain JS/HTML/CSS in `OpenInAppExtension/Resources/`); node's built-in `assert` for pure-helper unit tests (CommonJS, run with `node <file>`).

## Global Constraints

- **iOS Safari only.** Spud is an iOS-only app; do not add macOS-specific behavior.
- **Known instances only.** "Known" = the content script is injected (the manifest restricts `content_scripts.matches` to the bundled allowlist). Do NOT duplicate the ~500-host list anywhere; use content-script presence as the single source of truth. Non-allowlisted hosts are intentionally not supported.
- **Reuse the existing hand-off.** The open action must reuse `lemmyDeepLink(href)` from `content.js` and the `info.ddenis.spud://internal/resolve?url=<page>` deep link the banner already uses. Do not introduce a second deep-link form.
- **`activeTab` permission only.** Add exactly `"activeTab"` to `manifest.json` `permissions`; request no broad host permissions.
- **No app-side (Swift) change.** The `.unresolved` deep-link path (instance-home / `/search`) plays a warning haptic with no visible UI today; improving that is an explicit non-goal here (it also affects the banner).
- **`popup.js` must be a classic script** (not an ES module) — like `content.js` — so it both loads in Safari and is `require()`-able by the node test. Use the `if (typeof module !== "undefined" && module.exports)` export guard and a `typeof window !== "undefined"` browser guard.
- **No emojis** in code, comments, docs, or commit messages. Conventional commit subjects (`feat:`, `test:`, `docs:`). Small, focused commits.
- Node test files live in `OpenInAppExtension/Resources/__tests__/` (cjs), run with `node OpenInAppExtension/Resources/__tests__/<file>.test.cjs`, matching the existing `content.test.cjs`.

---

## File Structure

- `OpenInAppExtension/Resources/content.js` — **modify.** Add a pure `handlePopupMessage(message, deps)` and register a `browser.runtime.onMessage` listener. Existing banner logic and the `isLemmyContentPath`/`lemmyDeepLink` helpers are untouched; `handlePopupMessage` is added to the CommonJS export.
- `OpenInAppExtension/Resources/__tests__/content.test.cjs` — **modify.** Append `handlePopupMessage` assertions.
- `OpenInAppExtension/Resources/popup.js` — **replace** the `console.log` stub. Pure `popupStateFromProbe(result)` helper + the popup wiring (probe active tab, render state, wire the Open button). Classic script with export + browser guards.
- `OpenInAppExtension/Resources/__tests__/popup.test.cjs` — **create.** Unit test for `popupStateFromProbe`.
- `OpenInAppExtension/Resources/popup.html` — **replace** the Hello-World markup with the two-state markup; load `popup.js` as a classic script.
- `OpenInAppExtension/Resources/popup.css` — **replace** with popup styling (button, inactive message, error line, dark mode).
- `OpenInAppExtension/Resources/_locales/en/messages.json` — **modify.** Add `popup_open`, `popup_not_lemmy`, `popup_error`.
- `OpenInAppExtension/Resources/manifest.json` — **modify.** `permissions: []` → `permissions: ["activeTab"]`.
- `OpenInAppExtension/Resources/background.js` — **replace** the dead `hello`/`goodbye` template stub with an empty (comment-only) service worker.
- `docs/features/share-extension.md`, `docs/features/README.md` — **modify.** Reconcile status + add the popup scenario.

No new bundled Swift/resources and no `project.yml` change: these are edits to files the extension already ships, plus a test file alongside the existing `content.test.cjs` (the `__tests__` convention is pre-existing). No `make project` needed.

---

### Task 1: Content-script responds to popup messages

**Files:**
- Modify: `OpenInAppExtension/Resources/content.js`
- Test: `OpenInAppExtension/Resources/__tests__/content.test.cjs`

**Interfaces:**
- Consumes: existing `lemmyDeepLink(href)` in `content.js`.
- Produces: `handlePopupMessage(message, deps)` where `deps = { getHref: () => string, navigate: (url: string) => void }`. Returns `{ known: true }` for `{type:"spud-probe"}`; calls `deps.navigate(lemmyDeepLink(deps.getHref()))` and returns `{ ok: true }` for `{type:"spud-open"}`; returns `undefined` for any other message. Exported from `content.js`'s `module.exports`.

- [ ] **Step 1: Write the failing test.** Append to `OpenInAppExtension/Resources/__tests__/content.test.cjs`, before the final `console.log` line:

```javascript
// Popup message handling: probe reports "known", open navigates to the deep link.
const { handlePopupMessage } = require("../content.js");

assert.deepStrictEqual(
    handlePopupMessage({ type: "spud-probe" }, { getHref: () => "https://lemmy.world/", navigate: () => {} }),
    { known: true }
);

let navigatedTo = null;
const openResponse = handlePopupMessage(
    { type: "spud-open" },
    { getHref: () => "https://lemmy.world/post/123", navigate: (url) => { navigatedTo = url; } }
);
assert.deepStrictEqual(openResponse, { ok: true });
assert.strictEqual(
    navigatedTo,
    "info.ddenis.spud://internal/resolve?url=" + encodeURIComponent("https://lemmy.world/post/123")
);

assert.strictEqual(handlePopupMessage({ type: "other" }, { getHref: () => "", navigate: () => {} }), undefined);
assert.strictEqual(handlePopupMessage(null, { getHref: () => "", navigate: () => {} }), undefined);
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `node OpenInAppExtension/Resources/__tests__/content.test.cjs`
Expected: FAIL — `TypeError: handlePopupMessage is not a function` (it isn't exported yet).

- [ ] **Step 3: Add the pure handler to `content.js`.** Insert immediately after the `lemmyDeepLink` function (after its closing `}`, before `localized`):

```javascript
// Maps a message from the toolbar popup to a response, performing the
// navigation for an "open" request. Pure except for the injected `deps`:
//   deps.getHref()      -> the current page URL
//   deps.navigate(url)  -> perform the navigation (page -> deep link)
// Returns the object to send back to the popup, or undefined for a message
// this listener does not handle. Reuses lemmyDeepLink so the popup and the
// in-page banner share one deep-link form.
function handlePopupMessage(message, deps) {
    if (!message || typeof message.type !== "string") {
        return undefined;
    }
    if (message.type === "spud-probe") {
        // The content script only runs on allowlisted Lemmy hosts, so a reply
        // at all is the "known instance" signal the popup is looking for.
        return { known: true };
    }
    if (message.type === "spud-open") {
        deps.navigate(lemmyDeepLink(deps.getHref()));
        return { ok: true };
    }
    return undefined;
}
```

- [ ] **Step 4: Export the handler.** Change the export line at the bottom of `content.js` from:

```javascript
    module.exports = { isLemmyContentPath, lemmyDeepLink };
```

to:

```javascript
    module.exports = { isLemmyContentPath, lemmyDeepLink, handlePopupMessage };
```

- [ ] **Step 5: Run the test to verify it passes.**

Run: `node OpenInAppExtension/Resources/__tests__/content.test.cjs`
Expected: PASS — prints `content.js helper tests passed`.

- [ ] **Step 6: Register the runtime listener (browser wiring).** Inside the existing browser-only block in `content.js` (the `if (typeof window !== "undefined" && typeof document !== "undefined") { ... }` block), after the `isLemmyContentPath(...)` banner call, add:

```javascript
    if (typeof browser !== "undefined" && browser.runtime && browser.runtime.onMessage) {
        browser.runtime.onMessage.addListener(function (message) {
            const response = handlePopupMessage(message, {
                getHref: function () { return window.location.href; },
                navigate: function (url) { window.location.href = url; },
            });
            // Returning a Promise sends the response; false means "not handled"
            // so other listeners (and the sender's catch) behave correctly.
            return response === undefined ? false : Promise.resolve(response);
        });
    }
```

- [ ] **Step 7: Re-run the test to confirm the wiring did not break the helpers.**

Run: `node OpenInAppExtension/Resources/__tests__/content.test.cjs`
Expected: PASS — `content.js helper tests passed` (the browser block is guarded and inert under node).

- [ ] **Step 8: Commit.**

```bash
git add OpenInAppExtension/Resources/content.js OpenInAppExtension/Resources/__tests__/content.test.cjs
git commit -m "feat: content script answers Open-in-Spud popup probe/open messages"
```

---

### Task 2: Toolbar popup UI and wiring

**Files:**
- Modify: `OpenInAppExtension/Resources/popup.js` (replace stub), `OpenInAppExtension/Resources/popup.html` (replace), `OpenInAppExtension/Resources/popup.css` (replace), `OpenInAppExtension/Resources/manifest.json`, `OpenInAppExtension/Resources/_locales/en/messages.json`, `OpenInAppExtension/Resources/background.js` (replace stub)
- Test: `OpenInAppExtension/Resources/__tests__/popup.test.cjs` (create)

**Interfaces:**
- Consumes: the content-script messages from Task 1 (`{type:"spud-probe"}` → `{known:true}`; `{type:"spud-open"}` → navigates).
- Produces: `popupStateFromProbe(result)` → `"known"` when `result && result.known`, else `"unknown"`. Exported from `popup.js`.

- [ ] **Step 1: Write the failing test.** Create `OpenInAppExtension/Resources/__tests__/popup.test.cjs`:

```javascript
"use strict";

// Pure-helper tests for the "Open in Spud" toolbar popup. Run with:
//   node OpenInAppExtension/Resources/__tests__/popup.test.cjs

const assert = require("node:assert");
const { popupStateFromProbe } = require("../popup.js");

// A truthy { known: true } reply means the active tab is a known Lemmy instance.
assert.strictEqual(popupStateFromProbe({ known: true }), "known");

// No content script / no reply -> not a known instance.
assert.strictEqual(popupStateFromProbe(null), "unknown");
assert.strictEqual(popupStateFromProbe(undefined), "unknown");
assert.strictEqual(popupStateFromProbe({}), "unknown");
assert.strictEqual(popupStateFromProbe({ known: false }), "unknown");

console.log("popup.js helper tests passed");
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `node OpenInAppExtension/Resources/__tests__/popup.test.cjs`
Expected: FAIL — `Cannot find module '../popup.js'` is not the case (the stub exists), so it fails with `popupStateFromProbe is not a function` (the stub exports nothing).

- [ ] **Step 3: Replace `popup.js` with the real implementation.** Overwrite `OpenInAppExtension/Resources/popup.js` entirely:

```javascript
"use strict";

// Toolbar popup for the "Open in Spud" Safari Web Extension.
//
// On a known Lemmy instance (detected by the content script's presence in the
// tab) it offers a single "Open in Spud" button that hands the current page to
// the app via the same resolve deep link the in-page banner uses. On any other
// page it shows an inactive "Not a Lemmy instance" message. The popup never
// duplicates the host allowlist: the content script is the source of truth.
//
// Classic script (not a module) so it both loads in Safari and is require()-able
// by the node test; the browser-only wiring is guarded.

// Pure: decide the popup state from the content script's probe reply. A truthy
// { known: true } reply means a known Lemmy instance; null/undefined (no content
// script) means it is not.
function popupStateFromProbe(result) {
    return result && result.known ? "known" : "unknown";
}

// Localized string with an English fallback when i18n is unavailable. Mirrors
// content.js's localized() (the two script contexts cannot share a module).
function localized(key, fallback) {
    try {
        const message = globalThis.browser && globalThis.browser.i18n
            ? globalThis.browser.i18n.getMessage(key)
            : "";
        return message || fallback;
    } catch (e) {
        return fallback;
    }
}

// Queries the active tab and probes its content script. Resolves to the tab and
// the resulting popup state. A tab with no content script (unknown host, or a
// non-injectable page) rejects the sendMessage, which we treat as "unknown".
async function probeActiveTab() {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    const tab = tabs[0];
    if (!tab) {
        return { tab: null, state: "unknown" };
    }
    let result = null;
    try {
        result = await browser.tabs.sendMessage(tab.id, { type: "spud-probe" });
    } catch (e) {
        result = null;
    }
    return { tab: tab, state: popupStateFromProbe(result) };
}

function render(state) {
    document.getElementById("known-state").hidden = state !== "known";
    document.getElementById("unknown-state").hidden = state === "known";
    document.getElementById("open-button").textContent = localized("popup_open", "Open in Spud");
    document.getElementById("unknown-message").textContent = localized("popup_not_lemmy", "Not a Lemmy instance");
    document.getElementById("spud-popup").classList.remove("loading");
}

async function openInSpud(tabId) {
    const errorEl = document.getElementById("error-message");
    errorEl.hidden = true;
    try {
        await browser.tabs.sendMessage(tabId, { type: "spud-open" });
        window.close();
    } catch (e) {
        errorEl.textContent = localized("popup_error", "Couldn't open - try again");
        errorEl.hidden = false;
    }
}

async function init() {
    const probed = await probeActiveTab();
    render(probed.state);
    if (probed.state === "known" && probed.tab) {
        document.getElementById("open-button").addEventListener("click", function () {
            openInSpud(probed.tab.id);
        });
    }
}

// Browser-only entry point. Guarded so requiring this file in node (for the
// helper test) has no side effects.
if (typeof window !== "undefined" && typeof document !== "undefined") {
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { popupStateFromProbe };
}
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `node OpenInAppExtension/Resources/__tests__/popup.test.cjs`
Expected: PASS — prints `popup.js helper tests passed`.

- [ ] **Step 5: Replace `popup.html`.** Overwrite `OpenInAppExtension/Resources/popup.html` entirely (classic `<script>`, both states present but hidden until JS renders):

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <link rel="stylesheet" href="popup.css">
    <script src="popup.js"></script>
</head>
<body>
    <div id="spud-popup" class="loading">
        <div id="known-state" hidden>
            <button id="open-button" type="button">Open in Spud</button>
        </div>
        <div id="unknown-state" hidden>
            <p id="unknown-message">Not a Lemmy instance</p>
        </div>
        <p id="error-message" hidden></p>
    </div>
</body>
</html>
```

- [ ] **Step 6: Replace `popup.css`.** Overwrite `OpenInAppExtension/Resources/popup.css` entirely:

```css
:root {
    color-scheme: light dark;
}

body {
    margin: 0;
    min-width: 220px;
    font-family: system-ui, -apple-system, sans-serif;
}

#spud-popup {
    padding: 14px 16px;
    text-align: center;
}

/* Hidden until the probe resolves, so neither state flashes on open. */
#spud-popup.loading {
    visibility: hidden;
}

#open-button {
    display: block;
    width: 100%;
    box-sizing: border-box;
    border: 0;
    border-radius: 10px;
    padding: 11px 16px;
    background: #30b0c7;
    color: #fff;
    font: 600 16px system-ui, -apple-system, sans-serif;
    cursor: pointer;
}

#open-button:active {
    opacity: 0.75;
}

#unknown-message {
    margin: 6px 0;
    color: #666;
    font: 400 14px system-ui, -apple-system, sans-serif;
}

#error-message {
    margin: 10px 0 0;
    color: #d33;
    font: 400 13px system-ui, -apple-system, sans-serif;
}

@media (prefers-color-scheme: dark) {
    #unknown-message {
        color: #aaa;
    }
}
```

- [ ] **Step 7: Add the popup i18n strings.** In `OpenInAppExtension/Resources/_locales/en/messages.json`, add three keys before the closing `}` (add a comma after the current last entry `banner_dismiss`):

```json
    "banner_dismiss": {
        "message": "Dismiss",
        "description": "Accessibility label of the banner's dismiss button."
    },
    "popup_open": {
        "message": "Open in Spud",
        "description": "Label of the toolbar popup button that opens the current page in the Spud app."
    },
    "popup_not_lemmy": {
        "message": "Not a Lemmy instance",
        "description": "Toolbar popup message shown when the current page is not a known Lemmy instance."
    },
    "popup_error": {
        "message": "Couldn't open - try again",
        "description": "Toolbar popup message shown when handing the page to the app failed."
    }
```

- [ ] **Step 8: Grant `activeTab`.** In `OpenInAppExtension/Resources/manifest.json`, change:

```json
  "permissions" : [

  ],
```

to:

```json
  "permissions" : [
    "activeTab"
  ],
```

- [ ] **Step 9: Gut the dead `background.js` stub.** Overwrite `OpenInAppExtension/Resources/background.js` entirely:

```javascript
// The "Open in Spud" flow is popup <-> content-script direct messaging; no
// background coordination or native messaging is used. This service worker is
// intentionally empty (Manifest V3 still requires the declared file to exist).
```

- [ ] **Step 10: Validate the JSON files parse.**

Run: `node -e "require('./OpenInAppExtension/Resources/manifest.json'); require('./OpenInAppExtension/Resources/_locales/en/messages.json'); console.log('json ok')"`
Expected: prints `json ok` (a trailing-comma or brace slip throws here).

- [ ] **Step 11: Commit.**

```bash
git add OpenInAppExtension/Resources/popup.js OpenInAppExtension/Resources/popup.html OpenInAppExtension/Resources/popup.css OpenInAppExtension/Resources/manifest.json OpenInAppExtension/Resources/_locales/en/messages.json OpenInAppExtension/Resources/background.js OpenInAppExtension/Resources/__tests__/popup.test.cjs
git commit -m "feat: implement Open-in-Spud Safari toolbar popup"
```

- [ ] **Step 12: Manual verification (Safari Web Extension flows can't be automated here — idb tap is dead and Web Extensions aren't XCUITest-drivable).** Build and run the `Spud` app on the iOS Simulator (`make build` then launch, or run from Xcode) so the extension installs, then in the Simulator:
  1. Settings → Safari → Extensions → enable "Open in Spud" and allow it on All Websites.
  2. **Smoke-test the risk first (Global Constraints):** open `https://lemmy.world/post/1` in Safari, tap the extensions/puzzle button → "Open in Spud". Confirm the popup shows the **enabled** button and tapping it opens the Spud app on that post. (If `sendMessage` to the content script does not work here, stop and switch to the spec's fallback mechanism — popup parses `manifest.json` matches + `browser.tabs.update(tabId,{url})`.)
  3. Open `https://lemmy.world/` (instance home) → popup shows the enabled button; tapping opens the app (a haptic-warn dead-end is expected and out of scope per Global Constraints).
  4. Open `https://www.google.com/` → popup shows "Not a Lemmy instance" with no button.
  Record the result of each in the task notes.

---

### Task 3: Documentation

**Files:**
- Modify: `docs/features/share-extension.md`, `docs/features/README.md`

**Interfaces:** none (documentation only).

- [ ] **Step 1: Update the feature-doc status line.** In `docs/features/share-extension.md`, replace line 4:

```markdown
- **Status:** partial — the Safari banner and the "Open in Spud" share/action both work; the Safari Web Extension's browser-action popup is an unimplemented stub
```

with:

```markdown
- **Status:** shipped — the Safari banner, the toolbar popup, and the "Open in Spud" share/action all work
```

- [ ] **Step 2: Add a behavior bullet for the popup.** In `docs/features/share-extension.md`, immediately after the "Banner runs on known instances." bullet (the one ending "use the share sheet for those."), add:

```markdown
- **Toolbar popup, known instances.** The Safari toolbar button opens a popup
  that offers a single "Open in Spud" on any page of a known instance (the same
  bundled allowlist the banner uses — the popup detects it via the content
  script's presence, not a duplicated host list). Unlike the banner it is
  available on non-content pages (instance home, search) and after the banner is
  dismissed. On a non-allowlisted host or a non-Lemmy page it shows an inactive
  "Not a Lemmy instance" message instead of an action.
```

- [ ] **Step 3: Add a popup scenario.** In `docs/features/share-extension.md`, after the "### Open a Lemmy post from Safari" scenario block (after its `- **Then** ...` line), add:

```markdown
### Open the current instance page from the toolbar popup

- **Surfaces:** `share-extension`, `iphone`, `ipad`
- **Given** I am on any page of a known Lemmy instance in Safari
- **When** I tap the Spud toolbar button and choose "Open in Spud"
- **Then** the app opens and resolves that page (a post/community/user opens its screen)

### The popup is inactive off a known instance

- **Surfaces:** `share-extension`, `iphone`, `ipad`
- **Given** I am on a non-Lemmy page (or a Lemmy instance not in the allowlist)
- **When** I open the Spud toolbar popup
- **Then** it shows "Not a Lemmy instance" and offers no action
```

- [ ] **Step 4: Remove the stale "popup is a stub" out-of-scope bullet.** In `docs/features/share-extension.md`, delete the bullet:

```markdown
- **The Safari Web Extension browser-action popup is a stub.** The toolbar-button
  popup is not implemented; the banner and the share/action extension are the
  working entry points.
```

and, so the acknowledged limitation is not lost, replace the "No instance-home open." bullet:

```markdown
- **No instance-home open.** A bare instance URL (e.g. `lemmy.world`) is not routed
  to an in-app screen.
```

with:

```markdown
- **No instance-home open.** A bare instance URL (e.g. `lemmy.world`) is not routed
  to an in-app screen. The toolbar popup still offers "Open in Spud" on such a
  page (it acts on any known-instance page), but the app cannot resolve it and
  plays a warning haptic — improving that feedback is a follow-up that also
  affects the banner.
```

- [ ] **Step 5: Update the README capability table.** In `docs/features/README.md`, change line 117 from:

```markdown
| [Open in Spud (Safari extension)](share-extension.md) | `share-extension`, `iphone`, `ipad` | partial |
```

to:

```markdown
| [Open in Spud (Safari extension)](share-extension.md) | `share-extension`, `iphone`, `ipad` | shipped |
```

- [ ] **Step 6: Update the README status-list line.** In `docs/features/README.md`, change line 212 from:

```markdown
- [~] "Open in Spud" — Safari banner (Web Extension) + an "Open in Spud" share/action extension (handles post / comment / community / user URLs); the Web Extension's browser-action popup is a stub
```

to:

```markdown
- [x] "Open in Spud" — Safari banner (Web Extension) + a toolbar popup (both known-instance) + an "Open in Spud" share/action extension (handles post / comment / community / user URLs)
```

- [ ] **Step 7: Update the README by-area map.** In `docs/features/README.md`, change line 55 from:

```markdown
| `share-extension` | "Open in Spud" Safari Web Extension (`OpenInAppExtension`) — rewrites a Lemmy post page to a deep link that opens the post in the app |
```

to:

```markdown
| `share-extension` | "Open in Spud" Safari Web Extension (`OpenInAppExtension`) — in-page banner + toolbar popup on known instances, plus the share/action extension — hands a Lemmy page to a deep link that opens it in the app |
```

- [ ] **Step 8: Commit.**

```bash
git add docs/features/share-extension.md docs/features/README.md
git commit -m "docs: mark Safari toolbar popup shipped in share-extension docs"
```

---

## Self-Review

**1. Spec coverage:**
- Known-instance-only via content-script presence → Task 1 (probe responder) + Task 2 (`probeActiveTab`). ✓
- Single "Open in Spud" on any page of a known instance → Task 1 `spud-open` navigates via `lemmyDeepLink`; Task 2 renders the button. ✓
- "Not a Lemmy instance" inactive state off a known instance → Task 2 `render("unknown")`. ✓
- Reuse `lemmyDeepLink` / the banner's `resolve` deep link, no duplicated host list → Task 1 reuses `lemmyDeepLink`; detection is content-script presence, not a copied list. ✓
- `activeTab` permission only → Task 2 Step 8. ✓
- Gut `background.js`; leave `SafariWebExtensionHandler.swift` unchanged → Task 2 Step 9 (no Swift touched). ✓
- Node test of the pure state helper + `handlePopupMessage` → Task 1 Step 1, Task 2 Step 1. ✓
- `.unresolved` haptic dead-end is an explicit non-goal, documented → Task 3 Step 4. ✓
- iOS `sendMessage` risk smoke-tested first → Task 2 Step 12.2. ✓
- Docs: `share-extension.md` status+scenario, README table + status list + by-area map → Task 3. ✓

**2. Placeholder scan:** No TBD/TODO; every code and doc step shows the exact content. ✓

**3. Type consistency:** `handlePopupMessage(message, deps)` with `deps.getHref`/`deps.navigate` is used identically in Task 1 test, implementation, and wiring. `popupStateFromProbe(result)` returns `"known"`/`"unknown"` consistently in Task 2 test, `probeActiveTab`, `render`, and `init`. Message types `"spud-probe"`/`"spud-open"` and the `{known:true}`/`{ok:true}` shapes match between the content-script responder (Task 1) and the popup sender (Task 2). Element ids (`spud-popup`, `known-state`, `unknown-state`, `open-button`, `unknown-message`, `error-message`) match between `popup.html` and `popup.js`. i18n keys (`popup_open`, `popup_not_lemmy`, `popup_error`) match between `popup.js` and `messages.json`. ✓
