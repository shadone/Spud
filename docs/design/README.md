# Spud — Design bundle

The staging material for a **Spud design system on claude.ai/design** ("Claude
Design"). This folder captures what's already designed and implemented so it can
be imported as the starting point, then iterated on ahead of the code.

## Contents

| File | What it is |
|---|---|
| [`DESIGN-BRIEF.md`](DESIGN-BRIEF.md) | The comprehensive brief: product, audience, the Apollo-parity north-star, brand, the full **design system** (themes, accent palette, type, density, iconography, haptics, motion) as implemented in `SpudUIKit`, information architecture, every screen, interaction patterns, accessibility, performance budget |
| [`screenshots/`](screenshots/) | 12 live screenshots of the implemented UI + a captioned index |

## Source-of-truth pointers (in the repo)

- Design tokens in code: `SpudUIKit/Theme/*` (AppTheme, AccentColor, PostDensity,
  ThumbnailPosition, AppIconVariant, ThemeManager) and `SpudUIKit/{Haptics,Theme}.swift`.
- Design north-star: [`../DESIGN.md`](../DESIGN.md).
- Feature status & behavior: the per-capability docs under [`../features/`](../features/README.md).
- Screens: `Spud/Scenes/*`.

## Importing into Claude Design (next step)

This bundle is reference material — it is **not** itself a Claude Design project.
To stand one up, build an HTML component library that mirrors §5 of the brief and
sync it with the `DesignSync` tool / `/design-sync` skill (incremental, one
component at a time). Suggested groups:

- **Foundations** — Color (semantic background tokens + 9-swatch accent palette),
  Type (Dynamic Type + text-scale/density adjustments), Spacing/Density,
  Iconography (SF Symbol set), Motion, Haptics.
- **Components** — Post cell (× density × thumbnail position), Vote control,
  Swipe-action set, Status badges, Comment cell (× depth), Composer + markdown
  toolbar, Community/Person headers, Search-result cells, Inbox cells, DM bubble,
  Media-viewer chrome, Settings rows.
- **Screens** — the inventory in `DESIGN-BRIEF.md` §7, anchored to `screenshots/`.

Once mirrored in Claude Design, keep the `SpudUIKit` tokens as the implementation
contract so design and code stay in lockstep.
