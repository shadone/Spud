# Profile banner editing

- **Date:** 2026-06-30
- **Status:** design — pending implementation
- **Surfaces:** `iphone`, `ipad`
- **Targets touched:** `Spud`, `SpudDataKit`
- **Replaces/updates docs:** the profile-editing capability doc under `docs/features/` (Edit Profile) + README capability table + by-area map

## Summary

Let a signed-in user set and remove their **profile banner** image from the Edit
Profile screen, and show that banner in the Account tab header so it matches the
public person profile (which already renders it). The work is almost entirely a
reuse of the avatar editing pipeline that already ships: image pick → JPEG encode
→ pict-rs upload → URL → `saveUserSettings`. One new field (`banner`) is threaded
through the existing save + optimistic-mirror + `getSite`-reconcile flow.

## Background — what already exists (verified)

- **Image upload pipeline is live and proven.** `LemmyApi.uploadImage` (pict-rs
  multipart) → `LemmyServiceType.uploadImage(imageData:fileName:mimeType:) -> URL`
  (`LemmyService.swift:215`, impl `:1620`). Used today by avatar editing
  (`EditProfileViewModel.uploadAvatar`) and the new-post composer
  (`NewPostViewModel.uploadImage:262`).
- **Avatar image editing is fully implemented** in `EditProfileView` /
  `EditProfileViewModel`: `PhotosPicker(matching: .images)` → `loadTransferable(Data)`
  → `jpegData(0.85)` → `uploadImage` → set `avatarUrl` + `avatarEdited = true` →
  on `save()` send `avatar` to `saveProfile`.
- **`SaveUserSettings.banner` already exists** in LemmyKit
  (`LemmyApi+SaveUserSettings.swift:54`, a `banner: String?` wired to the generated
  call). **No LemmyKit change is needed.**
- **`PersonRecord.bannerUrl: String?` column exists** (`Person.swift:19`).
- **Banner display already works** on the public person profile:
  `PersonHeaderView.bannerImageView` (100pt tall, full-width, avatar overlapping
  its bottom edge — `PersonHeaderView.swift:125–271`), driven by
  `PersonViewModel.bannerUrl` from `PersonRecord.bannerUrl`.
- **Gaps:** the Edit Profile form has no banner field; `LemmyService.saveProfile`
  (`:1096`) and `AccountImporter.setAccountProfile` (`:215`) don't carry/mirror
  `banner`; `AccountEditableProfile` (the seed struct) has no `bannerUrl`; and the
  Account tab header (`AccountView`) shows only the avatar/name/handle (no banner).

## Goals

- Edit Profile lets the user pick a new banner and remove an existing one.
- The Edit Profile header is a **live preview**: full-width banner with the
  circular avatar overlapping its bottom edge (mirrors the person-profile header).
- The banner persists via the same path as the avatar: `saveUserSettings(banner:)`,
  optimistic local mirror to `PersonRecord.bannerUrl`, then `getSite` reconcile.
- The **Account tab header** shows the banner, matching the public profile.
- Accessible and snapshot-covered.

## Non-goals (this iteration)

- **No in-app cropping / aspect-ratio editor.** Parity with avatar: upload the
  picked image as-is at JPEG 0.85; the header frame `aspectFill`-crops it. (A crop
  UI is a separable future enhancement, applicable to avatar too.)
- **Not routed through the outbox.** Profile saves use the shipped optimistic
  mirror + `getSite` reconcile (same as avatar/display-name today), not
  `OutboxService`/`ComposerOutboxService`.
- **No banner on other surfaces** beyond Account tab + the already-rendered person
  profile (e.g. no banner in comment/post author rows).

## Design

### Data layer (SpudDataKit) — thread one `banner` field

1. **`AccountEditableProfile`**
   (`SpudDataKit/Services/AppDatabase/Records/AccountEditableProfile.swift`): add
   `bannerUrl: String?`. Seed it from `PersonRecord.bannerUrl` in
   `AppDatabase.accountEditableProfileSync(forKeychainId:)`.
2. **`LemmyServiceType` + `LemmyService.saveProfile`**
   (`LemmyService.swift:100`/`:1096`): add a `banner: String?` parameter and pass
   it to `api.saveUserSettings(... banner: banner ...)`. Keep the existing
   parameters and ordering; `banner` follows the `avatar` convention (empty string
   = clear).
3. **`AccountImporter.setAccountProfile`** (`:215`): add `banner: String?`; in the
   GRDB write set `person.bannerUrl = banner.flatMap { $0.isEmpty ? nil : $0 }`
   (exactly the avatar pattern at `:252`). The subsequent `fetchSiteInfo()`
   reconcile overwrites with the server's canonical value.

### UI (Spud app)

4. **`EditProfileViewModel`**: add `bannerUrl: URL?` and `bannerEdited: Bool`
   seeded from `AccountEditableProfile.bannerUrl`. Add `uploadBanner(imageData:)`
   and `removeBanner()` as near-copies of `uploadAvatar`/`removeAvatar` (filename
   `banner-<UUID>.jpg`, set `bannerEdited = true`). In `save()`, when
   `bannerEdited`, compute `bannerToSend = bannerUrl?.absoluteString ?? ""` and pass
   `banner: bannerToSend` to `saveProfile`.
