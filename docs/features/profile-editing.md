# Edit your profile

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Accounts and switching](accounts-and-switching.md), [Person / user profile](person-profile.md), [Image upload](image-upload.md), [Default sort](default-sort.md), [NSFW content visibility and blur](nsfw-content.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Edit your own account's profile and a handful of server-synced preferences from one screen, reached by tapping your profile header at the top of the [Account tab](accounts-and-switching.md). You can change your display name, bio, and avatar, and toggle the account-level settings Lemmy stores server-side (show scores, show bot accounts, show read posts, show others' avatars, and your default feed). Changes are saved to the server and reflected back into the app, so they follow your account across devices.

## Behavior and rules

- **Reached from the Account tab.** Tapping the profile header (avatar + display name + `@name@instance`) on the Account tab opens Edit Profile as a modal. It is only available for a signed-in account.
- **Identity fields.** Display name (text), bio (multi-line markdown, edited as plain text), and avatar. The fields are prefilled from your account's stored profile.
- **Avatar.** "Change Photo" picks an image (system photo picker), compresses it to JPEG, and uploads it to the instance's pict-rs (the same upload path as [Image upload](image-upload.md)); an upload spinner shows while it's in flight. "Remove Photo" clears the avatar. A missing avatar falls back to a deterministic hue tile.
- **Synced preferences.** Show scores, Show bot accounts, Show read posts, Show others' avatars, and a Default feed picker (All / Local / Subscribed). These are the `save_user_settings` fields Lemmy keeps per account; the app reads them back from the server on every site refresh.
- **Save is to the server, then refreshed.** Tapping Save pushes everything via `save_user_settings`, mirrors the new values into local storage so the screen updates immediately, then re-fetches the account's profile from the server (`getSite`) to reconcile. A Save spinner shows while in flight; a failure surfaces an error and keeps your edits so you can retry. (This is a settings-style save, not the optimistic-outbox path used for posts/comments.)
- **Signed-out is gated.** Editing requires a signed-in account; a signed-out account has no server profile to write.

## Scenarios

### Change your display name and bio

- **Given** my own account on the Account tab
- **When** I tap my profile header, edit the display name and bio, and tap Save
- **Then** the values are pushed to the server, the profile refreshes, and the screen dismisses

### Set a new avatar

- **Given** the Edit Profile screen
- **When** I tap Change Photo and pick an image
- **Then** it uploads to the instance and becomes my avatar on save (Remove Photo clears it)

### Toggle a synced preference

- **Given** the Edit Profile screen
- **When** I turn on "Show bot accounts" (or change the Default feed) and Save
- **Then** the setting is saved to my account server-side and applies on this and other devices after a sign-in / refresh

### A failed save keeps my edits

- **Given** I tap Save and the request fails
- **When** the error is shown
- **Then** my edits remain on screen so I can retry; nothing is half-applied locally

## Not supported / out of scope

- **No banner editing.** The profile banner isn't editable here (Spud doesn't surface user banners) — a possible follow-up.
- **Account-level identity only.** Email / password changes and account deletion are not part of this screen.
- **Not optimistic/durable.** Unlike post & comment edits, a profile save is a direct server write with a refresh, not queued through an outbox — a dropped connection means retry, not background delivery.
