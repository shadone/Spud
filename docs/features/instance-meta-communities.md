# Instance meta communities

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — badge + the Communities-tab "About `<instance>`" section, whose
  rows offer Favourite, "Notify About New Posts", and (signed in) Subscribe; plus an
  "About this instance" card on the instance-detail screen for **whichever instance
  you're viewing** (not just your home one), whose rows carry the same actions behind a
  long-press context menu instead of inline controls.
- **Related:** [Discover (Community Explorer)](discover.md), [Search](search.md), [Community screen](community-screen.md), [Subscribe / unsubscribe](subscribe-unsubscribe.md), [Communities tab (subscriptions)](subscriptions-sidebar.md), [Instance browsing (open an instance in-app)](instance-browsing.md), [Reminders](reminders.md), [2026-07-14-instance-meta-communities-design.md](../superpowers/specs/2026-07-14-instance-meta-communities-design.md), [docs/superpowers/specs/2026-07-19-community-new-posts-follow-design.md](../superpowers/specs/2026-07-19-community-new-posts-follow-design.md), [docs/superpowers/specs/2026-07-19-instance-detail-meta-section-design.md](../superpowers/specs/2026-07-19-instance-detail-meta-section-design.md)

<!-- These are product-feature descriptions for an end-user audience, with a
     sprinkle of technical detail — not implementation docs. Do NOT link to
     source files (.swift) anywhere in the doc; reference symbols as inline code
     (`HideReadPostsFilter`), never as links. Link only plans / design docs /
     sibling feature docs. -->

## What it does

A "meta" community is one that's about the instance itself — its news, changelog,
support, and site discussion — like `announcements@lemmy.world` or
`tchncs@discuss.tchncs.de`. Spud detects these with a heuristic and marks them with a
small badge everywhere community lists appear: Discover, the Communities tab, Search
results, and the community header. The Communities tab also gets an always-visible
"About `<your instance>`" section listing your home instance's own meta communities,
each with one-tap Favourite, a bell to be notified of its new posts (see
[Reminders](reminders.md)), and, when signed in, Subscribe — no manual search required
to find where your instance's own announcements live, and no need to check back
manually for its next post either. The instance-detail screen (see
[Instance browsing](instance-browsing.md)) shows the same idea for **any** instance you
open, not just your home one: an "About this instance" card lists that instance's own
meta communities, with Favourite, Notify, and Subscribe reachable from a long-press
context menu instead of inline controls.

## Behavior and rules

- **Detection is a heuristic, not a server-provided fact.** Lemmy's API has no field
  that designates a community as "the instance's meta community" — Spud infers it from
  the community's name/title, its home instance's domain, and (when known) the
  instance's site name. Meta-ness is intrinsic to the community's own home instance,
  not relative to who's viewing: `tchncs@discuss.tchncs.de` is meta for everyone,
  regardless of account.
- **Two confidence tiers.** A community is **high-confidence** meta when its normalized
  name/title equals the instance's site name or its primary domain label (equality
  only — never a substring match, so `world@lemmy.world` is **not** flagged just
  because "world" appears in the domain), or when it contains a strong/unambiguous
  keyword (`meta`, `announcements`, `changelog`, `sitenews`, `site`, `instance`, and
  similar). It's **low-confidence** meta when it only matches a broader, more ambiguous
  keyword (`support`, `help`, `news`, `general`, `welcome`, `rules`, and similar).
  Everything else is not meta.
- **Broad matching can occasionally mislabel an ordinary community** — a generic
  `general` or `news` community that isn't really about the instance. This is an
  accepted trade-off: the app never auto-acts on the classification, only suggests, so
  a false positive costs nothing worse than a badge or an extra row under a disclosure.
- **The badge is informational, not actionable.** It reads "Instance community" to
  VoiceOver and appears next to the community's name in every list — Discover (rails,
  directory, "See all", pack detail, compare sheet), the Communities tab's own
  subscribed-communities list, Search's community results, and as a small pill next to
  the title on an open community's header.
- **The "About `<instance>`" section is always visible in the Communities tab** — even
  before subscribing to anything, and even signed out (browsing anonymously still has a
  home instance). High-confidence meta communities are listed first; any low-confidence
  ones are tucked under a "More on this instance" disclosure so the section doesn't get
  noisy. If no meta communities have been found yet (or the instance genuinely has
  none), the section is simply omitted rather than showing an empty state.
