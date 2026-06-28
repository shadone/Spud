# Configurable swipe actions

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Marking posts read and hiding read posts](mark-read-and-hiding.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Apollo-style swipe gestures on every post and comment cell. Each cell has four swipe
slots — a short and a long (deep) swipe in each direction — and you assign what each one
does. Posts and comments are configured independently in Settings, with sensible defaults
and a one-tap reset per kind.

## Behavior and rules

- **Four slots per kind.** Each direction has two slots: a short swipe fires the **primary** action, a deeper/longer swipe fires the **secondary** one. In Settings they read as Right Swipe (Short/Long) and Left Swipe (Short/Long).
- **Assignable actions:** None, Upvote, Downvote, Save, Reply, Share — plus **Collapse**, which is comment-only. A slot set to None does nothing in that direction/depth.
- **Posts and comments are separate configs.** Settings has a Posts section and a Comments section, each with its own four pickers and its own "Reset … Swipe Actions" button.
- **Defaults.** Posts: short-right Upvote, long-right Downvote, short-left Reply, long-left Save. Comments: short-right Upvote, long-right Downvote, short-left Reply, long-left Collapse.
- **Changes apply live.** Reassigning a slot updates already-visible cells immediately; there is no relaunch and no need to leave the feed.
- **Presentation is state-aware.** A Save slot reads Save or Unsave, a vote slot reads Upvote/Downvote or Remove vote, a Collapse slot reads Collapse or Expand; vote glyphs and tints follow the active theme.
- **Stored config is forgiving.** An unknown or invalid pairing (e.g. Collapse assigned to a post) degrades to None rather than failing to load.
- **Spud uses UIKit's leading/trailing axis:** leading = swipe right, trailing = swipe left. The default layout is: leading short (upvote) / leading long (downvote); trailing short (reply) / trailing long (save for posts, collapse for comments). All four slots are remappable per account in Settings.

## Scenarios

### Upvote with a short swipe (default)

- **Given** a post in any feed, or a comment in a post's thread
- **When** I short-swipe it from the leading (right) edge
- **Then** it is upvoted, with a haptic on commit
- **And** the same gesture removes the vote if it was already upvoted

### Reassign a slot, applied live

- **Given** Settings → Swipe Actions
- **When** I set the Posts "Left Swipe (Long)" slot to Share
- **Then** a long left-swipe on a post now opens the share sheet
- **And** posts already on screen pick up the new mapping without a refresh

### A deep swipe triggers the secondary action

- **Given** the default comment config
- **When** I swipe a comment from the leading edge and keep going past the short threshold
- **Then** the secondary action fires (Downvote) instead of the primary (Upvote)

### Reset a kind to defaults

- **Given** I have customized the comment slots
- **When** I tap "Reset Comment Swipe Actions"
- **Then** the four comment slots return to Upvote / Downvote / Reply / Collapse

### An empty slot does nothing

- **Given** a slot set to None
- **When** I swipe in that direction/depth
- **Then** no action is taken and the cell springs back

## Not supported / out of scope

- Only two tiers per direction (short + long); there is no third, deeper action.
- **Collapse** is comment-only — it is not offered for posts, and a stored Collapse-on-a-post pairing is treated as None.
- Swipe gestures elsewhere (Inbox swipe-to-mark-read, account-list swipes) are fixed and are **not** governed by this configuration; they belong to their own features.
- No per-community, per-feed, or per-account swipe overrides — a kind's config is global.
