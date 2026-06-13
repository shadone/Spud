# Spud — design north-star (Apollo-parity bar)

Goal: a Lemmy client whose UI/UX is **at least on par with Apollo for Reddit**. Apollo's
reputation came from feel, not feature count — fluid gestures, instant feedback, deep
customization, and refined media. Every feature is
built to this bar, not just to "works". When a feature lands, it should feel native, fast,
and considered.

This file is the concise **feel bar**. The full design system — tokens, palette, typography,
density, iconography, screens, accessibility, and the performance budget — lives in
[`design/DESIGN-BRIEF.md`](design/DESIGN-BRIEF.md).

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
  direction) mapped to upvote / downvote / save / reply / share / collapse. Sensible defaults,
  user-configurable (shipped in M8).
- **Swipe-to-collapse** comment threads; tap anywhere on a comment to collapse/expand, with a
  collapsed-count badge and colored depth rails.
- **Swipe-from-edge back**; **swipe-to-dismiss** on sheets and the full-screen media viewer.

## Comments (where Lemmy clients live or die)

- Tap-to-collapse with smooth height animation + collapsed child count.
- Colored depth indicator rails (one hue per depth, subtle).
- A **jump button** / floating control to skip to the next top-level comment.
- Inline parent-comment context when arriving from inbox/permalink.
- Load-more-replies and continue-thread handling.

## The full system

Media, compose, customization, accessibility, and the performance budget are specified in
[`design/DESIGN-BRIEF.md`](design/DESIGN-BRIEF.md) (§5 design system, §9 accessibility, §10
performance budget) and feature status is documented per-capability under [`features/`](features/README.md).
