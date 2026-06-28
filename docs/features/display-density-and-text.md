# Display density and text size

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [themes-and-accent.md](themes-and-accent.md), [post-thumbnails.md](post-thumbnails.md), [feeds-and-sorting.md](feeds-and-sorting.md), [swipe-actions.md](swipe-actions.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Settings → Display tunes how the post list looks: cell density (Comfortable or Compact), where the thumbnail sits (Left, Right, or Hidden), and a text-size override layered on top of the system Dynamic Type setting. All three apply live — the post list observes the same preferences and re-lays out its visible cells without a relaunch or a feed reload.

## Behavior and rules

- **Density: Comfortable or Compact.** Comfortable is the default, with generous cell margins and spacing. Compact tightens the margins and title/subtitle spacing and shaves the post font by one point, fitting more posts on screen.
- **Thumbnail position: Left, Right, or Hidden.** Left is the default (thumbnail leading the text). Right moves it to the trailing edge. Hidden drops the thumbnail entirely, giving the title and subtitle the full width.
- **Vote Buttons toggle.** When on (the default), explicit up/down vote arrows are shown on each post in the list. When off, they are hidden; swipe actions for voting remain available. The toggle applies live to visible cells.
- **Text size: a −3…+6 point override.** A slider adjusts the post text by whole points, from −3 to +6, relative to the system body size. The default is 0 (no override). It stacks on top of the device's Dynamic Type setting rather than replacing it; Compact density folds in its own −1 point on top of this.
- **Changes apply live.** Reassigning density, thumbnail position, vote visibility, or text size reconfigures the post list's already-visible cells immediately — there is no relaunch and no need to leave the feed.
- **Persisted.** All settings are stored and re-applied on the next launch.
- **Haptic on change.** Changing density or thumbnail position fires a light haptic.
- **Per-post comment density.** The post-detail screen has its own popover (accessed via the config button) that allows adjusting comment density for that post without leaving it. The density adjustment writes to the global `commentDensity` preference, so it also affects other open posts and future browsing.

## Scenarios

### Compact density fits more posts

- **Given** Settings → Display with density on Comfortable
- **When** I select Compact
- **Then** the post list tightens its spacing and trims the font, so more posts fit on screen
- **And** the posts already on screen re-lay out immediately, with no reload

### Move the thumbnail to the right

- **Given** the thumbnail position is Left
- **When** I select Right
- **Then** post thumbnails move to the trailing edge of each cell live

### Hide the thumbnail

- **Given** any thumbnail position
- **When** I select Hidden
- **Then** thumbnails are dropped and the title and subtitle take the full cell width

### Increase post text size

- **Given** the text-size slider at 0
- **When** I drag it to +3
- **Then** post text grows by three points on top of my Dynamic Type setting
- **And** visible cells re-lay out to the new size immediately

## Not supported / out of scope

- These preferences affect the post list cells; they do not restyle the post-detail body, comments, or other screens.
- The Home Screen widget does not read density, thumbnail position, or text size.
- The text-size override is bounded to −3…+6 points and steps in whole points; there is no free-form font-size or font-family choice.
- Thumbnail content and media badges (what the thumbnail shows) are a separate feature — see [post-thumbnails.md](post-thumbnails.md). This feature only governs the thumbnail's position.
- No per-community or per-feed density/thumbnail overrides — each setting is global.
