# Open in Spud — instance-agnostic Lemmy link handling

Date: 2026-06-17
Status: Design approved, ready for implementation plan

## Problem

Spud cannot open an arbitrary Lemmy `https://` link the way a native app should.
Today's inbound link handling has three hard limits:

1. **Single entry point, single instance.** The only "open a web post in Spud"
   path is a Safari *web* extension whose content script is scoped to
   `discuss.tchncs.de/post/*` and **silently auto-redirects** (`window.stop()` +
   `window.location.replace`) into the app. Posts on any other instance, and any
   link tapped outside Safari (Messages, Mail, another client), have no path in.
2. **No share-sheet entry.** There is no system Share/Action extension, so
   "Open in Spud" never appears when you share a Lemmy URL from another app.
3. **Post-only routing.** Even when a deep link arrives,
   `AppCoordinator.open(_:in:)` only routes `.post` and `.objectAtURL`→post.
   `.community` / `.person` log an error and go nowhere
   (`AppCoordinator.swift:86`), and comments are unhandled.

Associated Domains / Universal Links are **not an option**: Spud does not control
the thousands of federated instances and cannot host
`/.well-known/apple-app-site-association` on them. The instance-agnostic answer is
two thin entry points (an extended Safari banner + a new Action extension) feeding
the app's existing custom-scheme deep link, plus closing the app-side routing gap.

## Decisions (confirmed)

- **URL scope:** posts, comments, communities, users. Instance-home URLs are out
  of scope.
- **Safari trigger:** an injected, dismissible **"Open in Spud" banner** on
  recognized Lemmy pages — no more silent auto-redirect, no `window.stop()`.
- **Instance detection (Safari):** the content-script `matches` list is generated
  from the **bundled Explorer instance directory** (~505 hosts). Scoped host
  permission, high precision, no injection on random sites. The list is static and
  can go stale; brand-new instances simply get no banner (the Action extension
  covers them).