- **Each row offers Favourite, a notify bell, and (signed in only) Subscribe.**
  Favourite pins the community for quick access and works purely locally, so it's
  available even browsing signed out. The bell toggles "Notify About New Posts" — a
  standing local follow that fires a notification the next time the community posts
  something new (see [Reminders](reminders.md)) — and is likewise available signed in or
  out, since it's local and per-account like Favourite. Subscribe adds the community to
  your Subscribed feed and is only offered when signed in, since a signed-out/anonymous
  browse has no server-side subscription to change. **Nothing is auto-subscribed,
  auto-favourited, or auto-followed** — every action is a deliberate one-tap choice, and
  the three are fully independent of each other (see
  [Subscribe / unsubscribe](subscribe-unsubscribe.md)).
- **Resolution and caching.** The set of meta communities for an instance is found by
  checking a fixed, bounded list of likely community names (e.g. "meta",
  "announcements", "support", "news"...) against that instance and classifying any
  hits. Results are cached per account, so the app doesn't repeat this lookup on every
  visit — it refreshes once per Communities-tab session and skips the check entirely
  while the cache is still fresh (about a day). A resolution pass that finds nothing
  (e.g. a network blip) never wipes a previously-good cached result. The badge itself
  never depends on this cache — it's computed fresh, inline, from whatever community
  data the list is already showing.
- **The instance-detail screen reuses this same cache, keyed per instance you're
  viewing.** Opening the instance-detail screen (the "before you commit" screen reached
  from an instance's health card, or from the instance picker — see
  [Instance browsing](instance-browsing.md)) fires the identical refresh for the viewed
  host, using the app's current default account (signed in or browsing signed out) to do
  the resolving. The same 24-hour freshness and never-overwrite-on-a-miss rules apply.
  The card is simply absent — no placeholder — until the app has a default account and
  that refresh (or a still-fresh earlier one) has something to show; there's no
  directory-classified fallback while waiting.
- **Row actions there are a long-press context menu, not inline controls.** The
  instance-detail card's rows match its Communities card's compact row style (icon,
  `c/name` handle with the "Instance community" badge glyph, an optional title subtitle,
  chevron) — tapping a row opens the community, and every action instead lives behind a
  long-press: Open Community, Subscribe/Unsubscribe, Add to Favorites (or Remove from
  Favorites), Notify About New Posts, Mute/Unmute, Share, Copy Link, and Block Community.
  This is the same community context menu [Search](search.md)'s results use, plus
  Favourite. Rows resolve through your home instance's own connection, exactly like the
  Communities-tab section, so every action works regardless of which instance's meta
  communities you're looking at.
- **Subscribe is sign-in gated here rather than simply hidden.** Unlike the
  Communities-tab section, which omits the Subscribe control entirely when signed out,
  the instance-detail menu always offers "Subscribe" / "Unsubscribe" and shows the
  sign-in gate instead of a doomed attempt when signed out. Favourite and Notify work
  signed out either way. Blocking a community from this menu also removes a live
  "Notify About New Posts" follow on it, same as every other block entry point (see
  [Reminders](reminders.md)).
- **Favourite is a shared, host-optional menu action.** The community long-press menu
  builder — the same one Search's results use — can offer "Add to Favorites" / "Remove
  from Favorites" when the hosting screen supplies favourite state; the instance-detail
  screen does, Search doesn't, so Search's own menu is unchanged. The copy ("Add to
  Favorites" / "Remove from Favorites") and star / star-slash symbols are centralized so
  the wording can't drift between this menu and the community screen's own overflow
  action.

## Scenarios

### Meta community shows a badge in a list

- **Given** a community whose name matches a strong meta keyword (e.g.
  `announcements@lemmy.world`) or the instance's own name (e.g.
  `tchncs@discuss.tchncs.de`)
- **When** it appears in Discover, the Communities tab, Search results, or a community
  header
- **Then** it shows a small "Instance community" badge next to its name

### Ordinary community shows no badge

- **Given** a community whose name doesn't match the instance's identity or any meta
  keyword (e.g. `photography@lemmy.world`)
