# Instance picker

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Login](login.md), [Registration](registration.md), [Accounts and switching](accounts-and-switching.md), [Signed-out browsing](signed-out-browsing.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

When adding an account, Spud shows a searchable, sortable, and filterable list of Lemmy
instances to choose from. Picking an instance opens the login screen for it, which is
also the gateway to registering or browsing that instance anonymously. The list is
seeded with a set of popular instances and shows each one's name, description, icon, and
a compact stats line (total users, monthly active, all-time uptime).

## Behavior and rules

- **A "Choose an instance" list.** The picker (the site list) is presented as a modal sheet titled "Choose an instance", reached from the Account screen's Log in / Sign up buttons and the account switcher's add button. See [accounts-and-switching.md](accounts-and-switching.md).
- **Seeded with suggested instances.** On appearing, the screen populates the site list with a built-in set of popular instances (idempotently), in addition to whatever instances are already known. Each row shows the instance hostname, its description, and its icon when available.
- **Per-row stats line.** Below the description, each row shows a muted, compact stats line surfacing the metrics the list can be sorted by — total users, monthly active users, and all-time uptime (e.g. "12.3K users · 1.9K active · 99% uptime"). Counts use a locale-aware K/M abbreviation and uptime is shown as a whole-number percent. Any metric whose value is unknown is omitted (never shown as "0" or "nil"); the line is hidden entirely when no metric is known.
- **Searchable.** A search bar filters the list by matching the typed text against the instance hostname or its description (case-insensitive). Clearing or dismissing search restores the full list.
- **Sortable.** A sort menu in the navigation bar reorders the list by Recommended (Explorer score), Most users, Most active, Best uptime, or Name (A–Z). The per-row stats line makes the active sort metric visible on each row.
- **Filterable.** A filter menu toggles "Registration open" and "Hide NSFW", and offers a Language submenu. Languages are titled by their localized display name ("English", "German") and ordered by that name, not the raw code. The language list is scoped to the instances that still match the other active filters, so every offered language has at least one matching instance — turning on "Registration open" then opening Language shows only languages available among open-registration instances.
- **Feeds into login.** Selecting an instance pushes the login screen for that instance. From there you can sign in, tap Register to sign up, or choose to browse anonymously — so the picker is the shared entry point for [login.md](login.md), [registration.md](registration.md), and anonymous browsing.
- **Live updates.** The list observes the underlying site rows, so newly added or refreshed instances appear without leaving the screen.

## Scenarios

### Browse the instance list

- **Given** I am adding an account
- **When** the "Choose an instance" screen appears
- **Then** I see a list of suggested instances, each with a name, description, and icon

### Search for an instance

- **Given** the instance list is showing
- **When** I type into the search bar
- **Then** the list narrows to instances whose hostname or description matches, and clearing the search restores the full list

### Sort and filter the list

- **Given** the instance list is showing
- **When** I open the sort menu and choose Most users / Most active / Best uptime, or open the filter menu and toggle Registration open / Hide NSFW or pick a Language
- **Then** the list reorders or narrows accordingly, and each row's stats line shows the metric I sorted by

### Pick a language with results

- **Given** I have turned on "Registration open"
- **When** I open the Language submenu
- **Then** I see only languages (by their display name, e.g. "English") that have at least one open-registration instance — no language that would yield zero results

### Pick an instance to continue

- **Given** the instance list
- **When** I tap an instance
- **Then** the login screen for that instance opens, from which I can sign in, register, or browse anonymously

## Not supported / out of scope

- No free-form "enter a custom instance URL" field — selection is from the seeded / known list only.
- The per-row stats line shows total users, monthly active users, and all-time uptime; deeper live health (latency, version, moderation signals) lives on the instance detail screen, not the list. See [instance-browsing.md](instance-browsing.md).
- It does not perform sign-in or sign-up itself — it only routes to the login screen. See [login.md](login.md) and [registration.md](registration.md).
