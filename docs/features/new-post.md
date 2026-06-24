# New post

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Markdown editor](markdown-editor.md), [Image upload](image-upload.md), [Draft persistence](draft-persistence.md), [Drafts and Outbox](drafts-and-outbox.md), [Community screen](community-screen.md), [Sign-in gate on write actions](sign-in-gate.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Create a new post in a community from a sheet composer. The composer has a community picker, a title field, a Text / Link / Image type selector, an optional URL field, an optional markdown body editor, an "Attach image" button, and an NSFW toggle. Post is enabled once there is a title and a chosen community. On submit, the sheet dismisses immediately and the app navigates to a pending post-detail screen rendered from the draft while the send runs in the durable background queue. On success the pending view is replaced in place by the real post. Creating a post requires being signed in.

## Behavior and rules

- **Three post types.** A `Text / Link / Image` segmented control selects the post type. The type only changes which inputs are emphasised — `Text` hides the URL field; `Link` and `Image` show it. The underlying create request is the same shape regardless of type (`title`, optional `url`, optional `body`, `nsfw`).
- **Community picker.** Tapping the community button opens a search-driven picker. Typing a query searches communities (debounced) and tapping a result fills the target community, shown on the button as `name@instance`. When the composer is launched from a community screen, that community is pre-filled.
- **Title is required.** Post is enabled only with a non-whitespace title, a chosen community, and no in-flight upload or submission. The body and URL are optional.
- **NSFW toggle.** A switch marks the post NSFW; it is sent with the create request.
- **Image attach.** "Attach image" opens the system photo picker (`PHPickerViewController`, out-of-process, no photo-library permission prompt) and uploads the chosen image. Where the uploaded URL lands depends on the post type — see [Image upload](image-upload.md).
- **Optimistic pending post.** Tapping Post dismisses the composer immediately and navigates to a pending post-detail screen rendered from the draft (title, body, URL) with a "Sending..." banner. The send runs in the durable background queue; no manual refresh is needed.
- **Durable background send with retry.** The send runs in a per-account background queue that retries transient failures with exponential backoff, auto-resumes when the network returns, and survives app relaunch. The pending post-detail screen remains visible while retries are in progress.
- **Success: swap in place.** When the server confirms, the pending post-detail screen is replaced in place by the real post detail (using the server's returned `PostView`) with no navigation stack change.
- **Failure: "Couldn't post" with Retry / Discard.** A permanent failure (auth error, rate limit, etc.) shows a "Couldn't post" banner on the pending post-detail screen. Tapping it offers Retry (requeue in the background queue) or Discard (remove the pending item). A non-blocking "Couldn't post — View" toast also appears and links to [Drafts and Outbox](drafts-and-outbox.md).
- **Durable draft per community.** The composer auto-saves the in-progress title, body, URL, NSFW flag, and post type to the durable draft store, keyed to the target community and signed-in account. Dismissing a non-empty composer without posting offers "Save Draft" / "Delete Draft" / "Keep Editing". Reopening the composer for the same community silently restores the draft. See [Draft persistence](draft-persistence.md).
- **Signed-out gate.** The compose entry points (the feed compose button and the community screen's new-post button) gate on sign-in: a signed-out account gets a "Sign in to post" alert and the composer is not presented.
- **Launch points.** The composer is launched from the frontpage feed's compose button and from a community screen's new-post button. The frontpage button only appears on the frontpage feed (saved feeds have no single community to post to).

## Scenarios

### Create a text post

- **Given** a signed-in account and the new-post composer
- **When** I pick a community, type a title, optionally type a markdown body, and tap Post
- **Then** the sheet dismisses and the app navigates to a pending post-detail screen marked "Sending..."
- **And** on server confirmation the pending view becomes the real post detail

### Create a link post

- **Given** the composer with the Link type selected
- **When** I enter a title, a URL, and a community, then tap Post
- **Then** the post is created with that URL and the pending post detail is shown

### Pre-filled community from a community screen

- **Given** I open the new-post composer from a community screen
- **Then** that community is already selected as the target

### Pick a community by search

- **Given** the composer with no community chosen
- **When** I tap the community button and search, then tap a result
- **Then** the community button shows `name@instance` and Post becomes available once a title is present

### Title and community gate Post

- **Given** the composer with an empty title or no community
- **Then** the Post button is disabled

### Mark a post NSFW

- **Given** the composer
- **When** I turn on the NSFW toggle and submit
- **Then** the post is created with the NSFW flag set

### Signed-out post is blocked

- **Given** a signed-out account
- **When** I tap the compose / new-post button
- **Then** a "Sign in to post" alert is shown and the composer is not presented

### A failed post shows Retry / Discard

- **Given** a pending post that has permanently failed
- **When** I tap the "Couldn't post" banner
- **Then** I am offered Retry or Discard

### Saving a draft for later

- **Given** I filled in a title and body but tapped Cancel
- **When** I choose "Save Draft"
- **Then** reopening the composer for that community (even after a relaunch) silently restores my title, body, URL, community, and NSFW state

## Not supported / out of scope

- **No editing or deleting your own post.** The composer only creates; there is no edit or delete path for an existing post.
- **Private messages.** The DM composer still uses the old blocking flow; durable/optimistic behavior is not yet supported for private messages. See [private-messages.md](private-messages.md).
- **No cross-posting**, scheduling, or language selection.
- **Dedup is not guaranteed.** If a send commits on the server but its response is lost before the app records success, and no later refresh imports the post before an auto-retry, a duplicate post may appear. This is a known rare edge case.
- The markdown body editor (toolbar, live preview) is documented in [Markdown editor](markdown-editor.md); image upload mechanics are in [Image upload](image-upload.md); draft lifecycle is in [Draft persistence](draft-persistence.md); recovery for failed items is in [Drafts and Outbox](drafts-and-outbox.md).
