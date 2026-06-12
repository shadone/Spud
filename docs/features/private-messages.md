# Private messages

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Inbox](inbox.md), [Mark inbox items read](inbox-mark-read.md), [Background unread refresh](background-unread-refresh.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Private messages are read and sent in a chat-style thread reached from the Inbox's Messages
scope. Each thread shows messages as left/right bubbles with an inline compose bar pinned
above the keyboard. Typing and sending posts a new message to the correspondent, and opening
a thread marks the correspondent's unread messages read. Sending requires a signed-in
account.

## Behavior and rules

- **Conversations come from the Messages scope.** The Inbox groups private messages per correspondent; tapping a conversation row pushes its thread. The thread opens with the messages already grouped for that correspondent (oldest first) — it does not refetch on open.
- **Chat bubbles.** Your own messages align right with an accent fill; the correspondent's align left with a neutral fill. Whether a message is outgoing is decided by comparing its author to your account's person id (falling back to "not the correspondent" when your id is unknown).
- **Compose bar.** A growing text view plus a circular send button sit in an input bar pinned above the keyboard. Send is disabled while the text is empty (whitespace-only counts as empty) and while a send is in flight; a spinner replaces the send button during a send.
- **Send path.** Sending trims the text, posts it via the private-message API, and appends the server-returned message to the thread, keeping the list ordered by time. The compose field clears on tapping send.
- **Marks read on open.** Opening a thread marks every unread message *from the correspondent* read and decrements the unread badge by that many. Your own sent messages are never counted as unread.
- **Auto-scroll.** The thread scrolls to the newest message when it appears and again whenever a message is sent or arrives in the list.
- **Empty thread.** A conversation with no messages shows a "No messages yet — say hello" placeholder; the compose bar is still available.
- **Sign-in gate on send.** Sending while signed out is rejected by the service (it throws an authentication error) and surfaces as an error alert; nothing is appended.
- **Send failures surface an alert.** A failed send shows an error alert and clears the in-flight state so you can retry; the unsent text is not re-populated.

## Scenarios

### Open a conversation

- **Given** a conversation in the Inbox Messages scope
- **When** I tap it
- **Then** its thread opens showing the messages as chat bubbles
- **And** unread messages from the correspondent are marked read and the badge updates

### Outgoing vs incoming bubbles

- **Given** a thread with messages from me and from the correspondent
- **When** I view it
- **Then** my messages align right with an accent fill and theirs align left with a neutral fill

### Send a message

- **Given** an open thread and some typed text
- **When** I tap send
- **Then** the message is posted to the correspondent and appended to the thread
- **And** the compose field clears and the thread scrolls to the newest message

### Send is disabled until there is text

- **Given** an open thread with an empty compose field
- **When** I look at the send button
- **Then** it is disabled until I type non-whitespace text

### Sending while signed out fails

- **Given** I am signed out
- **When** I attempt to send a message
- **Then** the send is rejected and an error alert is shown
- **And** no message is appended

### A failed send can be retried

- **Given** a send that fails on the server
- **When** the error returns
- **Then** an alert is shown and the in-flight spinner clears
- **And** I can type and send again

## Not supported / out of scope

- There is no way to start a brand-new conversation from the Messages list; threads are reached from existing conversations grouped from the inbox. (A DM is also sendable to a user from elsewhere in the app, but the Messages scope itself lists existing correspondents only.)
- The thread shows the messages it was opened with and does not re-fetch on open or paginate older history; only what the inbox grouped for that correspondent is shown.
- Messages cannot be edited, deleted, or reported from the thread, and there are no read receipts or typing indicators.
- Message bodies are shown as plain text in bubbles; no inline Markdown rendering, attachments, or media in DMs.
- Marking conversations read happens by opening their thread, not from the Messages list — see [Mark inbox items read](inbox-mark-read.md).
