# Themes and accent color

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [display-density-and-text.md](display-density-and-text.md), [app-icon.md](app-icon.md), [swipe-actions.md](swipe-actions.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Settings → Appearance offers an app-wide theme — System, Light, Dark, or True Black — and an accent color picked from a nine-swatch palette. Both apply live the moment they are tapped: the whole interface switches appearance and retints without a relaunch, because the app window observes the preference and re-applies it. The choice is persisted and re-applied on the next launch before the window is shown, so there is no flash of the wrong appearance.

## Behavior and rules

- **Four themes.** System (follows the device setting), Light, Dark, and True Black. System / Light / Dark map onto the standard interface styles. True Black is a Dark variant that additionally swaps the app's background tokens to pure black for OLED displays — its interface style is still dark, but the theme-aware color providers paint backgrounds black.
- **Nine accent colors.** Lemmy (the default, a fixed brand teal/green), Blue, Indigo, Purple, Pink, Red, Orange, Green, Teal. All but Lemmy use the system colors, which already adapt per interface style. The accent drives the window tint, so buttons, links, and controls retint across the app.
- **Live, app-wide.** Changing theme or accent updates every window immediately. The window sets `overrideUserInterfaceStyle` for the theme and `tintColor` for the accent, and records the choice on the shared `ThemeManager` so the dynamic color providers stay in sync.
- **Dark ↔ True Black is handled specially.** Switching between standard Dark and True Black keeps the same interface style (`.dark`), so UIKit fires no trait change on its own. The window nudges itself through an unspecified style and back to force the dynamic colors to re-resolve, so the pure-black backgrounds apply instantly. Every other transition changes the style outright and refreshes immediately.
- **Persisted and pre-applied.** The selected theme and accent are stored and applied synchronously at launch before the window appears, avoiding a flash of the wrong look.
- **Haptic on change.** Selecting a different theme or accent fires a light haptic.

## Scenarios

### Switch to Dark theme

- **Given** Settings → Appearance with the theme on System
- **When** I tap Dark
- **Then** the whole app switches to dark mode immediately, with no relaunch
- **And** the choice persists and is re-applied on the next launch

### True Black swaps backgrounds to pure black

- **Given** the theme is already Dark
- **When** I tap True Black
- **Then** the app's backgrounds become pure black while staying in dark mode
- **And** the change applies instantly even though the interface style does not change

### Change the accent color

- **Given** Settings → Appearance with the accent on Lemmy
- **When** I tap the Blue swatch
- **Then** buttons, links, and controls across the app retint to blue immediately
- **And** the selected swatch shows a ring and checkmark

### Appearance follows the system setting

- **Given** the theme is set to System
- **When** the device switches between light and dark mode
- **Then** the app follows the device appearance

## Not supported / out of scope

- The Home Screen widget does not read the theme or accent; these preferences apply to the app's own surfaces only.
- No per-account, per-community, or scheduled (e.g. sunrise/sunset) theming — the theme and accent are single global choices.
- The accent palette is a fixed curated set of nine; there is no custom color picker or hex entry.
- True Black affects only background tokens; it is not a separate high-contrast or pure-monochrome mode.
- The alternate Home Screen app icon is a separate feature, documented in [app-icon.md](app-icon.md).
