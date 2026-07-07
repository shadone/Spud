# Image upload

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [New post](new-post.md), [Markdown editor](markdown-editor.md), [Draft persistence](draft-persistence.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Attach an image to a new post by picking it from the photo library and uploading it to the instance's pict-rs image backend. The upload returns a fully-qualified image URL, which is then placed into the post depending on the post type. The upload is performed with a hand-written `multipart/form-data` request to match pict-rs's wire-format contract, and a unit test covers that encoding.

## Behavior and rules

- **Photo picker.** "Attach image" in the new-post composer opens the system `PHPickerViewController` (images only, single selection). It runs out-of-process, so no photo-library permission prompt and no `NSPhotoLibraryUsageDescription` are needed.
- **Normalised to JPEG.** The picked image is re-encoded to JPEG (quality 0.85) and uploaded with a generated `upload-<uuid>.jpg` filename and `image/jpeg` MIME type, so the filename and MIME type are honest.
- **Targets pict-rs.** The upload `POST`s to the instance's `pictrs/image` endpoint, not through the generated OpenAPI client. The account's bearer token is attached as an `Authorization` header.
- **Hand-written multipart.** The body is built by hand as `multipart/form-data` with the field name `images[]` and a `filename` in the part's `Content-Disposition`, because pict-rs is strict about that format. The encoding is a pure value type and is unit-tested (`MultipartFormDataTests`).
- **Where the URL goes.** On success the returned URL is inserted into the post: for a `Link` or `Image` post it becomes the post's URL field; for a `Text` post it is appended into the markdown body as an inline image (`![](url)`).
- **Progress.** While an upload is in flight a spinner is shown next to the attach button and the attach button is disabled; the rest of the form stays editable.
- **Error handling.** A failed upload surfaces an error alert and leaves the composer in editing state with the draft intact; nothing is inserted. A signed-out account cannot upload (the upload requires a signed-in account's token).
- **Transient result.** The upload result (URL plus pict-rs delete token) is returned for use in the post; it is not mirrored into the local database.
- **Instance capability gate.** When the account's home instance is on Lemmy 1.0, tapping "Attach image" shows an explanatory action sheet instead of opening the picker; the button stays visible and enabled — see [Instance capability gating](instance-capability-gating.md).

## Scenarios

### Attach an image to an image post

- **Given** the new-post composer with the Image type selected
- **When** I tap "Attach image" and pick a photo
- **Then** the image is uploaded to pict-rs and the returned URL fills the post's URL field
- **And** a spinner shows during the upload and the attach button is re-enabled afterward

### Attach an image to a text post

- **Given** the composer with the Text type selected
- **When** I attach an image
- **Then** the uploaded URL is appended into the markdown body as an inline image

### Upload uses the pict-rs multipart contract

- **Given** an image to upload
- **When** the request is built
- **Then** the body is `multipart/form-data` with field name `images[]` and a filename in the `Content-Disposition`, and the account token is sent as a bearer header

### A failed upload keeps the draft

- **Given** an upload that fails
- **When** the failure occurs
- **Then** an error alert is shown, nothing is inserted, and the composer stays editable with my draft intact

## Not supported / out of scope

- **One image at a time.** The picker selects a single image; there is no multi-image attach.
- **Uploads happen only from the new-post composer**, not from the comment / DM composer.
- **No re-use of the pict-rs delete token in the UI.** The token is returned by the upload but there is no in-app "remove uploaded image" action.
- **No camera capture, screenshots, or paste-to-upload** — the source is the system photo picker only.
