# Draft persistence

- **Surfaces:** `iphone`, `ipad`
- **Status:** partial — a draft survives only while its composer sheet is open (in-memory); it is not saved across dismissal or app launches
- **Related:** [New post](new-post.md), [Replying](replying.md), [Markdown editor](markdown-editor.md), [Image upload](image-upload.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

While a compose sheet is open, the in-progress draft is held in the composer's view model and is preserved across the things that would otherwise lose it: switching the markdown editor between Write and Preview, an image upload, and — most importantly — a failed submission. After a failed submit the sheet stays open with everything intact so you can retry. The draft lives only in memory for the lifetime of that sheet; closing the sheet discards it.

## Behavior and rules

- **Held in the view model, not persisted.** The draft (for a new post: title, body, URL, NSFW flag, post type, chosen community; for a comment / DM: the body text) is stored on the composer's view model. There is no on-disk draft store — nothing is written to `UserDefaults` or the database.
- **Survives a failed submit.** On a submission failure the composer returns to editing state and presents an error alert without clearing any field, so a retry starts from the same draft.
- **Survives image upload and preview toggles.** An image upload mutates the draft (URL or body) in place; toggling the markdown editor between Write and Preview never mutates the draft. Neither loses content.
- **Pre-filled, not restored.** The only thing pre-populated when a composer opens is context passed in at launch — e.g. the target community when posting from a community screen. This is a fresh seed, not restoration of a previously abandoned draft.
- **Discarded on dismiss.** Cancelling or successfully posting tears down the view model, so the draft is gone. Re-opening the composer starts empty.
- **Not shared across composers.** Each composer instance owns its own draft; there is no single global draft shared between the new-post composer, the comment composer, and the DM composer.

## Scenarios

### A failed post keeps every field

- **Given** a new-post draft with a title, body, URL, community, and NSFW set
- **When** the submission fails
- **Then** the sheet stays open and all fields are intact for a retry

### A failed reply keeps the body

- **Given** a comment or message draft that fails to send
- **When** the failure occurs
- **Then** the composer stays open with the body text intact

### Preview and upload do not lose the draft

- **Given** a draft being edited
- **When** I switch to Preview and back, or attach an image
- **Then** the draft content is preserved

### Closing the composer discards the draft

- **Given** an in-progress draft
- **When** I cancel (or dismiss) the sheet
- **Then** the draft is discarded, and re-opening the composer starts empty

### Posting from a community pre-fills the target

- **Given** I open the new-post composer from a community screen
- **Then** the community is pre-filled as launch context, not as a restored draft

## Not supported / out of scope

- **No persistence across sheet dismissal or app launches.** Drafts are in-memory only; there is no saved-drafts list, no auto-save, and no draft recovery after the sheet closes or the app is relaunched. This corrects the legacy "shipped" framing — draft persistence is limited to the lifetime of an open composer.
- **No shared/global draft** across the different composer types.
- **No multiple concurrent drafts** or a draft picker.
