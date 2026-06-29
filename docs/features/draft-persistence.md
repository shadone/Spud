# Draft persistence

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [New post](new-post.md), [Replying](replying.md), [Markdown editor](markdown-editor.md), [Image upload](image-upload.md), [Drafts and Outbox](drafts-and-outbox.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Spud auto-saves every compose session to a durable per-target draft store (GRDB `outboundContent` table, per account) so that an in-progress text is never silently lost. A draft persists across sheet dismissal, app backgrounding, and app relaunch. Reopening a composer for the same target (a given post, parent comment, or community) silently restores the previous unsent text with no user action required. A non-empty composer dismissed without posting offers a Mail-style action sheet — "Save Draft" keeps it; "Delete Draft" removes it.

## Behavior and rules

- **Per-target, per-account.** One draft slot exists for each combination of target (a post, a comment, a community) and signed-in account. Opening the same composer twice in the same session, or after a relaunch, silently restores that slot. A different account has its own independent slots.
- **Auto-saved, not manually triggered.** The draft is written to the durable store incrementally as you type; no explicit "save" action is needed.
- **Mail-style dismiss.** Dismissing a non-empty composer presents an action sheet: "Save Draft" (retains the text in the durable store), "Delete Draft" (removes it), and "Cancel" (returns to the composer). An empty composer dismisses without the action sheet.
- **Silent restore on reopen.** Reopening the composer for a target that has a saved draft silently pre-fills the text fields with no notification or banner — the text is simply there.
- **Cross-launch persistence.** Drafts survive force-quit and relaunch. The durable store is backed by the shared App Group database; draft content is not surfaced to the widget or extensions.
- **Content for new posts.** For a new post, the durable draft stores title, body, URL, NSFW flag, and post type. The community is the draft's key (which draft slot is used) but is not restored into the editor. For a comment reply or DM, it stores the body text.
- **Preview and upload do not lose the draft.** Toggling Write / Preview or attaching an image mutates the live draft in place. The in-memory state is flushed to the durable store.
- **Not shared across composer types.** Each composer target (new post, top-level reply, nested comment reply, private message, **edit of a specific comment**) has its own slot; there is no single global draft. An edit draft is keyed by the edited comment's id, so it never coalesces with a reply draft for the same post or parent.
- **Sending clears the draft.** A successful send deletes the draft from the store. A failed send parks the item as Failed in the outbox but retains the content so it can be retried or discarded from [Drafts and Outbox](drafts-and-outbox.md).

## Scenarios

### Reopening a composer restores the unsaved text

- **Given** I started typing a reply, then dismissed "Save Draft"
- **When** I tap Reply on the same post again (even after relaunching the app)
- **Then** the composer opens with my previous text already in the body

### Dismissing a non-empty composer offers Save / Delete

- **Given** I have typed some text in the composer
- **When** I tap Cancel or swipe the sheet down
- **Then** an action sheet appears with "Save Draft", "Delete Draft", and "Cancel"
- **And** tapping "Save Draft" keeps the text; tapping "Delete Draft" removes it

### Dismissing an empty composer skips the action sheet

- **Given** the composer is open with no text entered (or only whitespace)
- **When** I tap Cancel
- **Then** the sheet dismisses without prompting

### A failed send keeps the content in the outbox

- **Given** a reply that fails permanently
- **Then** the content is parked as Failed in the outbox (see [Drafts and Outbox](drafts-and-outbox.md)) and is never silently discarded

### Preview and upload do not lose the draft

- **Given** a draft being edited
- **When** I switch to Preview and back, or attach an image
- **Then** the draft content is preserved and auto-saved

### Each account has independent draft slots

- **Given** two signed-in accounts
- **When** each opens the same post's reply composer
- **Then** each sees only their own previously saved draft for that post

## Not supported / out of scope

- **No multiple concurrent drafts for the same target.** Only one draft slot exists per target per account; a later session overwrites the earlier one. (A direct message's in-progress text uses one per-correspondent draft slot like any other target; each *sent* DM is a separate durable outbox item, so several messages to one correspondent can be in flight at once — see [Private messages](private-messages.md).)
- **No draft picker or drafts list inside the composer.** The recovery surface for Failed / Sending / Draft items is the standalone [Drafts and Outbox](drafts-and-outbox.md) screen.
- **Posts are not editable.** Editing an already-posted *comment* IS supported (it opens a composer prefilled with the comment's body, with its own draft slot — see [Replying](replying.md)); editing or deleting an already-posted *post* is not.
