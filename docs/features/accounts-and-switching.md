# Accounts and switching

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Signed-out browsing](signed-out-browsing.md), [Login](login.md), [Instance picker](instance-picker.md), [Registration](registration.md), [Sign-in gate on write actions](sign-in-gate.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Spud holds any number of accounts at once, including several on different Lemmy
instances, and lets you switch between them from an account switcher on the Account tab.
One account is always the active default; switching makes another account the default and
the whole app — feeds, inbox, search, and preferences — rebuilds for it live. Each account
carries its own instance, credentials, and sort/listing preferences.

## Behavior and rules

- **Many accounts, many instances.** Accounts are stored as rows keyed by a durable `accountKeychainId` (a string), each tied to a site and instance; a signed-in account's credential lives in the shared-group Keychain, not in the database. There is no per-instance limit and accounts on different instances coexist.
- **Exactly one default.** A single account is marked default at any time. Marking one default clears the flag on all others in the same write, so the app always has one and only one active account.
- **Switching is live and app-wide.** Selecting an account in the switcher marks it default; a database observation of the default account drives `MainWindow`, which rebuilds the tab bar (the post-list split view, Account, Search, Inbox, and Preferences tabs) for the newly active account. No app restart is needed, and a redundant re-emit of the same account does not rebuild.
- **The switcher.** The Account tab's nav bar always shows a "Switch account" button (regardless of sign-in state). It opens an Accounts list as a modal sheet: each row shows the account as `nickname@instance` (or just the instance for a signed-out account), with the active account checkmarked. Tapping a row switches to it and dismisses.
- **Adding an account.** The Accounts list has an add (`+`) button that opens the instance picker, which leads into login or sign up. This is the same add-account path the signed-out Account screen's Log in / Sign up buttons use. See [instance-picker.md](instance-picker.md), [login.md](login.md), and [registration.md](registration.md).
- **Removing an account.** In the Accounts list's edit mode (or by swipe), any account except the currently active one can be deleted; the active account is switched away from rather than deleted. Removing a signed-in account also clears its Keychain credential.
- **Logging out.** From a signed-in Account screen, Log out removes the current account and falls back to another registered account, or to a signed-out account on the same instance — so the app is never left without a default. Logout is a no-op for a signed-out account.
- **Per-account preferences.** Each account resolves its own default listing type and sort type (falling back to the site's defaults, then to All / Hot).

## Scenarios

### Switch to another account

- **Given** more than one account exists
- **When** I open the account switcher from the Account tab and tap a different account
- **Then** that account becomes the active default and the sheet dismisses
- **And** the feeds, inbox, search, and preferences rebuild for the newly active account without a restart

### The active account is checkmarked

- **Given** the account switcher is open
- **Then** the active account's row shows a checkmark and the others do not

### Add another account

- **Given** the account switcher is open
- **When** I tap the add button
- **Then** the instance picker opens, leading into login or sign up for a new account

### Remove a non-active account

- **Given** the account switcher is open and I am viewing an account other than the active one
- **When** I delete that account row
- **Then** the account (and its stored credential, if signed in) is removed and the active account is unchanged

### Removing the active account is not offered here

- **Given** the account switcher is open
- **Then** the currently active account has no delete control — switching away is the way to leave it

### Log out

- **Given** a signed-in active account
- **When** I confirm Log out from the Account screen
- **Then** that account is removed and the app falls back to another account, or to anonymous browsing on the same instance

## Not supported / out of scope

- No simultaneous multi-account views: only the single default account is active at a time; the app reflects one account, not a merged view across accounts.
- Switching accounts is by explicit selection only — there is no automatic per-feed or per-community account routing.
- Reordering accounts in the list is not supported.
- Sign-in itself (entering credentials, 2FA) is covered in [login.md](login.md); choosing an instance is [instance-picker.md](instance-picker.md).
