# Login

- **Surfaces:** `iphone`, `ipad`
- **Status:** partial — two-factor (TOTP) sign-in is not wired up
- **Related:** [Instance picker](instance-picker.md), [Registration](registration.md), [Accounts and switching](accounts-and-switching.md), [Signed-out browsing](signed-out-browsing.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Sign in to a Lemmy instance with a username or email and a password. The login screen is
reached after picking an instance; on success the new account is stored, its credential
saved to the Keychain, and it becomes the active default. The same screen offers
shortcuts to register a new account or to keep browsing anonymously.

## Behavior and rules

- **Instance is chosen first.** Login is pushed from the instance picker, so the screen already knows which instance it's signing in to and shows that instance's name and icon. See [instance-picker.md](instance-picker.md).
- **Username or email + password.** One field accepts either a username or an email, plus a password field. The Login button is enabled only when both fields are non-empty.
- **Success stores and activates the account.** A successful login stores the returned credential in the shared-group Keychain under a new `accountKeychainId`, marks the account default, and immediately kicks off the initial site / own-profile fetch so the Account screen resolves without waiting for the next periodic refresh. The login screen then dismisses.
- **Invalid credentials surface an error.** A rejected login ("incorrect login") is reported as an invalid-login error alert; the screen stays open to retry. Other API failures surface a generic error alert.
- **Register and anonymous shortcuts.** The screen has a "Register" button that pushes the sign-up form for the same instance, and a "Browse without an account" button that activates the signed-out account for the instance and dismisses. See [registration.md](registration.md) and [signed-out-browsing.md](signed-out-browsing.md).
- **Forgot Password is informational only.** A "Forgot Password?" label is shown but does not start an in-app reset flow.

## Scenarios

### Sign in with a username and password

- **Given** the login screen for a chosen instance
- **When** I enter my username and password and tap Login
- **Then** the account is signed in, stored, made the active default, and the screen dismisses

### Sign in with an email

- **Given** the login screen
- **When** I enter my email instead of a username, plus my password, and tap Login
- **Then** the same sign-in succeeds (the field accepts either)

### Login button stays disabled until both fields are filled

- **Given** the login screen
- **When** either the username or password field is empty
- **Then** the Login button is disabled

### Wrong credentials show an error

- **Given** the login screen
- **When** I submit credentials the instance rejects
- **Then** an invalid-login error alert is shown and I can retry without losing the screen

### Jump to registration or anonymous browsing

- **Given** the login screen
- **When** I tap Register, or "Browse without an account"
- **Then** the sign-up form for the instance opens, or the signed-out account for the instance becomes active and the screen dismisses

## Not supported / out of scope

- **Two-factor (TOTP) sign-in is not functional.** A one-time-code field exists in the layout but is permanently hidden, never populated, and no TOTP value is sent with the login request — accounts that require 2FA cannot be signed in. (A `totp2faRequired` state is defined in the data layer but is not produced or handled.)
- No "forgot password" / password-reset flow runs in-app; the label does not act.
- No biometric unlock or credential autofill integration beyond the system keyboard's own behavior.
- Choosing the instance is a separate step — see [instance-picker.md](instance-picker.md).
