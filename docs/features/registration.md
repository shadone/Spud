# Registration

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Login](login.md), [Instance picker](instance-picker.md), [Accounts and switching](accounts-and-switching.md), [Signed-out browsing](signed-out-browsing.md), [Custom instance entry](custom-instance-entry.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Create a new account on a chosen Lemmy instance. The sign-up form collects a username,
optional email, a password (with confirmation), an optional application answer, and an
NSFW preference. When the instance lets the account in immediately, Spud signs in and
activates it; when the instance defers the account (admin approval or email verification),
Spud explains the pending state instead.

## Behavior and rules

- **Instance chosen upstream.** Sign up is pushed from the login screen's Register button, so the instance is already fixed; the form shows which instance it's creating an account "on". See [instance-picker.md](instance-picker.md) and [login.md](login.md).
- **Non-Lemmy instances are blocked before the network call.** Before the registration request is sent, Spud probes the instance's NodeInfo. If the instance runs non-Lemmy software, an action sheet blocks the attempt and offers "Open in Safari". The probe fails open — if it cannot complete, registration proceeds as before. See [instance-software-detection.md](instance-software-detection.md).
- **Fields.** Username, email (optional), password, confirm password, an application answer ("Why do you want to join?", used by instances that require an application), and a "Show NSFW content" toggle. Sign up is enabled only when the username and password are non-empty and the password matches its confirmation.
- **Immediate sign-in path.** If the instance returns a usable credential, registration behaves like login: the credential is stored in the Keychain, the account is marked default, the initial profile fetch starts, a success haptic fires, and the flow dismisses into the app.
- **Pending states are explained, not signed in.** When the instance defers the account, no credential is stored and an alert (with a warning haptic) explains the state:
  - **Application pending** — the account awaits admin approval; you can log in once approved.
  - **Verify email** — the account needs its email verified before logging in.
  - **Generic pending** — the account isn't active yet; try logging in shortly.
- **Rejections surface the reason.** If the instance rejects the sign-up (username taken, weak password, captcha required, etc.), an alert shows the server's reason when available, or a generic "username may be taken, password too weak, or a captcha may be required" message otherwise. **A connection failure is distinguished from a rejection.** If the request never reaches the instance (unreachable host, DNS failure, timeout — most likely on a typed/custom instance, see [Custom instance entry](custom-instance-entry.md)), the alert reads "Couldn't connect to `<host>`. Check the address and your connection." instead of a generic retry message; other API failures still show the generic retry message.

## Scenarios

### Sign up and get straight in

- **Given** the sign-up form for an instance with open registration
- **When** I fill in a username, password, and matching confirmation and tap Sign up
- **Then** the account is created, signed in, made the active default, and the flow dismisses

### Sign up button gating

- **Given** the sign-up form
- **When** the username or password is empty, or the password and confirmation differ
- **Then** the Sign up button is disabled

### Application-required instance

- **Given** an instance that requires an application
- **When** I submit the form (optionally with an application answer)
- **Then** an alert explains the account is awaiting admin approval and I am not signed in

### Email-verification instance

- **Given** an instance that requires email verification
- **When** I submit the form with my email
- **Then** an alert tells me to verify my email before logging in, and I am not signed in

### Rejected sign-up

- **Given** the sign-up form
- **When** the instance rejects the registration
- **Then** an alert shows the server's reason (or a generic reason) and I can adjust and retry

### An unreachable instance shows a connection error

- **Given** the sign-up form for an instance that is unreachable (offline, DNS failure, timeout)
- **When** I submit the form
- **Then** the alert reads "Couldn't connect to `<host>`. Check the address and your connection." rather than a generic rejection message

## Not supported / out of scope

- **Captcha is not handled in-app, but this is no longer a real-world gap.** Captcha registration was removed from Lemmy server-side and modern instances cannot require one. The sign-up form still surfaces a server rejection as an error if an old instance ever returns a captcha requirement, but there is no in-app captcha solver.
- The form does not poll for approval or verification — once a pending state is shown, you return later via [login.md](login.md).
- Choosing the instance is a separate step; see [instance-picker.md](instance-picker.md).
