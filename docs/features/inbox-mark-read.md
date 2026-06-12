# Marking inbox items read

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Inbox](inbox.md), [Private messages](private-messages.md), [Background unread refresh](background-unread-refresh.md), [Marking posts read and hiding read posts](mark-read-and-hiding.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Inbox items can be marked read one at a time or all at once. A reply or mention is marked
read by tapping it or by swiping it, and there is a mark-all-read button that clears the
whole inbox. Every mark-read updates the row and the unread badge immediately, then mirrors
the change to the server in the background. This is about Inbox items (replies, mentions,
private messages) — marking *posts* read in a feed is a separate feature.

## Behavior and rules

- **Optimistic, then confirm.** Marking an item read updates the local row and decrements the unread badge right away, then sends the change to the server. The visible state does not wait on the network round-trip.
- **Tap a reply/mention marks it read.** Opening a reply or mention (which navigates to its post) also marks that item read.
- **Swipe to mark read.** A trailing swipe on an unread reply or mention exposes a "Read" action (open-envelope icon). Firing it marks the item read. The swipe is offered only on unread items — a read row has no swipe action.
- **Conversations are not marked read from the list.** The Messages scope has no per-row mark-read swipe; a conversation's messages are marked read by opening the thread (see [Private messages](private-messages.md)).
- **Mark all read.** When signed in, the Inbox shows a mark-all-read button (open-envelope) in the navigation bar. It optimistically marks every loaded reply and mention read, zeroes the unread badge, then calls the server's mark-all-inbox-read endpoint and re-fetches the unread count to reflect the server's view (including private messages).
- **Badge stays in step.** Each per-item mark decrements the badge by one for its kind; mark-all-read resets the badge to zero. The badge is the `UnreadCountService` count surfaced on the Inbox tab.
- **Failures surface an alert, locally already applied.** If the server call fails, an error alert is shown; the optimistic local change has already been made, so the row stays read on screen.
- **Signed-out has nothing to mark.** The mark-all-read button is hidden when signed out, and per-item mark-read is a no-op without a signed-in account.

## Scenarios

### Swipe a reply to mark it read

- **Given** an unread reply in the Replies scope
- **When** I swipe the row and tap Read
- **Then** the row immediately shows as read and the tab badge drops by one
- **And** the change is sent to the server in the background

### Opening an item marks it read

- **Given** an unread mention
- **When** I tap it to open its post
- **Then** the mention is marked read and the badge updates

### A read item offers no mark-read swipe

- **Given** a reply that is already read
- **When** I swipe the row
- **Then** no Read action is offered

### Mark all read clears the inbox

- **Given** I am signed in with unread replies and mentions
- **When** I tap the mark-all-read button
- **Then** every loaded reply and mention shows as read and the tab badge clears
- **And** the server is told to mark the whole inbox read, after which the count is re-fetched to reflect private messages too

### A failed mark keeps the local change

- **Given** marking an item read fails on the server
- **When** the error returns
- **Then** an alert is shown
- **And** the row remains read on screen because the local change was already applied

### Signed out hides mark-all-read

- **Given** I am signed out
- **When** I open the Inbox
- **Then** the mark-all-read button is not shown

## Not supported / out of scope

- There is no mark-as-*unread* — items can only be marked read.
- Mark-all-read clears the loaded replies and mentions optimistically and asks the server to clear the whole inbox; conversations are marked read by opening their threads, not from the Messages list.
- This feature is about Inbox items only. Marking *posts* read (on open / on scroll) and hiding read posts in a feed are a separate feature ([Marking posts read and hiding read posts](mark-read-and-hiding.md)); the two share no controls.
- Marking a DM thread's incoming messages read happens automatically on opening the thread — see [Private messages](private-messages.md).
