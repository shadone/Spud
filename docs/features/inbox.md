# Inbox

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Mark inbox items read](inbox-mark-read.md), [Private messages](private-messages.md), [Background unread refresh](background-unread-refresh.md), [Replying](replying.md), [Reminders](reminders.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

The Inbox is a tab that gathers everything addressed to your account: replies to your
posts and comments, @-mentions of you, private-message conversations, and your own
[reminders](reminders.md) — including standing follows on a post's comments or a
community's new posts. A segmented control switches between four scopes — Replies,
Mentions, Reminders, Messages — and the active scope's list is shown below it. Unread
items are visually distinct, and the count of all unread items (including fired-unseen
reminders) rides as a numeric badge on the Inbox tab, kept live. The Inbox requires a
signed-in account; signed out, it shows a sign-in prompt instead of content.

## Behavior and rules

- **Four scopes, one segmented control.** The control has Replies / Mentions / Reminders / Messages. Selecting a segment swaps which list is displayed; switching among Replies/Mentions/Messages is instant because those three scopes are loaded up front, not lazily per tap. The Reminders scope is likewise always ready — it's a standing local GRDB observation, not a fetch (see [Reminders](reminders.md)).
- **All scopes load together.** Opening the Inbox (and each later appearance) loads replies, mentions, and conversations in parallel, and refreshes the unread count. Each scope tracks its own loading / loaded / error phase, so one scope failing does not blank the others.
- **Replies and mentions are comment rows.** Each shows the author, the comment body, and an "in `<community>` · `<post title>`" context line. Tapping a row opens that comment's post in the post detail (and marks the row read — see [Mark inbox items read](inbox-mark-read.md)). These rows also support swipe-to-mark-read.
- **Messages is a conversation list.** Private messages are grouped per correspondent into conversations, newest thread first, each row showing the correspondent's name, avatar, and the latest message as a preview. Tapping a row opens the DM thread (see [Private messages](private-messages.md)). DM conversations are marked read by opening the thread, not by swipe.
- **Unread items stand out.** An unread reply/mention shows a blue dot, a tinted row background, and a semibold author name; an unread conversation shows a blue dot and a bolder name. Read items render plain.
- **Unread badge on the tab.** The Inbox tab's badge shows the total unread count for the active account, or no badge when the total is zero. The count comes from the server's unread-count endpoint plus the local fired-and-unseen reminder count, is held by `UnreadCountService` as observable state, and the badge updates live whenever either contribution changes — on load, on marking items read, after sending, when a reminder fires or is seen, and on returning to the app. On a v3 instance the server portion is the sum of the per-kind counts (replies + mentions + private messages); on a native-v4 instance the server reports a single combined total with no per-kind breakdown — the reminder count blends into that total either way (see [Reminders](reminders.md)).
- **Backend-neutral: works natively on both Lemmy v3 and v4.** The inbox reads whichever API the home instance speaks. On a Lemmy 0.19.x (v3) instance it uses the per-kind endpoints (replies, mentions, and — for the Messages scope — private messages, each carrying its own read id). On a Lemmy 1.0+ (native v4) instance it uses the unified notification inbox (filtered per scope), and each item is marked read by its notification id. The three scopes, rows, unread styling, and badge are identical either way — the wire difference is invisible to the user.
- **Pull-to-refresh.** The Inbox list has a pull-to-refresh control that reloads all three scopes and the unread count.
- **Per-appearance refresh.** Returning to the Inbox tab reloads all scopes so newly-arrived items appear and the badge stays accurate, without a manual pull.
- **Empty and error states.** A loaded-but-empty scope shows a per-scope empty placeholder (no replies / no mentions / no messages). A failed load shows a "Couldn't load" state prompting a pull to refresh.
- **Signed-out gate.** Without a signed-in account the Inbox shows a "Sign in to use your inbox" placeholder, the mark-all-read button is hidden, and no scope is fetched.
- **Instance capability gate (now dormant for Lemmy).** The Inbox has a capability-gated "Inbox isn't available yet" explanatory state, but it no longer triggers on any Lemmy version: Spud speaks the native v4 inbox, so a Lemmy 1.0 instance loads the inbox normally. The gated state and its mechanism are retained (for non-Lemmy software or a future gap) but do not fire for Lemmy today — see [Instance capability gating](instance-capability-gating.md).

## Scenarios

### Switch between scopes

- **Given** I am signed in and on the Inbox tab
- **When** I tap the Mentions segment
- **Then** the list switches to my mentions immediately
- **And** the previously-loaded replies and messages remain loaded behind their segments

### Unread items are visually distinct

- **Given** my Replies scope contains read and unread replies
- **When** I view the list
- **Then** unread replies show a blue dot, a tinted background, and a bolder author name
- **And** read replies render plain

### The tab badge reflects unread count

- **Given** I have unread inbox items
- **When** I look at the Inbox tab
- **Then** its badge shows the total number of unread replies, mentions, and messages
- **And** the badge clears when that total reaches zero

### Tapping a reply opens its post

- **Given** a reply in the Replies scope
- **When** I tap the row
- **Then** the comment's post opens in the post detail
- **And** the reply is marked read

### Pull to refresh reloads the inbox

- **Given** I am viewing the Inbox
- **When** I pull the list down
- **Then** all three scopes and the unread count are reloaded from the server

### An empty scope shows a placeholder

- **Given** I have no mentions
- **When** I view the Mentions scope
- **Then** an empty-state icon, title, and message are shown

### Signed out shows a sign-in prompt

- **Given** I am signed out
- **When** I open the Inbox tab
- **Then** a "Sign in to use your inbox" placeholder is shown
- **And** no replies, mentions, or messages are fetched

## Not supported / out of scope

- The Inbox is signed-in only. There is no signed-out inbox.
- Inbox content is transient: it is fetched on demand and held in memory, not persisted. The durable signal is the unread count, not the item list.
- Only the first page of each scope is fetched (a fixed page size); there is no infinite scroll or "load more" within an inbox scope.
- There is no unread-only filter toggle — each scope fetches all items, read and unread.
- Marking items read and mark-all-read are documented in [Mark inbox items read](inbox-mark-read.md); composing and reading DM threads in [Private messages](private-messages.md).
- This is distinct from marking *posts* read in a feed, which is a separate feature ([Marking posts read and hiding read posts](mark-read-and-hiding.md)).
