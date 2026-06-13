# Acknowledgements

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [diagnostics-and-backup.md](diagnostics-and-backup.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Settings → About → Acknowledgements lists the third-party open-source projects Spud builds on, each with a short summary and its license name. The list is split into shipping dependencies and development/testing-only ones. Tapping a row opens the full canonical license text for that project.

## Behavior and rules

- **Curated static list.** The acknowledgements are a hand-maintained list baked into the app, not a build-time scrape of the dependency graph. This is intentional so each entry can carry a readable summary and the canonical license text without adding a plugin to the build.
- **Two sections.** A primary section of dependencies shipped in the app binary (for example LemmyKit, GRDB.swift, KeychainAccess, Down, the swift-openapi stack, Yams), and a separate "Development & testing" section for test-only dependencies (for example SBTUITestTunnel, swift-snapshot-testing). The test section is shown only when it is non-empty.
- **Each row shows name, summary, and license badge.** The row carries the project name, a one-line description of what it is used for, and its SPDX license identifier (MIT, Apache-2.0, BSD-2-Clause, etc.).
- **Detail shows the full license text.** Tapping a row opens a detail screen with the project's canonical license text.

## Scenarios

### Browse the acknowledgements

- **Given** Settings → About
- **When** I open Acknowledgements
- **Then** I see the shipping dependencies, each with a summary and license name
- **And** a separate Development & testing section lists test-only dependencies

### Read a project's license

- **Given** the acknowledgements list
- **When** I tap a project row
- **Then** its full license text is shown

## Not supported / out of scope

- The list is maintained by hand and baked into the app — it is not generated from the live package graph, so it reflects what the maintainer curated rather than an automatic dependency dump.
- No links out to each project's repository as a primary action; the row's action is the license text.
- No search or filtering within the acknowledgements list.
