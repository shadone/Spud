# Post author status

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [post-detail-and-comments.md](post-detail-and-comments.md), [moderation-actions.md](moderation-actions.md), [person-profile.md](person-profile.md), [removed-unavailable-content.md](removed-unavailable-content.md), [accessibility.md](accessibility.md)

## What it does

Spud surfaces a post author's role and moderation status so a reader knows who
they're reading. On the post-detail header, the author's byline carries full pill
badges — MOD, ADMIN, BOT, BANNED (from this community), SUSPENDED (site-wide) —
matching the pills a comment by the same author shows. The feed stays deliberately
low-noise: a post cell shows only a single small red "banned author" marker, and
only when the author is suspended site-wide or banned from the community — never
for benign roles. A post whose author account has been deleted reads as "[deleted]"
with no profile link.

## Behavior and rules

- **Two different bans, kept distinct on the detail header.** "SUSPENDED" means the
  author is banned site-wide on their home instance; "BANNED" means the author is
  banned from *this* community. Both render as red `person.fill.xmark` pills; a post
  can carry both.
- **Detail pills mirror the comment badges.** The same order (MOD, ADMIN, BOT,
  BANNED, SUSPENDED), colors, and glyphs a comment header uses, minus "OP" (a post's
  author *is* the original poster) and minus the solid "distinguished" fill (a post
  carries no per-post distinguished statement). So a post and a comment by the same
  author read identically.
- **The feed is low-noise.** A post cell adds exactly ONE inline red
  `person.fill.xmark` marker, leading the metadata line (score / comments / age), and
  only for a suspended or community-banned author. Moderator, admin, and bot authors
  add no feed marker — those roles are surfaced on the detail header, not the list.
  The feed never shows the author name; the list is otherwise unchanged.
- **"[deleted]" author.** When the author's account is deleted, the detail byline
  renders the name as "[deleted]" in a quiet tertiary color, with the profile deep
  link and the home-instance "@host" suffix suppressed — the same treatment a comment
  by a deleted author gets. This is distinct from a *deleted post* (the author's own,
  restorable), which dims the title and adds a separate "Deleted" byline marker.
- **Accessibility.** On the detail header the pills are grouped into a single
  VoiceOver element spoken right after the byline (e.g. "moderator, suspended
  site-wide"), so the status is announced without depending on the glyphs. On the feed
  cell the ban phrase ("suspended site-wide" / "banned from this community") is folded
  into the cell's spoken subtitle, so VoiceOver announces it rather than relying on the
  red marker. Benign roles are not announced on the feed (they carry no feed marker).

## Scenarios

### Suspended author on the post detail header

- **Given** a post whose author is banned site-wide on their home instance
- **When** the reader opens the post
- **Then** the header byline shows a red "SUSPENDED" pill beneath "in <Community> by <Author>"
- **And** VoiceOver announces "suspended site-wide" after the byline

### Moderator/admin author on the post detail header

- **Given** a post whose author both moderates the community and is an instance admin
- **When** the reader opens the post
- **Then** the header shows tinted "MOD" and "ADMIN" pills in that order
- **And** VoiceOver announces "moderator, admin" after the byline

### Banned author flagged in the feed

- **Given** a post in the feed whose author is suspended or banned from the community
- **When** the feed renders the post cell
- **Then** a single small red `person.fill.xmark` marker leads the cell's metadata line
- **And** VoiceOver's spoken subtitle includes the ban phrase

### Benign-role author is quiet in the feed

- **Given** a post in the feed whose author is a moderator, admin, or bot (and not banned)
- **When** the feed renders the post cell
- **Then** the cell shows no author-status marker and reads identically to an ordinary post

### Deleted author account

- **Given** a post whose author account has been deleted
- **When** the reader opens the post
- **Then** the byline reads "by [deleted]" in a quiet color, with no profile link and no "@host"
- **And** the author carries no status pills

## Not supported / out of scope

- The feed never shows the author's name or role pills — only the low-noise banned-author marker.
- The feed does not distinguish a site suspension from a community ban; the single marker covers both. The distinction is drawn only on the post detail header (SUSPENDED vs BANNED).
- No "OP" or "distinguished" treatment on a post's author (those are comment-only concepts).
- This is presentation only: it flags status the server already reports and does not perform or change any moderation action (see [moderation-actions.md](moderation-actions.md)).