5. **`EditProfileView`**: replace the top of the form with a **live-preview
   header**: a full-width banner image (`aspectFill`, ~person-profile proportions,
   ≈100pt) with the circular avatar overlapping its bottom edge. Both the banner
   and the avatar are `PhotosPicker` targets (two separate pickers); each offers a
   **Remove** affordance (e.g. a context menu / overflow). A neutral placeholder
   fill shows when no banner is set (match how `PersonHeaderView` handles a nil
   banner). Keep the existing avatar picker behavior; it just moves into this header.
6. **`AccountView` header**: add the banner behind/above the avatar + name + handle,
   styled to match the public person-profile header. Reuse `PersonHeaderView`'s
   visual approach where practical (DRY — extract a shared banner+avatar header
   piece if the duplication is non-trivial; otherwise mirror its constraints).

### Image handling

Pick → `loadTransferable(type: Data.self)` → `UIImage.jpegData(compressionQuality:
0.85)` → `uploadImage(imageData:fileName:mimeType: "image/jpeg")` → URL. Remove →
send `""`. No resizing/cropping beyond JPEG re-encode (parity with avatar). Display
is `aspectFill` clipped to the header frame.

### Data flow (banner change)

```
pick image → Data → jpegData(0.85) → uploadImage (pict-rs) → URL
           → bannerUrl set, bannerEdited = true
tap Save   → saveProfile(banner: url.absoluteString or "")
           → api.saveUserSettings(banner:)
           → setAccountProfile mirror: person.bannerUrl = url|nil
           → fetchSiteInfo() reconcile (canonical my_user)
GRDB observations refire → editor preview, Account tab header, and person
profile all reflect the new banner.
```

### Error handling

Reuse the avatar path's handling: an `uploadImage` failure surfaces the editor's
existing error state (no partial save — `bannerEdited` only flips on a successful
upload that yields a URL). A `saveProfile` failure surfaces the existing save-error
path. Removing a banner offline behaves like any profile save offline today (the
existing behavior is unchanged — this feature adds no new offline semantics).

## Testing

Unit (`SpudDataKitTests`, Swift Testing; in-memory `AppDatabase` + API fake):
- `saveProfile(banner:)` forwards `banner` to the `saveUserSettings` fake.
- `setAccountProfile(banner:)` writes `PersonRecord.bannerUrl`; empty string → nil.
- `accountEditableProfileSync` seeds `bannerUrl` from `PersonRecord`.

Snapshot (`SpudSnapshots`, iPhone 17 Pro / iOS 26.3.1 reference, or a pinned
device config): Edit Profile live-preview header (with banner + placeholder) and
the Account tab header (with banner + placeholder), light + dark.

Accessibility (designed in, verified deliberately): the banner exposes a label +
action ("Profile banner, double-tap to change") and its Remove action is labeled;
the avatar keeps its label; Dynamic Type unaffected (header is image + existing
text). VoiceOver order: banner, avatar, then the form fields.

## Files (anticipated)

Modified — SpudDataKit:
- `Services/AppDatabase/Records/AccountEditableProfile.swift` — `bannerUrl` field + seed.
- `Services/Lemmy/LemmyService.swift` — `saveProfile(banner:)` (protocol + impl).
- `Services/AppDatabase/Importers/AccountImporter.swift` — `setAccountProfile(banner:)` mirror.

Modified — Spud (app):
- `Scenes/Account/EditProfile/EditProfileViewModel.swift` — banner state + upload/remove + save.
- `Scenes/Account/EditProfile/EditProfileView.swift` — live-preview banner+avatar header.
- `Scenes/Account/EditProfile/ProfileAvatarView.swift` — if the avatar view is reshaped for the header overlap.
- `Scenes/Account/AccountView.swift` (+ header subview) — show the banner.

Possibly new — Spud (app):
- A shared `ProfileBannerHeader` view if the Edit Profile and Account/Person
  headers can DRY the banner+overlapping-avatar layout (decide during planning;
  only extract if duplication is real).

`make project` (XcodeGen) after adding any new file.

## Docs to update on completion

- The profile-editing capability doc under `docs/features/` — add banner editing
  to behavior + a Given/When/Then scenario (set banner, remove banner, see it on
  the Account tab and person profile).
- `docs/features/README.md` — capability table + by-area map.

## Open risks

- **Banner+avatar header DRY:** the Edit Profile header, the Account tab header,
  and `PersonHeaderView` all want the same banner+overlapping-avatar layout. Prefer
  one shared view; if `PersonHeaderView`'s UIKit shape doesn't transplant cleanly
  into the SwiftUI `EditProfileView`/`AccountView`, accept a small, well-bounded
  duplication rather than a forced abstraction.
- **Snapshot determinism:** header renders a remote image; snapshot fixtures must
  use a local/nil image (placeholder) or a stubbed image so refs are stable (no
  async network load), per the project's snapshot conventions.