- **Action extension is the universal fallback:** it accepts a shared URL from any
  app and is instance-agnostic (it defers resolution to the app, which resolves any
  federated URL via the user's home instance).
- **Thin extensions, one resolution point.** Both entry points emit a single
  uniform deep link — `info.ddenis.spud://internal/resolve?url=<encoded page URL>`
  — for every recognized Lemmy content page. Neither extension links LemmyKit,
  performs networking, or touches accounts. All routing intelligence lives in the
  app's `.objectAtURL` resolver.
- **Comment open = open the post, scrolled to and highlighting the comment**,
  reusing the post-detail jump machinery. If the comment cannot be resolved, fall
  back to a toast (never a dead screen).
- **Routing stays in `AppCoordinator.open` + `MainWindow`** (no new
  `DeepLinkRouter` abstraction yet — extract later if Shortcuts/notifications also
  need it).

## Architecture / components

One shared seam: the `info.ddenis.spud://internal/...` custom scheme
(`SpudUtilKit/Extensions/URL+spud.swift`), already parsed by `URL.spud` and
dispatched by `SceneDelegate` → `AppCoordinator.open`.

| Area | Component | Change |
|---|---|---|
| Safari | `OpenInAppExtension/Resources/content.js` | Replace the `/post/` regex + auto-redirect. Detect Lemmy content pages by path shape (`/post/`, `/comment/`, `/c/`, `/u/`); on a match, inject a dismissible "Open in Spud" banner whose tap sets `window.location` to `spud://internal/resolve?url=<encoded current URL>`. No page-load blocking. |
| Safari | `OpenInAppExtension/Resources/manifest.json` | `content_scripts.matches` generated from the bundled Explorer directory instead of the hard-coded host. |
| Safari | build tooling | A generator (script + Makefile target) that emits the `matches` array from the seed so the allowlist is reproducible and regenerated when the seed updates. |
| Safari | `OpenInAppExtension/Resources/_locales`, `popup.*` | Localized banner strings; the placeholder "Hello World" popup is replaced with a minimal status/info popup (or removed if unused). |
| Share | **New `OpenInSpudAction` Action-extension target** | System share-sheet item "Open in Spud". `NSExtensionActivationRule` gates to Lemmy-ish web URLs. On invocation: read the input URL, build `spud://internal/resolve?url=<encoded URL>`, open the host app via `extensionContext.open(_:)` (responder-chain `open(_:)` fallback), then `completeRequest`. Minimal/no custom UI. Links **SpudUtilKit only** (for the `URL.SpudInternalLink` builder); no SpudDataKit, no app group, no keychain. |
| App | `Spud/Utils/LemmyURLParser.swift` | Stop deferring comments: `/comment/N` → `.objectAtURL(url:)` (benefits body-text taps too). |
| App | `SpudDataKit/.../ResolvedLemmyObject.swift` | Enrich the dataless `.comment` case to carry `postId` + `commentId` + `instance`, populated from the `resolve_object` response's `CommentView` (`response.comment.comment.post_id` / `.id`). |
| App | `Spud/App/AppCoordinator.swift` | Extend `open(_:in:)`: route `.community` and `.person` (currently the error gap), and switch the `.objectAtURL` resolve result over post / community / person / comment instead of post-only. |
| App | `Spud/Scenes/MainWindow/MainWindow.swift` | Add `display(community:instance:)`, `display(person:instance:)`, and `display(serverPostId:scrollToCommentId:)` siblings to `display(serverPostId:)`, reusing `CommunityOrLoadingViewController` / `PersonOrLoadingViewController` and the existing `pushDetail` split/nav logic. |
| App | `project.yml` | Declare the new `OpenInSpudAction` target + embed it in the `Spud` app; regenerate with `make project`. |

## Data flow

```
Lemmy https URL
  ├─ Safari page (allowlisted host): content.js path-shape match → banner
  │     → tap → window.location = spud://internal/resolve?url=<encoded page URL>
  └─ Any app: share sheet → "Open in Spud" (activation predicate gated)
        → extensionContext.open(spud://internal/resolve?url=<encoded URL>)
        ▼
SceneDelegate.openURLContexts → AppCoordinator.open(url) → url.spud == .objectAtURL(url)
        ▼  Task: resolveObject(url) under default/signed-out account
   .post(id,instance)            → MainWindow.display(serverPostId:)                 [exists]
   .community(name,instance)     → MainWindow.display(community:instance:)           [new]
   .person(id,instance)          → MainWindow.display(person:instance:)             [new]
   .comment(postId,commentId,..) → MainWindow.display(serverPostId:scrollToCommentId:) [new]
   .unresolved                   → warning haptic + toast                           [new]

(body-text taps also produce .community / .person / .post directly; those now route
 too, via the same MainWindow.display(...) methods — a bonus fix of the existing gap.)
```

The extensions never branch on content type; `resolve_object` is the single
classifier. A `/c/` open therefore costs one network round-trip — acceptable for a
deliberate "open in app" action, and it makes unknown instances work for free
(resolve runs against the user's home instance).

## Error handling

- **Unresolvable / non-Lemmy URL:** `.unresolved` (or a thrown resolve) → one
  warning haptic + a brief non-blocking toast ("Couldn't open this link in Spud").
  Never a blank screen. The Action extension always calls `completeRequest`
  promptly regardless, so the share sheet dismisses cleanly.
- **No default account yet:** `resolveObject` needs an account. Reuse
  `currentDefaultAccountKeychainId()` and the existing signed-out fallback; if truly
  none, show the same toast.
- **Cold launch:** a deep link arriving in `scene(_:willConnectTo:)` before the UI
  is ready already forwards through `connectionOptions.urlContexts`
  (`SceneDelegate.swift:33`). The new community/person/comment `display` paths must
  tolerate being invoked at first display (queue until the tab/nav stack exists,
  mirroring how `display(serverPostId:)` selects/creates the stack).
- **Banner nagging:** the content-script banner is dismissible and remembers
  dismissal for the page session (e.g. `sessionStorage`) so it does not reappear on
  scroll/SPA navigation within the same post.
- **Activation false positives:** the predicate matches by path shape only, so a
  non-Lemmy URL that happens to look like a Lemmy path (e.g. some unrelated site
  with `/post/123`) can still offer the "Open in Spud" item. The app's resolve then
  returns `.unresolved` and falls through to the toast. Acceptable — the cost is one
  failed resolve, not a crash or dead screen.

## Testing

- **LemmyURLParser (unit):** extend `SpudTests/LemmyURLParserTests` for
  `/comment/N` → `.objectAtURL`, plus existing `/u/`, `/c/name`, `/c/name@host`.
- **ResolvedLemmyObject (unit):** initializer maps a `CommentView` response to
  `.comment(postId:commentId:instance:)`; post/community/person/unresolved
  unchanged.
- **Routing (unit):** `AppCoordinator.open` dispatch table — each
  `URL.SpudInternalLink` case and each `.objectAtURL` resolved type lands on the
  correct `MainWindow.display(...)` call, using a fake window + stub `resolveObject`
  (post / community / person / comment / unresolved).
- **URL round-trip:** `URLSpudInternalLinkTests` already covers the wire format;
  add a `resolve?url=` case with an embedded query to guard the sub-delimiter
  escaping.
- **Content script (JS):** a small node fixture test mapping representative URLs
  (all four path types, with/without trailing segments, query strings) → expected
  `resolve?url=` deep links, and asserting non-Lemmy paths produce no banner.
- **Manual matrix** (documented under `docs/features/`): share a post / comment /
  community / user URL from Messages and open the banner in Safari, on a known and
  an unknown instance; verify the unknown instance works via the Action extension
  and not the Safari banner.

## Docs to update

- `docs/features/share-extension.md` — currently describes the Safari-only,
  single-instance, post-only behavior as "partial". Rewrite for: banner across the
  bundled allowlist + system Action extension + full post/comment/community/user
  coverage.
- New or merged `docs/features/` entry for the Action extension surface.

## Out of scope (YAGNI)

- Instance-home (`.instance`) opens — left logging as today.
- Universal Links / Associated Domains — impossible without controlling instances.
- Resolving inside an extension, or a rich share-sheet preview/confirmation UI.
- A `name@host` community **fast path** (no-network) — uniform `resolve` is simpler;
  revisit only if the round-trip proves noticeable.
- The separate App Intents / Shortcuts / Spotlight gap from the system-integration
  assessment — a distinct future effort.

## Open risks / to verify during implementation

- **`extensionContext.open(_:)` from an Action extension.** Confirm it opens the
  custom scheme on current iOS; keep the responder-chain `UIApplication.open`
  fallback ready if not.
- **`CommentView` field names** in the pinned LemmyKit `Components.Schemas`
  (`post_id`, `id`) — verify against the generated types before wiring the
  `.comment` enrichment.
- **`matches` list size** — ~505 hosts × path patterns; confirm Safari iOS accepts
  the generated manifest and the permission prompt reads acceptably.
- **`display(serverPostId:scrollToCommentId:)`** — confirm the post-detail jump/
  highlight machinery (from the post-tracking work) exposes a usable "scroll to
  comment id" entry, or add one.
