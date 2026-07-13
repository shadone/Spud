# Login

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Instance picker](instance-picker.md), [Registration](registration.md), [Accounts and switching](accounts-and-switching.md), [Signed-out browsing](signed-out-browsing.md), [Custom instance entry](custom-instance-entry.md), [Session re-login hint](session-reauth.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Sign in to a Lemmy instance with a username or email and a password. The login screen is
reached after picking an instance; on success the new account is stored, its credential
saved to the Keychain, and it becomes the active default. The same screen offers
shortcuts to register a new account or to keep browsing anonymously.

## Behavior and rules

- **Instance is chosen first.** Login is pushed from the instance picker, so the screen already knows which instance it's signing in to and shows that instance's name and icon. See [instance-picker.md](instance-picker.md).
- **Non-Lemmy instances are blocked before the network call.** Before the login request is sent, Spud probes the instance's NodeInfo. If the instance runs non-Lemmy software (PieFed, Mbin, Mastodon, etc.), an action sheet blocks the attempt and offers "Open in Safari". The probe fails open — if it cannot complete, login proceeds as before. See [instance-software-detection.md](instance-software-detection.md).
- **Username or email + password.** One field accepts either a username or an email, plus a password field. The Log in button is enabled only when both fields are non-empty.
- **Success stores and activates the account.** A successful login stores the returned credential in the shared-group Keychain under a new `accountKeychainId`, marks the account default, and immediately kicks off the initial site / own-profile fetch so the Account screen resolves without waiting for the next periodic refresh. The login screen then dismisses. (This is ordinary sign-in of a new or additional account. Re-authenticating an *existing* account whose session expired reuses that account's keychain id instead of minting a new one — see [Session re-login hint](session-reauth.md).)
- **Invalid credentials surface an error.** A rejected login ("incorrect login") is reported as an invalid-login error alert; the screen stays open to retry. **A connection failure is distinguished from a credentials failure.** If the request never reaches the instance (unreachable host, DNS failure, timeout — most likely on a typed/custom instance, see [Custom instance entry](custom-instance-entry.md)), the inline error reads "Couldn't connect to `<host>`. Check the address and your connection." instead of implying the password was wrong. Other API failures surface a generic error alert.
- **Two-factor (TOTP) sign-in.** When an account has two-factor authentication enabled, the one-time code is collected on a dedicated code-entry screen and sent to the server alongside the password (as `totp_2fa_token`). The screen can be reached two ways: manually via the "Have a two-factor code?" affordance under the Log in button, or automatically — if a login is rejected because a 2FA code is missing or wrong, the app surfaces the inline hint "Enter your two-factor code." and presents the code-entry screen for you. After entering a code, the retried login carries the token. (A 2FA-required rejection is handled inline; it does not raise the generic error alert.)
- **Register and anonymous shortcuts.** The screen has a "Register" button that pushes the sign-up form for the same instance, and a "Browse without an account" button that first shows a confirmation screen; confirming activates the signed-out account for the instance and dismisses. See [registration.md](registration.md) and [signed-out-browsing.md](signed-out-browsing.md).
- **Forgot Password runs in-app.** A "Forgot Password?" affordance opens a reset screen (naming the instance, an email field, and a "Send reset link" button) that calls the server's password-reset endpoint. On success a "Check your email" confirmation is shown; a failure surfaces an error and you can retry.

## Scenarios

### Sign in with a username and password

- **Given** the login screen for a chosen instance
- **When** I enter my username and password and tap Log in
- **Then** the account is signed in, stored, made the active default, and the screen dismisses

### Sign in with an email

- **Given** the login screen
- **When** I enter my email instead of a username, plus my password, and tap Log in
- **Then** the same sign-in succeeds (the field accepts either)

### Log in button stays disabled until both fields are filled

- **Given** the login screen
- **When** either the username or password field is empty
- **Then** the Log in button is disabled

### Wrong credentials show an error

- **Given** the login screen
- **When** I submit credentials the instance rejects
- **Then** an invalid-login error alert is shown and I can retry without losing the screen

### An unreachable instance shows a connection error, not a credentials error

- **Given** the login screen for an instance that is unreachable (offline, DNS failure, timeout)
- **When** I attempt to sign in
- **Then** the inline error reads "Couldn't connect to `<host>`. Check the address and your connection." rather than the wrong-password message

### Two-factor sign-in prompts for the code

- **Given** an account with two-factor authentication enabled
- **When** I submit my username and password without a code
- **Then** the inline hint "Enter your two-factor code." appears and the two-factor code-entry screen is presented; after I enter a code and log in again, the code is sent with the password and the sign-in succeeds

### Jump to registration or anonymous browsing

- **Given** the login screen
- **When** I tap Register, or "Browse without an account"
- **Then** the sign-up form for the instance opens, or a confirmation screen appears and confirming activates the signed-out account and dismisses

## Not supported / out of scope

- No biometric unlock or credential autofill integration beyond the system keyboard's own behavior.
- Choosing the instance is a separate step — see [instance-picker.md](instance-picker.md).
