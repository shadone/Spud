# Private messages

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — durable + optimistic sending, GRDB-backed (offline-readable) threads, new-message compose, Markdown bodies
- **Related:** [Inbox](inbox.md), [Mark inbox items read](inbox-mark-read.md), [Drafts and Outbox](drafts-and-outbox.md), [Draft persistence](draft-persistence.md), [Replying](replying.md), [Background unread refresh](background-unread-refresh.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Private messages are read and sent in a chat-style thread reached from the Inbox's Messages
scope. Threads are stored locally, so they open instantly and are readable offline; opening a
thread refreshes it from the server in the background. Sending is **optimistic and durable**:
your message appears immediately as a "Sending…" bubble and is delivered by a background queue
that retries transient failures, resumes when the network returns, and survives an app
relaunch — the same machinery used for comments and posts. A permanent failure parks the
message (your text is kept) with tap-to-retry, and it also shows in [Drafts and Outbox](drafts-and-outbox.md).
Sending requires a signed-in account.

## Behavior and rules

- **Conversations come from the Messages scope, backed by the local store.** The Inbox groups private messages per correspondent (newest thread first, with the correspondent's unread count); tapping a conversation row pushes its thread. The list is driven by the persisted message store, so it shows immediately from cache and refreshes from the server on appear and pull-to-refresh.
- **Start a new conversation.** A compose button in the Inbox nav bar (shown in the Messages scope when signed in) opens a "New Message" recipient picker: search for a user and tap them to open a fresh thread and start typing. (You can also still start a DM by messaging a user from their profile elsewhere in the app.)
- **Markdown message bodies.** Message bodies render Markdown (bold, italic, links, inline code, code blocks, quotes, lists), like comments and posts; tapping a Lemmy user/community/post link inside a message opens it in-app, and other links open per your link settings. On your own (outgoing) bubble the text and links stay high-contrast on the accent fill.
- **Inline images in a message body.** A markdown image (`![alt](url)`) in a message body renders inline as part of the bubble's text, the same as in a post or comment (see [Post detail and comments](post-detail-and-comments.md)). It loads asynchronously, and once it arrives the bubble snaps to its new height instantly, with no animation — never a zoom-in from a corner.
- **Threads are persisted and refreshed on open.** A thread reads its messages from the local store (oldest first) — so it opens instantly and works offline — and kicks off a background fetch + import on open to reconcile with the server. A failed refresh leaves the cached messages in place rather than blanking the thread.
- **Chat bubbles.** Your own messages align right with an accent fill; the correspondent's align left with a neutral fill. Whether a message is outgoing is decided by comparing its author to your account's person id (falling back to "not the correspondent" when your id is unknown).
- **Compose bar.** A growing text view plus a circular send button sit in an input bar pinned above the keyboard. Send is enabled when the text has non-whitespace content. The in-progress text is auto-saved as a per-correspondent draft and restored when you reopen the thread (see [Draft persistence](draft-persistence.md)).
- **Optimistic, durable send.** Tapping send trims the text, clears the compose field immediately, and the message appears at once as an outgoing bubble marked "Sending…". The actual send runs in the durable background content queue (the same outbox as comments/posts); on success the confirmed server message seamlessly replaces the optimistic bubble. No awaited network call blocks the UI.
- **Multiple messages in flight.** You can send several messages in a row without waiting; each gets its own "Sending…" bubble and is delivered independently. There is no single global "sending" spinner.
- **Failure is recoverable, never lost.** A permanent failure flips the bubble to "Not delivered — tap to retry"; tapping offers Retry (re-enqueue) or Discard (drop the unsent message). The failed message is also listed in [Drafts and Outbox](drafts-and-outbox.md) for retry/discard. The text is never silently dropped.
- **Optimistic conversation list.** Sending the first message to a correspondent makes the conversation appear in the Messages list immediately; a conversation with pending or failed sends shows a "Sending…" / "Not delivered" indicator on its row. The indicator clears and the row reconciles to the real conversation once the send confirms.
- **Marks read on open.** Opening a thread marks every unread message *from the correspondent* read and decrements the unread badge by that many; returning to an already-open thread marks newly-arrived messages read too. Your own sent messages are never counted as unread.
- **Auto-scroll.** The thread scrolls to the newest message when it appears and again whenever a message is sent or arrives.
- **Empty thread.** A conversation with no messages shows a "No messages yet — say hello" placeholder; the compose bar is still available.
- **Sign-in gate on send.** Sending while signed out is rejected (the service throws an authentication error); nothing is enqueued.
- **Instance capability gate.** When the account's home instance is on Lemmy 1.0, an existing or new thread shows a gated explanatory state with its compose input disabled instead of loading or sending — see [Instance capability gating](instance-capability-gating.md).

## Scenarios

### Open a conversation

- **Given** a conversation in the Inbox Messages scope
- **When** I tap it
- **Then** its thread opens immediately from the local store showing the messages as chat bubbles, and refreshes from the server in the background
- **And** unread messages from the correspondent are marked read and the badge updates

### Send a message optimistically

- **Given** an open thread and some typed text
- **When** I tap send
- **Then** the compose field clears and my message appears immediately as an outgoing bubble marked "Sending…"
- **And** on success the bubble becomes the confirmed message with no flash or reorder

### Send several messages without waiting

- **Given** an open thread
- **When** I send two messages in quick succession
- **Then** both appear as their own "Sending…" bubbles and are delivered independently

### A failed send can be retried or discarded

- **Given** a message whose send permanently failed
- **When** I tap its "Not delivered" bubble
- **Then** I am offered Retry or Discard, and the failed message also appears in Drafts and Outbox
- **And** my text is preserved either way

### Start a new conversation appears in the list

- **Given** I send the first message to a correspondent
- **When** the message is queued
- **Then** the conversation appears in the Messages list with a "Sending…" indicator, reconciling to the real conversation once it confirms

### Start a new conversation from the Messages list

- **Given** I'm signed in, on the Inbox Messages scope
- **When** I tap the compose button, search for a user, and tap them
- **Then** a new thread opens and I can send the first message

### Markdown in a message

- **Given** a message whose body contains Markdown (e.g. **bold**, a link, a code block)
- **When** I view it in the thread
- **Then** it renders formatted (readable on both incoming and outgoing bubbles), and tapping a link opens it

### An inline image in a message loads without animating the bubble

- **Given** a message whose body contains a markdown image that hasn't finished loading yet
- **When** the image finishes loading
- **Then** the bubble snaps instantly to its new height, with no animation

### Read a thread offline

- **Given** I have previously loaded a conversation
- **When** I open it without a network connection
- **Then** the cached messages are shown; a failed refresh does not blank the thread

### Sending while signed out fails

- **Given** I am signed out
- **When** I attempt to send a message
- **Then** the send is rejected and nothing is enqueued

## Not supported / out of scope

- Older history is not paginated; the thread shows what has been imported from the server's message pages plus anything sent locally.
- Messages cannot be edited, deleted, or reported from the thread, and there are no read receipts or typing indicators.
- Message bodies render Markdown but do not support attachments or inline media uploads (a Markdown image link in a body still renders, but there's no attach-from-DM flow).
- Marking conversations read happens by opening their thread, not from the Messages list — see [Mark inbox items read](inbox-mark-read.md).
