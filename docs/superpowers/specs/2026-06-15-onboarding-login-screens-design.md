# Onboarding & Login screens — design spec

**Goal:** Bring Spud's onboarding and login/account-entry screens up to the
Claude Design mockups (handoff bundle `~/Downloads/spud/project/`,
`onboarding.jsx` + `login.jsx` + `screens-common.jsx`). Slice A (Welcome screen
+ `MainWindow` onboarding gate) already shipped; this spec covers the remaining
designed screens.

## Design source of truth

- `onboarding.jsx` — Welcome (shipped), **HomePick** ("Pick your home base"),
  Interests, Suggestions, CreateAccount (sheet), Pending review.
- `login.jsx` — ServerPick, **LoginForm**, LoginError, LoginTwoFactor,
  ForgotPassword, AnonConfirm.
- `screens-common.jsx` — shared primitives: `PrimaryBtn` (52pt, accent fill,
  radius 14, 17pt/700 white label), `GhostBtn` (44pt, accent text), `FlowTop`
  (back chevron · step dots · Skip), `CommunityIcon`, `FollowBtn`, `BottomFade`.

The mockups are HTML/CSS prototypes; recreate the visual output natively, do not
copy prototype structure.

## Token mapping (design `T` → Spud)

The design palette is standard iOS dark semantics plus the app's teal accent, so
existing tokens cover it — no new colors:

| design `T` | value in mock | Spud token |
|---|---|---|
| `bg` | `#000000` | `Theme.background` (OLED) / `.systemBackground` |
| `elev` | `#1c1c1e` | `.secondarySystemBackground` |
| `elev2` | `#2c2c2e` | `.tertiarySystemBackground` |
| `label` | `#ffffff` | `.label` |
| `sec` | `rgba(235,235,245,0.6)` | `.secondaryLabel` |
| `ter` | `rgba(235,235,245,0.32)` | `.tertiaryLabel` |
| `hair` | `rgba(255,255,255,0.08)` | `.separator` (thin) |
| `sep` | `rgba(84,84,88,0.6)` | `.separator` |
| `a` (accent) | teal | app accent (`view.tintColor`; snapshot pins `lemmyTeal = #009687`) |

Reusable native primitives mirroring `screens-common.jsx` live in a new
`Spud/Scenes/Onboarding/OnboardingKit.swift` (PrimaryButton, GhostButton, step
indicator, instance/community avatar) so screens stay DRY and consistent with
the shipped Welcome screen's button styling.

## Screen inventory → target

