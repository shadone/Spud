# App chrome and materials (Liquid Glass)

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [themes-and-accent.md](themes-and-accent.md), [media-viewer.md](media-viewer.md), [search.md](search.md), [ipad-split-view.md](ipad-split-view.md), [accessibility.md](accessibility.md), [share-as-image.md](share-as-image.md)

## What it does

Spud's chrome — navigation bars, the tab bar, sheets, popovers, and the controls that
float over full-screen media — is drawn by the system in iOS 26's Liquid Glass material.
Bars are translucent, so content tinting and scrolling underneath shows faintly through
them, and scrolling content is laid out to start below the bar and pass beneath it rather
than stopping at its edge. Spud supplies no bar colors of its own, so the chrome follows
the system's appearance and the app's Light/Dark choice automatically.

## Behavior and rules

- **The system owns bar appearance.** Spud does not set navigation-bar, tab-bar, sheet, or
  popover background colors. What you see is the standard iOS 26 material, including the
  way it reacts to what scrolls beneath it. There is no in-app setting to make bars opaque.
- **Content rests below the bar and scrolls under it.** On scrolling screens the content
  starts below the bar at rest and slides beneath the translucent material as you scroll,
  instead of being clipped to a hard edge. This was extended to the DM thread, Select
  Text, the reply composer, New post, and the pending-post screen, which previously
  stopped at the bar.
- **Floating controls over media are glass.** The media viewer's top bar and its caption
  area are one grouped glass surface, and the close / share / save buttons and the
  post-detail "jump to next comment" button use the system's glass button treatment
  rather than a hand-drawn tinted circle with a shadow.
- **Floating status chrome is glass too.** The toast bubble, the offline-download progress
  pill, the low-resolution-preview pill, and the instance screen's sticky bottom action
  bar all render on the same material.
- **Glass chrome over a fixed-dark backdrop stays dark.** Two surfaces sit permanently on
  a dark backdrop regardless of the app's appearance — the media viewer (a photo on
  black) and the Share as Image editor's stage. Their chrome is pinned to a dark
  appearance so its labels and glyphs stay legible when the app is in Light.
- **Search is the trailing tab.** Search is a system search tab: the system supplies its
  icon and localized title, positions it at the trailing end of the tab bar after Posts,
  Communities, Inbox, and Account, and separates it from the other tabs when the bar is
  compact.
- **Content is not glass.** The material is reserved for navigation and floating controls.
  Content obscurers stay opaque on purpose — the NSFW blur overlay is a solid blur, not a
  see-through material, because a spoiler that you can see through is not a spoiler. Share
  as Image cards keep their own fixed palette and are unaffected (see
  [share-as-image.md](share-as-image.md)).

## Scenarios

### Bars are translucent and content passes beneath them

- **Given** I am reading a feed or a post
- **When** I scroll
- **Then** the content slides beneath the navigation bar and tab bar, tinting the material
  rather than disappearing behind a solid fill
- **And** the bar picks up its appearance from the system, not from an app-set color

### An empty composer starts below the bar, not behind it

- **Given** I open the reply composer with no saved draft
- **When** the sheet appears
- **Then** the caret and the placeholder text rest below the navigation bar, fully visible
- **And** as I type past the visible area the text scrolls up underneath the bar

### Search sits at the end of the tab bar

- **Given** I am anywhere in the app
- **When** I look at the tab bar
- **Then** Search is the last tab, after Posts, Communities, Inbox, and Account
- **And** it carries the system's own search icon and title

### The media viewer's controls float as glass over the photo

- **Given** I have opened an image full screen
- **When** I tap once to reveal the chrome
- **Then** the close / share / save controls and the caption appear on a single grouped
  glass surface floating over the photo
- **And** pinching, panning, and paging still work anywhere the controls are not, including
  while the chrome is visible

### Media chrome stays readable with the app in Light appearance

- **Given** the app theme is Light
- **When** I open an image full screen, or open the Share as Image editor
- **Then** the chrome over the dark stage renders dark, so its white glyphs and text stay
  legible
- **And** the rest of the screen still follows the Light appearance

### Sheets and popovers use the system material

- **Surfaces:** `ipad`
- **Given** I am on the Posts tab at a regular width
- **When** I tap the feed name in the navigation bar to open the feed switcher popover
- **Then** the popover renders on the system material, with the content behind it showing
  through, rather than as a flat filled panel

## Not supported / out of scope

- **No way to turn glass off.** There is no opaque-bar or True Black option; the True Black
  theme was retired precisely because its job was forcing opaque bars (see
  [themes-and-accent.md](themes-and-accent.md)).
- **No tab-bar minimize-on-scroll, no prominent tab, and no iPad tab sidebar.** The system
  tab sidebar was evaluated and rejected: it overlaps the Posts tab's own primary column
  on iPad. The remaining items depend on APIs not available in the toolchain the app is
  currently built with.
- **The banner "extends under the sidebar" effect is inert today.** Community, person, and
  instance banners are set up to continue beneath an adjacent iPad sidebar, but the iPad
  split view tiles its columns rather than overlapping them, so there is no region to
  extend into and nothing visibly changes.
- **Contrast and transparency accessibility settings are not specially handled.** See the
  "Not supported" section of [accessibility.md](accessibility.md), which records exactly
  what has and has not been verified.
- **Some glass surfaces have no automated visual coverage.** The converted floating buttons
  and the low-resolution-preview pill rest on manual checks; this is a testing gap, not a
  behavior difference.
