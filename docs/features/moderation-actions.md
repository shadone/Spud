# Moderator / admin actions

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Post detail and comments](post-detail-and-comments.md), [Report](report.md), [Block / unblock](block-unblock.md), [Sign-in gate on write actions](sign-in-gate.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

When the active account moderates a post's community, or is a site admin, the post's and each comment's context menu gains a Moderation submenu of privileged actions. The submenu is gated by a capability fetched from the server when the post detail opens, so it appears only for accounts that actually have those powers. Actions are sent to the server and the server's confirmed result is mirrored back into the app.

## Behavior and rules

- **Capability-gated, fetched on open.** When the post detail appears, the account's moderation capability is fetched from the server (`fetchModerationCapability`, sourced from `getSite`'s `my_user`). It records which community ids the account moderates and whether the account is a site admin. The fetch is best-effort: a failure or a signed-out account leaves the capability at `.none`, simply hiding all mod actions.
- **Who sees the submenu.** The Moderation submenu (shield icon, "Moderation" title) is shown only when the account moderates this post's community or is a site admin (`canModerate(communityId:)`). A signed-out account, or one with neither power, never sees it.
- **Post moderation actions.** On a post the submenu offers:
  - **Remove / Restore** — remove a post (prompts for an optional reason recorded in the mod log) or restore a removed one.
  - **Lock / Unlock** — toggle whether the post accepts new comments.
  - **Pin to community / Unpin from community** — feature the post (or unfeature it) within its community.
  - **Pin to instance / Unpin from instance** — feature the post on the instance front page. This entry is admin-only; it appears only when the account is a site admin.
- **Comment moderation actions.** On a comment the submenu offers:
  - **Remove / Restore** — remove a comment (with an optional reason) or restore a removed one.
  - **Distinguish / Undistinguish** — mark a comment as a distinguished (mod) comment, or clear that.
  - **Ban from community** — ban the comment's author from this community. Offered only on other people's comments, not your own. It presents an action sheet ("Ban" or "Ban and remove content"), then prompts for an optional ban reason.
- **Moderator vs admin.** Per-community moderation (remove, lock, feature-in-community, distinguish, ban-from-community) is available to a moderator of that community or to a site admin. Featuring a post on the instance front page is the one admin-only action.
- **Reason prompts.** Remove (post and comment) and Ban present a reason field that is optional — submit stays enabled with the field blank, and a blank reason is sent as none. This differs from [Report](report.md), where the reason is required.
- **Confirm-then-mirror.** Each action calls the matching Lemmy API (`removePost`, `lockPost`, `featurePost`, `removeComment`, `distinguishComment`, `banFromCommunity`) and writes the server's returned view back into the local database. A failed action surfaces an error alert.
- **Server is the final authority.** The capability check only governs which actions are shown; the server independently rejects unauthorized actions. The data layer also rejects these writes from a signed-out account.

## Scenarios

### The Moderation submenu appears only with capability

- **Given** an account that moderates the post's community (or is a site admin)
- **When** I long-press the post header or a comment
- **Then** a Moderation submenu is offered
- **And** an account that neither moderates the community nor is an admin sees no Moderation submenu

### Remove and restore a post

- **Given** I moderate the post's community
- **When** I choose Remove and submit (optionally with a reason)
- **Then** the post is removed on the server and the result is mirrored
- **When** I later choose Restore
- **Then** the post is restored

### Lock a post

- **Given** I moderate the post's community
- **When** I choose Lock
- **Then** the post is locked and the action flips to Unlock

### Pin to instance is admin-only

- **Given** I am a site admin
- **When** I open a post's Moderation submenu
- **Then** Pin to instance / Unpin from instance is offered alongside the community pin
- **And** a moderator who is not an admin does not see the instance-pin action

### Ban a comment author from the community

- **Given** I moderate the post's community and the comment is not my own
- **When** I choose Ban from community
- **Then** an action sheet offers Ban or Ban and remove content, then prompts for an optional reason
- **And** Ban from community is omitted on my own comments

### Distinguish a comment

- **Given** I moderate the post's community
- **When** I choose Distinguish on a comment
- **Then** the comment is distinguished and the action flips to Undistinguish

### Signed-out and non-moderators see nothing

- **Given** a signed-out account, or one with no powers in this community
- **When** I open a post or comment context menu
- **Then** no Moderation submenu is present

## Not supported / out of scope

- The moderation capability is fetched once when the post detail opens; it is not live-refreshed if your roles change while the screen is open.
- No instance-level admin console (site bans, application approvals, community removal, mod-log browsing) — only the per-post / per-comment actions listed above.
- No purge (hard-delete) actions; Remove is reversible via Restore.
- Mod actions are exposed only from post detail context menus, not from the feed list, person profiles, or community screens.
- Appointing or removing moderators, editing community settings, or transferring a community are not provided.
