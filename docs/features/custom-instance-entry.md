# Custom instance entry

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Instance picker](instance-picker.md), [Login](login.md), [Registration](registration.md), [Instance software detection](instance-software-detection.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Lets you type the address of a Lemmy instance that isn't in the bundled/Explorer
directory — most commonly a private, non-federated server — and continue straight to
the normal sign-in or sign-up flow for it. Reachable both from first-run onboarding and
from the instance picker, so it works the same way whether you're creating your first
account or adding another one.

## Behavior and rules

- **Two entry points, one screen.** A "Enter instance address" row sits directly on the
  first-run "Pick your home base" screen (a sibling to "Browse all servers"), and an
  "Add your own instance" row sits at the top of the instance picker ("Choose an
  instance") used both by onboarding's "Browse all servers" and by the add-account
  picker. Both open the same address-entry screen.
- **One field, client-side only.** The screen is a single "Instance address" field
  (placeholder `lemmy.example.com`) and a "Continue" button, disabled until the field
  has plausible input. There is no network probe before Continue — a private or
  firewalled instance that won't answer a reachability check must still be enterable.
- **Accepts the same address shapes as everywhere else in Spud.** A bare host
  (`lemmy.example.com`), an `https://` URL, a trailing slash, and a `host:port` form are
  all normalized to the same instance.
- **A typo shows a validation error, not a login attempt.** Empty input, obvious junk,
  and a single word with no dot (a common typo shape) are rejected inline ("Enter a
  valid instance address, like lemmy.example.com.") without ever attempting to reach the
  network.
- **Continuing opens the normal login screen.** A valid address pushes the same login
  screen every other instance uses, complete with its Register / browse-anonymously
  shortcuts — a typed instance is not a second-class entry, it's a bare host handed to
  the identical flow. See [Login](login.md) and [Registration](registration.md).
- **Sign-up stays available.** The typed instance's real registration mode isn't known
  without contacting it, so the login screen's Register shortcut is always shown for a
  typed instance; the sign-up request itself is the real gate against a closed instance.
- **An unreachable host shows a connection error, not "wrong password."** If the typed
  address doesn't resolve or doesn't answer (offline, DNS failure, timeout), the login
  or sign-up attempt reports "Couldn't connect to `<host>`. Check the address and your
  connection." — not the credentials error normally shown for a rejected username/password.
  A rejected login or sign-up (the instance actually answered and said no) still shows
  the credentials / rejection message as usual.
- **The non-Lemmy software block still applies.** Like every other instance, Spud
  checks the typed host's software before login/register; a confirmed non-Lemmy host
  (Mastodon, PieFed, etc.) is blocked with the same "Open in Safari" sheet used
  elsewhere. That check is fail-open, so an unreachable/undetermined probe never blocks
  a legitimate private instance. See [Instance software detection](instance-software-detection.md).

## Scenarios

### Sign in to a private instance during onboarding

- **Given** I am on the first-run "Pick your home base" screen
- **When** I tap "Enter instance address", type my private instance's address, and tap
  Continue
- **Then** the login screen for that instance opens and I can sign in

### Add a second account on a typed instance

- **Given** I already have an account and open the add-account instance picker
- **When** I tap "Add your own instance", type an address, and tap Continue
- **Then** the login screen for that instance opens, ready to sign in a second account

### Sign up on a typed instance

- **Given** the login screen reached from a typed instance address
- **When** I tap Register and complete the sign-up form
- **Then** the account is created on that instance the same way as any directory instance

### A typo shows a validation error

- **Given** the address-entry screen
- **When** I type something that isn't a plausible instance address (e.g. a single word
  with no dot, or leave the field empty) and tap Continue
- **Then** an inline error explains the address looks invalid, and no login attempt is made

### An unreachable host shows a connection error

- **Given** the login screen for a typed instance that is offline or misspelled
- **When** I attempt to sign in or sign up
- **Then** I see "Couldn't connect to `<host>`. Check the address and your connection."
  — not a wrong-password message

### A confirmed non-Lemmy host is still blocked

- **Given** the login screen for a typed address that Spud has confirmed runs non-Lemmy
  software
- **When** I attempt to sign in
- **Then** the existing "Open in Safari" block sheet appears, same as for a directory
  instance

## Not supported / out of scope

- No reachability/handshake probe before Continue — validation is address-shape only,
  by design (a private/firewalled instance must not be false-blocked).
- No way to save or bookmark a typed address for later reuse beyond the account it signs
  into; re-entering the same instance later means retyping it (unless it has since
  appeared in the Explorer directory).
- Does not attempt to fetch or display the instance's name, icon, or stats before you
  continue — those are directory-only decorations; a typed instance shows just its host.
