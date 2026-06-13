# Markdown editor

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [New post](new-post.md), [Replying](replying.md), [Image upload](image-upload.md), [Draft persistence](draft-persistence.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

A reusable markdown editor shared by every compose flow: a text view with a formatting-toolbar keyboard accessory and a Write / Preview mode swap. In Write mode you edit raw markdown; in Preview mode the draft is rendered through the same markdown path that post detail and comments use, so the preview matches the final result. It is the shared component used by the comment / private-message composer (see [Replying](replying.md)) and the new-post body editor (see [New post](new-post.md)).

## Behavior and rules

- **Write / Preview toggle.** A segmented control switches the editor between Write (editable text view) and Preview (rendered markdown). Toggling modes never mutates the draft text; switching to Write and back keeps the content intact.
- **Live preview rendering.** Entering Preview re-renders the current draft with the `Down` markdown renderer using the same styler configuration as post detail, so the preview matches the rendered result exactly. Links in the preview are tappable; an empty draft shows a "Nothing to preview" placeholder.
- **Formatting toolbar.** A keyboard accessory toolbar exposes formatting buttons that scroll horizontally so the full set fits on narrow devices. The buttons are: bold, italic, strikethrough, link, quote, bulleted list, numbered list, inline code, code block, and spoiler.
- **Selection-aware transforms.** A formatting action operates on the current text selection: inline actions (bold, italic, strikethrough, link, code) wrap the selection in markers and toggle them off when already applied; line-prefix actions (quote, lists) add or strip a prefix on every line the selection touches. With no selection, a placeholder word is inserted so the marker has something to wrap. The transform logic is pure and unit-tested.
- **Haptics.** Applying a formatting action fires a light tap haptic.
- **Placeholder.** A placeholder string is shown when the editor is empty in Write mode.
- **Owns no persisted state.** The editor holds only its live text; it has no draft store of its own. What survives a dismiss or a failed submit is owned by the surrounding composer — see [Draft persistence](draft-persistence.md).

## Scenarios

### Preview rendered markdown

- **Given** the editor in Write mode with some markdown typed
- **When** I switch to Preview
- **Then** the rendered markdown is shown, matching how it will render in the thread
- **And** switching back to Write keeps my text unchanged

### Empty preview placeholder

- **Given** the editor with no content
- **When** I switch to Preview
- **Then** a "Nothing to preview" placeholder is shown

### Bold a selection

- **Given** some selected text in Write mode
- **When** I tap Bold in the toolbar
- **Then** the selection is wrapped in `**` markers and a tap haptic fires
- **And** tapping Bold again on the same wrapped text removes the markers

### Apply a line-prefix action

- **Given** one or more lines selected
- **When** I tap Quote or a list action
- **Then** the prefix is added to every line the selection touches

### Insert a marker with no selection

- **Given** no text selected
- **When** I tap a formatting action
- **Then** a placeholder word is inserted wrapped in the marker, selected for replacement

### Tap a link in the preview

- **Given** the preview showing rendered markdown that contains a link
- **When** I tap the link
- **Then** the surrounding composer handles opening it

## Not supported / out of scope

- **No WYSIWYG / rich-text editing.** Write mode edits raw markdown text; formatting is applied as markdown markers, not styled inline.
- **No autocomplete** for community / user mentions or emoji.
- **The image-attach button is part of the new-post composer**, not the editor itself — see [Image upload](image-upload.md).
- **The editor does not persist drafts**; persistence (what survives across a submit failure) belongs to the composer — see [Draft persistence](draft-persistence.md).
