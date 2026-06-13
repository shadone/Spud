# Report

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Post detail and comments](post-detail-and-comments.md), [Sign-in gate on write actions](sign-in-gate.md), [Block / unblock](block-unblock.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Report a post or a comment to its moderators with a required free-text reason. Report is offered in the post header's context menu and in each comment's context menu, but only on other people's content. Choosing Report opens an alert with a single reason field; submitting sends the report to the server and shows a brief "Report submitted" confirmation.

## Behavior and rules

- **Posts and comments both report.** The post header's long-press menu offers Report, and each comment's long-press menu offers Report, both with a flag icon and a destructive style.
- **Only on other people's content.** Report is omitted from the menu when the post or comment is your own; reporting your own content is meaningless.
- **Required reason.** Report presents an alert with a single "Reason (required)" text field. The Report submit button stays disabled until the field is non-empty; the reason is trimmed of surrounding whitespace before it is sent.
- **Submit sends and confirms.** On submit the report is sent to the server (`createPostReport` / `createCommentReport`). On success a success haptic fires and a "Report submitted — Thanks. The moderators will review it." confirmation alert is shown. On failure an error alert is shown.
- **Signed-out is pre-gated.** While the active account is signed out, choosing Report shows a "Sign in to report" alert with a warning haptic and does not open the reason field. See [sign-in-gate.md](sign-in-gate.md).
- **No local state change.** Reporting does not hide, remove, or otherwise alter the reported post or comment in your view; it only files the report.

## Scenarios

### Report a post

- **Given** another person's post and a signed-in account
- **When** I long-press the post header and choose Report
- **Then** an alert with a required reason field appears, with Report disabled until I type a reason
- **When** I enter a reason and tap Report
- **Then** the report is sent and a "Report submitted" confirmation appears

### Report a comment

- **Given** another person's comment and a signed-in account
- **When** I long-press the comment and choose Report
- **Then** the same required-reason alert appears and submitting files the comment report

### Report is hidden on my own content

- **Given** my own post or comment
- **When** I open its context menu
- **Then** there is no Report action

### An empty reason cannot be submitted

- **Given** the report reason alert
- **When** the reason field is empty or only whitespace
- **Then** the Report button stays disabled

### Reporting while signed out is gated

- **Given** a signed-out active account
- **When** I choose Report on a post or comment
- **Then** a "Sign in to report" alert appears with a warning haptic and the reason field is not shown

## Not supported / out of scope

- No predefined reason categories or rule pickers — the reason is free text only.
- Reporting does not block, hide, or remove the content for you; use [Block / unblock](block-unblock.md) to stop seeing a person or community.
- There is no in-app view of reports you have filed or their resolution.
- Reporting a private message, a community, or a person (as opposed to a specific post / comment) is not provided.
