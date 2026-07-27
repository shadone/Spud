# Themes and accent color

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [app-chrome-and-materials.md](app-chrome-and-materials.md), [display-density-and-text.md](display-density-and-text.md), [app-icon.md](app-icon.md), [swipe-actions.md](swipe-actions.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Settings → Appearance offers an app-wide theme — System, Light, or Dark — and an accent color picked from a nine-swatch palette. Both apply live the moment they are tapped: the whole interface switches appearance and retints without a relaunch, because the app window observes the preference and re-applies it. The choice is persisted and re-applied on the next launch before the window is shown, so there is no flash of the wrong appearance.

## Behavior and rules

- **Three themes.** System (follows the device setting), Light, and Dark. Each maps directly onto a standard interface style, and every color in the app is a system semantic color that resolves against it.
- **True Black is retired.** The former fourth option, a Dark variant that painted backgrounds pure black for OLED displays, no longer exists. It worked by forcing opaque bars, which is exactly what the Liquid Glass chrome now provides for itself — see [app-chrome-and-materials.md](app-chrome-and-materials.md).
- **A saved True Black selection becomes Dark.** Upgrading with True Black selected lands you on Dark, silently and on first launch. You are not reset to System and you are not asked to choose again; the closest surviving appearance is applied and persisted.
- **Nine accent colors.** Lemmy (the default, a fixed brand teal/green), Blue, Indigo, Purple, Pink, Red, Orange, Green, Teal. All but Lemmy use the system colors, which already adapt per interface style. The accent drives the window tint, so buttons, links, and controls retint across the app.
- **Live, app-wide.** Changing theme or accent updates every window immediately, with no delay and no partially-updated intermediate state — each theme maps to a distinct interface style, so the change is a single system-driven refresh.
- **Persisted and pre-applied.** The selected theme and accent are stored and applied synchronously at launch before the window appears, avoiding a flash of the wrong look.
- **Haptic on change.** Selecting a different theme or accent fires a light haptic.

## Scenarios

### Switch to Dark theme

- **Given** Settings → Appearance with the theme on System
- **When** I tap Dark
- **Then** the whole app switches to dark mode immediately, with no relaunch
- **And** the choice persists and is re-applied on the next launch

### A previously-chosen True Black becomes Dark

- **Given** I had True Black selected before updating the app
- **When** I launch the updated app
- **Then** the app is in Dark, not System, and Settings → Appearance shows Dark selected
- **And** the picker offers only System, Light, and Dark

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

- No pure-black / OLED theme. See the True Black rules above; the option was removed rather than hidden.
- The Home Screen widget does not read the theme or accent; these preferences apply to the app's own surfaces only.
- No per-account, per-community, or scheduled (e.g. sunrise/sunset) theming — the theme and accent are single global choices.
- The accent palette is a fixed curated set of nine; there is no custom color picker or hex entry.
- The theme does not change the chrome material. Bars, sheets, and floating controls are always the system Liquid Glass material; there is no opaque-bar option ([app-chrome-and-materials.md](app-chrome-and-materials.md)).
- The alternate Home Screen app icon is a separate feature, documented in [app-icon.md](app-icon.md).
