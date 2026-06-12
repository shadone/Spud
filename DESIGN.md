# Spud — design north-star (Apollo-parity bar)

Goal: a Lemmy client whose UI/UX is **at least on par with Apollo for Reddit**. Apollo's
reputation came from feel, not feature count — fluid gestures, instant feedback, deep
customization, and refined media. Every feature in `RELEASE-PLAN.md` is built to this bar, not
just to "works". When a feature lands, it should feel native, fast, and considered.

## Non-negotiable feel (apply to every screen)

- **Haptics** on every committal action (vote, save, subscribe, send, collapse) — `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`, light by default.
- **Optimistic-feeling UI** — actions reflect instantly. (Data layer stays confirm-then-mirror per `vote()`, but the UI shows pending state immediately and never blocks the main thread.)
- **Fluid animations** — spring-based, interruptible; respect `UIAccessibility.isReduceMotionEnabled`.
- **Fast scrolling** — image prefetch, cell reuse, no main-thread markdown parsing (parse off-main, cache `NSAttributedString`).
- **Context menus with previews** on posts, comments, users, communities, links.
- **Pull-to-refresh** everywhere a feed lives; **infinite scroll** with a tasteful footer spinner.
- **Empty / error / loading** states are designed, not blank — every async surface has all three.

## Gestures (Apollo's signature)

- **Customizable swipe actions** on post and comment cells: up to 4 slots (short/long swipe, each
  direction) mapped to upvote / downvote / save / reply / collapse / share / hide. Ship sensible
  defaults; make them user-configurable in M8.
- **Swipe-to-collapse** comment threads; tap anywhere on a comment to collapse/expand, with a
  collapsed-count badge and colored depth rails.
- **Swipe-from-edge back**; **swipe-to-dismiss** on sheets and the full-screen media viewer.

## Comments (where Lemmy clients live or die)

- Tap-to-collapse with smooth height animation + collapsed child count.
- Colored depth indicator rails (one hue per depth, subtle).
- A **jump button** / floating control to skip to the next top-level comment.
- Inline parent-comment context when arriving from inbox/permalink.
- Load-more-replies and continue-thread handling.

## Media

- Inline thumbnails with smart layout (text vs link vs image vs video).
- Full-screen **image viewer**: pinch-zoom, double-tap-zoom, pan, swipe-to-dismiss, share/save.
- **Galleries** (swipeable), animated GIF + video (loop, mute toggle), link previews with favicon.
- Image peek via context-menu preview.

## Compose

- Markdown editor with a **formatting toolbar** (bold, italic, strikethrough, link, quote, list,
  code, spoiler) operating on the selection.
- **Live preview** toggle using the same `Down`/`LinkLabel` render path as comment cells.
- Draft persistence per target; never lose text on error or dismiss.

## Customization (M8, but design data models for it now)

- Themes: light / dark / **true-black (OLED)**, plus accent color; per-theme.
- Selectable app icons; font family + Dynamic Type size; post/comment density; thumbnail side.
- All preferences live in `PreferencesService` (AsyncStream-backed) so UI reacts live.

## Accessibility (first-class, not a pass at the end)

- Full Dynamic Type; VoiceOver labels/traits on every interactive element (incl. the `LinkLabel`
  per-link-range fix already noted); honor reduce-motion and increase-contrast.

## Performance budget

- 60/120fps scroll on a feed of 100+ posts. Markdown parsed off-main and cached. Images
  downsampled to the display size before display. No synchronous disk/db on the main thread.

## How this shows up in code

- A shared `Haptics` helper in `SpudUIKit`; spring animation helpers; an off-main markdown
  cache; a reusable full-screen media viewer; a configurable swipe-action model. Build these as
  the features that need them land, then retrofit — don't ship a feature that skips the feel.
