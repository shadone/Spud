# App icon

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — switching works; the alternate icon art is placeholder, to be replaced with final art
- **Related:** [themes-and-accent.md](themes-and-accent.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Settings → Appearance → App Icon shows the default Home Screen icon plus four alternates as a swatch grid. Tapping one applies it as the device's app icon. The current icon is reflected with a selection ring and checkmark, and a failure to switch surfaces an alert. The art shipped today is placeholder "potato" variations; the switching mechanism itself is fully wired.

## Behavior and rules

- **Five choices.** Potato (the default, asset-catalog icon) plus Midnight, Forest, Sunset, and Mono. The default and each alternate render as a preview swatch in the grid.
- **Selecting one switches the Home Screen icon.** Tapping a swatch calls `UIApplication.setAlternateIconName(_:)` — the alternate's name for the four variants, or `nil` to restore the default. The four alternates are declared in the app's `Info.plist` (`CFBundleAlternateIcons`) with their icon files bundled, and the flow needs no special entitlement.
- **Optimistic with rollback.** The tapped swatch is selected immediately with a haptic; if the system reports an error, the selection rolls back to the previous icon, a warning haptic fires, and a "Couldn't Change Icon" alert shows the error. On success a success haptic fires.
- **Current selection is read back.** On appearing, the screen resolves the active icon from `UIApplication.alternateIconName` (no alternate set maps to the default) and shows the ring + checkmark on that swatch.
- **No-op on re-tap.** Tapping the already-selected icon does nothing.
- **Placeholder art.** The alternate icons are placeholder variations on the app's motif; the picker footer states this. The switching behavior above is real and shipped regardless.

## Scenarios

### Switch to an alternate icon

- **Given** Settings → Appearance → App Icon with Potato selected
- **When** I tap the Midnight swatch
- **Then** the system app icon changes to Midnight
- **And** the Midnight swatch gains the selection ring and checkmark

### Restore the default icon

- **Given** an alternate icon is selected
- **When** I tap Potato
- **Then** the default app icon is restored via a nil alternate name

### A failed switch rolls back

- **Given** the icon picker
- **When** applying an icon fails
- **Then** the selection reverts to the previous icon and a "Couldn't Change Icon" alert is shown

### The current icon is reflected on open

- **Given** an alternate icon is already active
- **When** I open the App Icon screen
- **Then** that icon's swatch shows the ring and checkmark

## Not supported / out of scope

- The shipped alternate icons are placeholder art; final designs are pending. This is an art note only — switching is fully functional.
- There are five fixed choices; there is no custom/photo icon or per-theme automatic icon.
- Icon selection is independent of the in-app theme and accent — switching the app icon does not change the in-app appearance, and vice versa.