| Design screen | Target | Status |
|---|---|---|
| Welcome | `OnboardingWelcomeViewController` | shipped (slice A) |
| HomePick "Pick your home base" | new `OnboardingHomeBaseViewController` (after Welcome's Get started; "Browse all servers" → existing `SiteListViewController`) | slice 2 |
| LoginForm / LoginError | rework `LoginViewController` | slice 1 |
| AnonConfirm | new `AnonymousBrowseConfirmViewController` (before `signInAsSignedOut`) | slice 3 |
| ForgotPassword | new `ForgotPasswordViewController` (LemmyKit `passwordReset`) | slice 4 |
| LoginTwoFactor | dedicated 2FA step in login (LemmyKit `login` totp token) | slice 5 |
| CreateAccount / Pending | rework `RegisterViewController` + pending-review state | slice 6 |
| ServerPick | existing `SiteListViewController` (already the picker) | reuse; light polish only |
| Interests / Suggestions | — needs curated interest taxonomy + suggested-community data + feed seeding | DEFERRED (separate initiative, overlaps Discover/Explorer) |

## Slice ordering & rationale

Build in independently shippable, snapshot-verifiable slices:

1. **Login form redesign** — most-used entry screen, self-contained, backend
   ready. Highest single-screen value.
2. **"Pick your home base"** — the key onboarding screen after Welcome; replaces
   the raw `SiteList` drop-in with the curated, de-jargoned picker.
3. **Anonymous-browse confirm** — read-only confirmation before anonymous sign-in.
4. **Forgot password** — `passwordReset` screen.
5. **Two-factor** — dedicated code-entry step.
6. **Create-account / Pending** — register redesign + application/pending state.

**Deferred:** Interests + Suggested-communities. They require an interest→community
taxonomy and suggested-community ranking that Spud does not have yet; that data
work belongs with the Discover/Community-Explorer initiative. The `FlowTop` step
indicator ("1 of 3") is therefore adapted: until interests/suggestions exist, the
home-base step does not advertise a 3-step flow.

## Per-screen visual specs (slices 1–2)

### Slice 1 — LoginForm (`login.jsx` `LoginForm`/`LoginError`)

Scrollable, `Theme.background`. Top to bottom:

- **Instance header card** (radius 14, `.separator` hairline border): a 58pt
  gradient banner; a 46pt rounded-square instance avatar (3pt bg-colored ring)
  overlapping the banner by 20pt with the host name beside it (16pt/800) and a
  teal "Change" affordance; below, a `.secondaryLabel` 12.5pt blurb line
  ("<tagline> · <members> members").
- **Fields** (`Field`): label (12pt/600 `.secondaryLabel`, 2pt left inset) over a
  48pt rounded (radius 12) `.secondarySystemBackground` field with a 1pt border —
  `.separator` normally, accent when focused, `#FF453A` on error. Password field
  shows an eye toggle. Error text (12pt `#FF453A`) under the field.
  - "Username or email", "Password".
- **Primary "Log in"** button (PrimaryButton).
- **"Forgot password?"** centered teal link (→ slice 4).
- **"New to Spud? Create an account"** centered, "Create an account" in teal/700
  (→ Register).
- **"or" divider** (hairline · "or" · hairline).
- **"Browse <instance> anonymously"** 50pt outlined row (radius 14, eye icon)
  (→ slice 3 confirm, or direct anonymous sign-in).

Error state: username border accent-less, password border `#FF453A` + "Incorrect
username or password." Error text comes from the existing `LoginViewModel` flow.

Keep all existing `LoginViewModel` wiring (icon, instanceName, login(),
loginButtonEnabled, loggedIn, anonymous sign-in, register push). 2FA field stays
hidden inline for now (slice 5 promotes it to its own screen).

### Slice 2 — HomePick (`onboarding.jsx` `HomePick`)

`Theme.background`. Back chevron top-left (pops to Welcome). Title "Pick your
home base" (27pt/800), subtitle (14.5pt `.secondaryLabel`): "It is just where
your account lives. You will still see and join every community on Spud, wherever
it is." Then:

- **Recommended instance card(s)** from the Explorer directory (top by
  `.recommended` sort): 42pt avatar, host (15.5pt/700) with a teal "RECOMMENDED"
  pill (9pt/800) when applicable, blurb (12.5pt `.secondaryLabel`), and
  "<members> members · <Open sign-up | Reviews new accounts>" (11.5pt
  `.tertiaryLabel`); accent 1.5pt border on the recommended one; chevron. Tapping
  a card → `InstanceDetailViewController` (existing "before you commit" screen).
- **"Browse all servers"** row (search icon + chevron) → existing
  `SiteListViewController`.
- **Reassurance note** (globe icon, `.secondarySystemBackground` rounded box):
  "New here? Keep the recommendation. You can change it later, and it never limits
  what you can read or join."
- **"Continue"** PrimaryButton pinned bottom → proceeds with the recommended
  instance's `InstanceDetailViewController` (or directly to login/anon for it).

Data: `appDatabase.explorerSiteListRowsSync()` / `observeExplorerSiteListRows()`,
`ExplorerInstanceSort.recommended`, `explorerInstanceSync(baseurl:)` — same
sources `SiteListViewController` already uses.

## Architecture

- New onboarding screens are plain `UIViewController`s taking the existing
  dependency compositions (e.g. `SiteListViewController.Dependencies`,
  `InstanceDetailViewController.Dependencies`). No new services.
- `MainWindow.showOnboarding()` changes (slice 2): Welcome's `onGetStarted`
  pushes `OnboardingHomeBaseViewController` instead of `SiteListViewController`;
  "Browse all servers" pushes `SiteListViewController` from there. The
  account-creation → tab-bar cross-fade (`observeDefaultAccount` →
  `swapRootToTabBar`) already shipped and is unchanged.
- Shared visual primitives in `OnboardingKit.swift`.

## Error handling

Reuse existing view-model error surfacing (`AlertService`, `LoginViewModel`
state). New network screens (forgot-password) surface failures via `AlertService`
and inline messages per the mocks.

## Testing

Each slice ships snapshot tests pinned to a device config so they are
simulator-independent, light + dark, following the shipped
`OnboardingSnapshotTests` pattern:
`assertSnapshot(matching: vc, as: .image(on: .iPhone13Pro, traits: ...))` with
`view.tintColor = lemmyTeal`. View models are fed deterministic fixtures (static
image service, in-memory `AppDatabase` seeded with Explorer rows) so renders are
stable with no async image loading. Snapshot references are recorded then
visually inspected before locking in.

## Non-goals

- Interests / suggested-communities / feed seeding (deferred, see above).
- Federation is never named in copy ("home base", "server"), per the design.
- No backend/service changes beyond wiring existing LemmyKit endpoints
  (`login` 2FA token, `passwordReset`, `register`, `getCaptcha`).
