# New post

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Markdown editor](markdown-editor.md), [Image upload](image-upload.md), [Draft persistence](draft-persistence.md), [Community screen](community-screen.md), [Sign-in gate on write actions](sign-in-gate.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Create a new post in a community from a sheet composer. The composer has a community picker, a title field, a Text / Link / Image type selector, an optional URL field, an optional markdown body editor, an "Attach image" button, and an NSFW toggle. Post is enabled once there is a title and a chosen community. On success the sheet dismisses and the app navigates to the new post. Creating a post requires being signed in.

## Behavior and rules

- **Three post types.** A `Text / Link / Image` segmented control selects the post type. The type only changes which inputs are emphasised — `Text` hides the URL field; `Link` and `Image` show it. The underlying create request is the same shape regardless of type (`title`, optional `url`, optional `body`, `nsfw`).
- **Community picker.** Tapping the community button opens a search-driven picker. Typing a query searches communities (debounced) and tapping a result fills the target community, shown on the button as `name@instance`. When the composer is launched from a community screen, that community is pre-filled.
- **Title is required.** Post is enabled only with a non-whitespace title, a chosen community, and no in-flight upload or submission. The body and URL are optional.
- **NSFW toggle.** A switch marks the post NSFW; it is sent with the create request.
- **Image attach.** "Attach image" opens the system photo picker (`PHPickerViewController`, out-of-process, no photo-library permission prompt) and uploads the chosen image. Where the uploaded URL lands depends on the post type — see [Image upload](image-upload.md).
- **Submit then mirror.** Posting calls the Lemmy API (`createPost`); on success the server's returned `PostView` is mirrored into the local database and its post id is returned, so the new post is queryable immediately and the app navigates to it. There is no optimistic local insertion before the server confirms.
- **Signed-out gate.** The compose entry points (the feed compose button and the community screen's new-post button) gate on sign-in: a signed-out account gets a "Sign in to post" alert and the composer is not presented.
- **Failure keeps the draft.** If submission fails, an error alert is shown and the composer stays open with all fields intact so you can retry. See [Draft persistence](draft-persistence.md).
- **Launch points.** The composer is launched from the frontpage feed's compose button and from a community screen's new-post button. The frontpage button only appears on the frontpage feed (saved feeds have no single community to post to).

## Scenarios

### Create a text post

- **Given** a signed-in account and the new-post composer
- **When** I pick a community, type a title, optionally type a markdown body, and tap Post
- **Then** the post is created and the server's result is mirrored into the app
- **And** the sheet dismisses and the app navigates to the new post

### Create a link post

- **Given** the composer with the Link type selected
- **When** I enter a title, a URL, and a community, then tap Post
- **Then** the post is created with that URL

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

### A failed submission keeps the draft

- **Given** a post that fails to send
- **When** the failure occurs
- **Then** an error alert is shown and the composer stays open with my title, body, URL, community, and NSFW state intact

## Not supported / out of scope

- **No editing or deleting your own post.** The composer only creates; there is no edit or delete path for an existing post.
- **No optimistic insertion.** The new post appears only after the server confirms and its `PostView` is mirrored.
- **No cross-posting**, scheduling, or language selection.
- The markdown body editor (toolbar, live preview) is documented in [Markdown editor](markdown-editor.md); image upload mechanics are in [Image upload](image-upload.md); what survives a failed submit is in [Draft persistence](draft-persistence.md).
