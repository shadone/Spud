# Instance meta communities

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — badge + the Communities-tab "About `<instance>`" section. A dedicated meta section on the instance-detail / About screen is **not** shipped (see Not supported).
- **Related:** [Discover (Community Explorer)](discover.md), [Search](search.md), [Community screen](community-screen.md), [Subscribe / unsubscribe](subscribe-unsubscribe.md), [Communities tab (subscriptions)](subscriptions-sidebar.md), [2026-07-14-instance-meta-communities-design.md](../superpowers/specs/2026-07-14-instance-meta-communities-design.md)

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
each with one-tap Favourite (and, when signed in, Subscribe) — no manual search
required to find where your instance's own announcements live.

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
- **Each row offers Favourite (always) and Subscribe (signed in only).** Favourite pins
  the community for quick access and works purely locally, so it's available even
  browsing signed out. Subscribe adds the community to your Subscribed feed and is only
  offered when signed in, since a signed-out/anonymous browse has no server-side
  subscription to change. **Nothing is auto-subscribed or auto-favourited** — every
  action is a deliberate one-tap choice.
- **Resolution and caching.** The set of meta communities for an instance is found by
  checking a fixed, bounded list of likely community names (e.g. "meta",
  "announcements", "support", "news"...) against that instance and classifying any
  hits. Results are cached per account, so the app doesn't repeat this lookup on every
  visit — it refreshes once per Communities-tab session and skips the check entirely
  while the cache is still fresh (about a day). A resolution pass that finds nothing
  (e.g. a network blip) never wipes a previously-good cached result. The badge itself
  never depends on this cache — it's computed fresh, inline, from whatever community
  data the list is already showing.

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

### Subscribe is gated to being signed in

- **Given** I am signed in and viewing the About-instance section
- **When** I tap Subscribe on a listed community
- **Then** it is added to my Subscribed feed through the normal optimistic subscribe
  flow
- **And** signed out, no Subscribe control is shown on these rows at all — only
  Favourite

### Low-confidence meta communities sit under a disclosure

- **Given** my home instance has both high- and low-confidence meta communities
  detected
- **When** I view the About-instance section
- **Then** the high-confidence ones are listed directly and the low-confidence ones are
  reachable by expanding "More on this instance"

## Not supported / out of scope

- **No dedicated meta-communities section on the instance-detail / About screen.** The
  design considered generalizing the "About `<instance>`" list to any instance's About
  screen (not just your home instance), but that surface was deferred and is not part
  of this shipped behavior — don't assume it's there.
- **No push notification on new posts.** Subscribe here means exactly what it means
  everywhere else in Spud: the community joins your Subscribed feed. Lemmy has no
  per-community push notification mechanism, and this feature does not add one —
  keeping up with a meta community still means checking your feed, the same as any
  other community.
- **No auto-subscribe or auto-favourite.** Every action is a manual, one-tap choice;
  detecting a community as meta never changes your subscriptions or favourites on its
  own.
- **No exhaustive scan of an instance's communities.** Detection checks a fixed,
  bounded list of likely candidate names against the instance rather than scanning
  every community it hosts, so an oddly-named meta community that isn't in that
  candidate list may not appear in the About-instance section (though it will still be
  badged if you come across it in a list, since the badge is computed independently of
  this candidate list).
- **No curated per-instance override list.** Detection is purely heuristic (name-match
  + keywords) — there's no hand-maintained map of "this instance's meta community is
  named X".
