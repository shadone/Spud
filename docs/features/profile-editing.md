# Edit your profile

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Accounts and switching](accounts-and-switching.md), [Person / user profile](person-profile.md), [Image upload](image-upload.md), [Default sort](default-sort.md), [NSFW content visibility and blur](nsfw-content.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Edit your own account's profile and a handful of server-synced preferences from one screen, reached by tapping your profile header at the top of the [Account tab](accounts-and-switching.md). You can change your display name, bio, avatar, and banner image, and toggle the account-level settings Lemmy stores server-side (show scores, show bot accounts, show read posts, show others' avatars, and your default feed). Changes are saved to the server and reflected back into the app, so they follow your account across devices.

## Behavior and rules

- **Reached from the Account tab.** Tapping the profile header (banner + avatar + display name + `@name@instance`) on the Account tab opens Edit Profile as a modal. It is only available for a signed-in account.
- **Live-preview header.** The top of the Edit Profile screen shows a full-width banner with the circular avatar overlapping its bottom edge — the same layout as the public [person profile](person-profile.md) header. Both images are live: changes made in the editor are reflected immediately in this preview. On a regular-width iPad the banner is width-capped and centered rather than stretching full-bleed across the screen width.
- **Identity fields.** Display name (text), bio (multi-line markdown, edited as plain text), avatar, and banner. The fields are prefilled from your account's stored profile.
- **Banner.** Tapping the banner area opens the system photo picker; the picked image is compressed to JPEG and shown immediately in the live-preview header. A long-press or context menu on the banner offers Remove, which clears it. A neutral placeholder fill shows when no banner is set. No in-app cropping: the image is uploaded as-is and the header frame crops it to fit.
- **Avatar.** Tapping the circular avatar area opens the system photo picker and compresses to JPEG (the same encode path as [Image upload](image-upload.md)); the picked image appears in the preview header instantly, with no network round-trip — it is uploaded once, on Save. A long-press or context menu offers Remove, which clears the avatar. A missing avatar falls back to a deterministic hue tile.
- **Synced preferences.** Show scores, Show bot accounts, Show read posts, Show others' avatars, and a Default feed picker (All / Local / Subscribed). These are the account settings Lemmy keeps per account; the app reads them back from the server on every site refresh.
- **Avatar and banner are pushed to the server on Save — exactly once.** Picking an image only previews it locally and stashes its bytes; the upload happens when you tap Save, and removing either clears it server-side — so the change follows your account across devices, not just on this device. (Picking no longer uploads a throwaway preview copy that orphaned a file on the instance every time; the image is sent a single time, at Save.) Newer instances (Lemmy 1.0) use dedicated profile-image endpoints; older instances upload to pict-rs and store the resulting URL. A failed Save — including its image upload — surfaces an error inline without clearing the field, so you can retry. Removing the banner or avatar offline behaves like any profile save offline — the existing error path applies (no new offline semantics).
- **Save is to the server, then refreshed.** Tapping Save pushes everything — the avatar/banner images first (via the dedicated profile-image endpoints), then the text and preference fields — mirrors the new values into local storage so the Account tab header and the public person profile update immediately, then re-fetches the account's profile from the server (`getSite`) to reconcile. A Save spinner shows while in flight; a failure surfaces an error and keeps your edits so you can retry, with nothing half-applied server-side (the image push runs before the local mirror, so a failed push rolls back to your previous images on the next refresh). (This is a settings-style save, not the optimistic-outbox path used for posts/comments.)
- **Signed-out is gated.** Editing requires a signed-in account; a signed-out account has no server profile to write.
- **Instance capability gate.** When the signed-in account's home instance is on Lemmy 1.0, tapping the profile header shows an explanatory action sheet instead of opening the editor — see [Instance capability gating](instance-capability-gating.md).

## Scenarios

### Change your display name and bio

- **Given** my own account on the Account tab
- **When** I tap my profile header, edit the display name and bio, and tap Save
- **Then** the values are pushed to the server, the profile refreshes, and the screen dismisses

### Set a new avatar

- **Given** the Edit Profile screen
- **When** I tap the circular avatar and pick an image
- **Then** the live-preview header reflects the new image immediately (no upload happens yet); it uploads to the instance and becomes my avatar on Save
- **And** a context menu on the avatar offers Remove, which clears it on save

### Set a profile banner

- **Given** the Edit Profile screen
- **When** I tap the banner area in the live-preview header and pick an image
- **Then** the preview header shows the new banner immediately (no upload happens yet)
- **And** tapping Save uploads and persists the banner to the server and the Account tab header and public person profile both show it

### Remove the profile banner

- **Given** the Edit Profile screen with an existing banner
- **When** I long-press the banner and choose Remove
- **Then** the preview header shows the placeholder fill; tapping Save clears the banner from the server and the Account tab header reverts to the placeholder

### See your banner on the Account tab and public profile

- **Given** a signed-in account that has a profile banner set
- **When** I view the Account tab
- **Then** the profile header shows the full-width banner behind the avatar, display name, and handle — matching what other users see on my public person profile

### Toggle a synced preference

- **Given** the Edit Profile screen
- **When** I turn on "Show bot accounts" (or change the Default feed) and Save
- **Then** the setting is saved to my account server-side and applies on this and other devices after a sign-in / refresh

### A failed save keeps my edits

- **Given** I tap Save and the request fails
- **When** the error is shown
- **Then** my edits remain on screen so I can retry; nothing is half-applied locally

## Not supported / out of scope

- **No in-app cropping.** The banner and avatar are uploaded as-is (JPEG re-encode only); the header frame crops them to fit. A crop UI is a possible future enhancement.
- **Account-level identity only.** Email / password changes and account deletion are not part of this screen.
- **Not optimistic/durable.** Unlike post & comment edits, a profile save is a direct server write with a refresh, not queued through an outbox — a dropped connection means retry, not background delivery.
- **Banner not shown in other contexts.** The banner appears in the Account tab header and on the public person profile; it does not appear in comment rows, post attribution lines, or inbox rows.
