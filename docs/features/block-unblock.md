# Block / unblock

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Community screen](community-screen.md), [Person / user profile](person-profile.md), [Report](report.md), [Sign-in gate on write actions](sign-in-gate.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Block a person or a community so their content stops appearing in your feeds, and unblock them later. Blocking is launched from the overflow menu (or header context menu) on a person profile or a community screen, and is confirmed before it applies. Blocked people and communities are listed under Settings, where each can be unblocked with a trailing swipe. A block is sent to the server and the server's confirmed result is mirrored back into the app, so what you see matches what the server recorded.

## Behavior and rules

- **People and communities both block.** A person profile offers Block user / Unblock user; a community screen offers Block community / Unblock community. Each appears both in the screen's overflow (`...`) menu and in the header's long-press context menu.
- **Confirm before blocking, immediate unblock.** Blocking presents a destructive confirmation action sheet ("Block @user?" / "Block !community@instance?") with a warning haptic, a "Block" confirm button, and a body explaining you won't see their content and can unblock later. Confirming fires a success haptic. Unblocking is applied immediately, with no confirmation sheet.
- **Confirm-then-mirror.** The action calls the Lemmy API (`blockPerson` / `blockCommunity`) and writes the server's returned view back into the local database. The block state shown in the UI updates optimistically and reverts if the call fails.
- **Blocking a community reloads the feed.** After a community block, the community screen's embedded feed reloads so the now-server-filtered content disappears. A person block does not reload a feed from the profile (the profile has no embedded feed of its own); the server filters that author out of subsequent feed fetches.
- **Signed-out is pre-gated.** While the active account is signed out, attempting to block shows a "Sign in to block" alert with a warning haptic and makes no API call. See [sign-in-gate.md](sign-in-gate.md).
- **Failures surface an alert.** If the block / unblock call fails, an error alert is shown and the optimistic state is reverted.
- **Blocked list in Settings.** Settings shows Blocked Users and Blocked Communities (only when signed in). Each list is fetched from the server (the account's `my_user` blocks) and shows the name, federated handle, and avatar / icon per entry.
- **Swipe to unblock.** In each blocked list, a trailing swipe on a row reveals a destructive Unblock action. Unblocking removes the row optimistically and reverts it if the server call fails. Pull-to-refresh re-fetches the list.

## Scenarios

### Block a person from their profile

- **Given** a person profile that is not my own and a signed-in account
- **When** I open the overflow menu (or long-press the header) and choose Block user
- **Then** a "Block @user?" confirmation sheet appears with a warning haptic
- **When** I confirm
- **Then** the block is sent to the server, the server result is mirrored, and the action flips to Unblock user

### Block a community from its screen

- **Given** a community screen and a signed-in account
- **When** I choose Block community and confirm
- **Then** the community is blocked and its embedded feed reloads so its posts disappear

### Unblock is immediate

- **Given** a person or community I have already blocked
- **When** I choose Unblock
- **Then** the unblock is applied without a confirmation sheet

### Manage blocks in Settings

- **Given** a signed-in account with blocked people or communities
- **When** I open Settings and select Blocked Users or Blocked Communities
- **Then** the list of blocked entries is fetched from the server and shown with name and handle

### Swipe to unblock in Settings

- **Given** the Blocked Users (or Blocked Communities) list
- **When** I swipe a row from the trailing edge and tap Unblock
- **Then** the entry is removed and unblocked on the server, reverting if the call fails

### Blocking while signed out is gated

- **Given** a signed-out active account
- **When** I try to block a person or community
- **Then** a "Sign in to block" alert appears with a warning haptic and nothing is blocked

## Not supported / out of scope

- No optimistic feed change beyond the community-screen reload: a person block relies on the server filtering subsequent feed fetches rather than removing already-loaded rows in place.
- The blocked lists are not editable beyond unblock — there is no in-app way to add a block from the list, only from a profile or community screen.
- Blocking an instance / domain, muting, or per-keyword filtering are not provided.
- The Settings blocked lists are visible only when signed in; a signed-out account has no blocks and no entry point.