- **When** it appears in any community list
- **Then** no badge is shown
- **And** the instance's own name never false-flags an unrelated community by
  coincidence — `world@lemmy.world` is not badged, because domain-label matching
  requires equality, not a substring

### The About-instance section lists your home instance's meta communities

- **Given** I open the Communities tab and my home instance has detectable meta
  communities
- **When** the tab loads
- **Then** an "About `<instance name>`" section appears above the regular feeds and
  subscribed list, showing the high-confidence meta communities first

### Favourite a meta community, signed out

- **Given** I am browsing signed out and the About-instance section is showing
- **When** I tap the star on a listed community
- **Then** it is favourited locally (no sign-in or network round trip required)

### Tap the bell on a meta-row to be notified of its new posts

- **Given** the About-instance section is showing a meta community, and I have not yet
  followed it for new posts
- **When** I tap the bell on that row
- **Then** the bell fills in to show a live "Notify About New Posts" follow was created
  for that community
- **And** this works the same whether I'm signed in or browsing signed out, and is
  independent of whether the row's Favourite star or Subscribe button has been tapped

### Subscribe is gated to being signed in

- **Given** I am signed in and viewing the About-instance section
- **When** I tap Subscribe on a listed community
- **Then** it is added to my Subscribed feed through the normal optimistic subscribe
  flow
- **And** signed out, no Subscribe control is shown on these rows at all — only
  Favourite and the notify bell, both of which remain available

### Low-confidence meta communities sit under a disclosure

- **Given** my home instance has both high- and low-confidence meta communities
  detected
- **When** I view the About-instance section
- **Then** the high-confidence ones are listed directly and the low-confidence ones are
  reachable by expanding "More on this instance"

### The instance-detail screen shows any viewed instance's meta communities

- **Given** I open the instance-detail screen for an instance (not necessarily my home
  one) whose meta communities Spud has classified, and the app has a default account
- **When** the screen loads
- **Then** an "About this instance" card appears above its Communities card, listing
  those meta communities with the high-confidence ones first

### Favourite a meta community from the instance-detail long-press menu

- **Given** the instance-detail screen's About this instance card is showing a row
- **When** I long-press it and choose "Add to Favorites"
- **Then** it's favourited locally, the same as tapping the star in the Communities
  tab's own About section — no sign-in or network round trip required

### Subscribe from the instance-detail menu is sign-in gated, not hidden

- **Given** I'm browsing signed out and long-press a meta-community row on the
  instance-detail screen
- **When** I choose "Subscribe"
- **Then** the sign-in gate appears instead of a doomed subscribe attempt — unlike the
  Communities tab's About section, which simply omits the Subscribe control when signed
  out

### Blocking from the instance-detail menu also removes a live notify follow

- **Given** a meta-community row I'm notify-following shows on the instance-detail
  screen
- **When** I long-press it, choose "Block Community", and confirm
- **Then** the community is blocked and its "Notify About New Posts" follow is also
  removed, same as every other block entry point

## Not supported / out of scope

- **No meta section on the plain "browse all communities" list.** The screen that opens
  first when you tap an instance name (banner, description, communities) has no "About
  this instance" card — only the deeper instance-detail screen (reached from its health
  card, or from the instance picker) does; that plain list's rows keep whatever badging
  they already had.
- **No directory-classified fallback before an account exists.** The instance-detail
  card is simply absent until the app has a default account (signed in or browsing
  signed out) — there's no substitute drawn from the bundled directory in the meantime.
- **No auto-subscribe, auto-favourite, or auto-follow.** Every action is a manual,
  one-tap choice; detecting a community as meta never changes your subscriptions,
  favourites, or notify follows on its own.
- **No exhaustive scan of an instance's communities.** Detection checks a fixed,
  bounded list of likely candidate names against the instance rather than scanning
  every community it hosts, so an oddly-named meta community that isn't in that
  candidate list may not appear in the About-instance section (though it will still be
  badged if you come across it in a list, since the badge is computed independently of
  this candidate list).
- **No curated per-instance override list.** Detection is purely heuristic (name-match
  + keywords) — there's no hand-maintained map of "this instance's meta community is
  named X".
