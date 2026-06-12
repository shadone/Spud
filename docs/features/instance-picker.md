# Instance picker

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Login](login.md), [Registration](registration.md), [Accounts and switching](accounts-and-switching.md), [Signed-out browsing](signed-out-browsing.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

When adding an account, Spud shows a searchable list of Lemmy instances to choose from.
Picking an instance opens the login screen for it, which is also the gateway to
registering or browsing that instance anonymously. The list is seeded with a set of
popular instances and shows each one's name, description, and icon.

## Behavior and rules

- **A "Choose an instance" list.** The picker (the site list) is presented as a modal sheet titled "Choose an instance", reached from the Account screen's Log in / Sign up buttons and the account switcher's add button. See [accounts-and-switching.md](accounts-and-switching.md).
- **Seeded with suggested instances.** On appearing, the screen populates the site list with a built-in set of popular instances (idempotently), in addition to whatever instances are already known. Each row shows the instance hostname, its description, and its icon when available.
- **Searchable.** A search bar filters the list by matching the typed text against the instance hostname or its description (case-insensitive). Clearing or dismissing search restores the full list.
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

### Pick an instance to continue

- **Given** the instance list
- **When** I tap an instance
- **Then** the login screen for that instance opens, from which I can sign in, register, or browse anonymously

## Not supported / out of scope

- No free-form "enter a custom instance URL" field — selection is from the seeded / known list only.
- The picker does not show live instance health, user counts, or open-registration status; it lists name, description, and icon.
- It does not perform sign-in or sign-up itself — it only routes to the login screen. See [login.md](login.md) and [registration.md](registration.md).
