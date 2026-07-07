//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import UIKit
@testable import Spud

/// Builds a `PreferencesService` backed by a fresh, private `UserDefaults`
/// suite, so a snapshot render can never depend on — or leak into — the shared
/// `.standard` (`info.ddenis.Spud`) domain that a prior test or the sim's app
/// state might have left dirty. Each call gets a unique suite, so every fixture
/// reads the documented preference defaults regardless of what ran before it.
///
/// This replaces the interim "pin `thumbnailPosition`/`showVoteButtons` to
/// their defaults" workaround: `.left`/`true` ARE those defaults, so a fresh
/// suite renders identically without the manual pins.
@MainActor
enum SnapshotPreferences {
    static func ephemeral() -> PreferencesService {
        PreferencesService(storage: UserDefaults(suiteName: "snapshot-\(UUID().uuidString)")!)
    }
}

/// A `UIWindow` whose `safeAreaInsets` are pinned to `.zero`, so a snapshot
/// rendered through `drawHierarchyInKeyWindow: true` is independent of the
/// ambient window-scene state.
///
/// swift-snapshot-testing's key-window render path reuses whichever `UIWindow`
/// is currently key (`getKeyWindow()`) and lays the view hierarchy out under
/// *that window's* safe area. A stock `UIWindow` derives its safe area from its
/// scene attachment, which an earlier snapshot suite in the same test process
/// can perturb — shifting the whole capture vertically, so a recorded reference
/// only matches the process state it was recorded in. Overriding `safeAreaInsets`
/// removes that dependency; `.zero` matches the zero-safe-area the strategy
/// already forces via its off-screen draw, so first-layout and draw-layout agree
/// and the render is byte-identical whatever ran before it. This mirrors the
/// private `Window` subclass swift-snapshot-testing uses for its own
/// non-key-window render path.
///
/// Shared by every snapshot suite that hosts a view controller on a real key
/// window and captures with `drawHierarchyInKeyWindow: true`
/// (`ActivityIPadSplitSnapshotTests`, `SummarySnapshotTests`).
final class FixedSafeAreaWindow: UIWindow {
    override var safeAreaInsets: UIEdgeInsets {
        .zero
    }
}

/// A minimal root view controller whose only job is to report its status bar
/// hidden, so installing it as a scene's key-window root pins that scene's
/// status bar to zero height. See ``SnapshotDeterminism/pinStatusBarHidden()``.
private final class StatusBarHiddenHostViewController: UIViewController {
    override var prefersStatusBarHidden: Bool {
        true
    }
}

/// Determinism helpers shared by the snapshot suites that host a view controller
/// on a real key window and capture with `drawHierarchyInKeyWindow: true`.
///
/// A live on-screen capture is exposed to three sources of frame-to-frame
/// nondeterminism that an off-screen `layer.render(in:)` capture is not:
/// in-flight `UIView` animations, layer-level *implicit* animations that ignore
/// `UIView.areAnimationsEnabled` (e.g. a `UISegmentedControl`'s selection
/// indicator), and stray scroll offsets from a mid-load layout pass. These
/// helpers neutralize all three so the pixel capture reflects the settled final
/// state regardless of timing.
@MainActor
enum SnapshotDeterminism {
    /// Pins the process-wide accent to the default (`.lemmy`) so a render can
    /// never depend on the sim's persisted accent preference.
    ///
    /// The accent leaks in through the snapshot HOST app, *outside* the
    /// ephemeral-`PreferencesService` isolation that ``SnapshotPreferences``
    /// gives each fixture: at launch the host's `MainWindow.applyAccent` reads
    /// the sim's persisted accent from `UserDefaults.standard` and calls
    /// `ThemeManager.shared.setAccent(...)`, which is a single process-global
    /// holder. Renders read that accent two ways — `ThemeManager.currentAccentColor`
    /// (the vote tints in `GeneralAppearance`, and any element that resolves the
    /// accent directly) and the window/root `tintColor` cascade (template
    /// placeholder images). A ref recorded while the sim carried a non-default
    /// accent (e.g. indigo) therefore mismatches on a clean sim, whose accent is
    /// the `.lemmy` default.
    ///
    /// Call from every snapshot class's `setUp` (runs after the host launch,
    /// before each test's render) so the accent is the default regardless of
    /// what the sim persisted. On-screen (`FixedSafeAreaWindow`) captures that
    /// exercise the `tintColor` cascade additionally pin `window.tintColor` to
    /// the brand teal where they build the window.
    static func pinAccent() {
        ThemeManager.shared.setAccent(.lemmy)
    }

    /// Pins the snapshot host scene's status bar HIDDEN so that nav-hosted and
    /// `drawHierarchyInKeyWindow` captures lay out identically regardless of
    /// whether the sim is running an interactive GUI session.
    ///
    /// **The leak.** A `UINavigationController` positions its bar (and the
    /// content inset below it) from the *global* scene `statusBarManager` —
    /// `UIApplication`'s single foreground `UIWindowScene` — NOT from the
    /// capture window's `safeAreaInsets`. So even a capture that force-zeroes
    /// its window safe area (`.image(on: .deterministicPhone)`'s off-screen
    /// `Window`, or an on-screen ``FixedSafeAreaWindow``) still inherits the
    /// host scene's status-bar height. On the reference device that height is
    /// 0 when hidden and 54 pt when visible; the visible case shifts every
    /// nav-hosted / key-window capture down one nav-bar height (~44 pt), the
    /// 2026-07-07 68-ref regression across 14 suites.
    ///
    /// **Why the refs encode HIDDEN.** The references were recorded under
    /// headless `xcodebuild` runs, where no interactive Simulator GUI session
    /// is attached and the scene reports its status bar hidden. The moment a
    /// GUI session is active (a human — or a parallel investigation — opens the
    /// Simulator app), `statusBarManager` flips to visible and the host process
    /// keeps that state until a Mac reboot. Re-recording is NOT the fix (it
    /// would poison the refs for the headless CI norm); pinning the scene state
    /// in code makes the suite immune to the GUI-session flip in either state.
    ///
    /// **The pin.** Install a `prefersStatusBarHidden` root controller on the
    /// host scene's key window, which drives `statusBarManager` to zero height.
    /// The swap is PERMANENT for the test process (no restore) and idempotent:
    /// the snapshot host app is a bare shell whose own root is never captured
    /// (every suite builds and hosts its own view controllers / windows), so
    /// leaving the host root replaced for the process lifetime is harmless and
    /// simpler than a save/restore dance. The suites' own on-screen
    /// ``FixedSafeAreaWindow``s are scene-less, so making one of them key does
    /// not disturb the host scene's pinned status bar.
    ///
    /// Call from every affected suite's `setUp` (nav-hosted `.image(on:)`
    /// captures and every `drawHierarchyInKeyWindow: true` capture) — like
    /// ``pinAccent()``, it re-asserts before each test so the suite is
    /// order-independent regardless of what ran before it (a key-window capture
    /// resets the host window's root to `nil` on teardown).
    static func pinStatusBarHidden() {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        guard let scene = windowScenes.first(where: { $0.activationState == .foregroundActive })
            ?? windowScenes.first
        else { return }

        // Prefer a window we already pinned; otherwise the scene's current key
        // window (the host app's own window). Idempotent: skip if already pinned.
        let window = scene.windows.first { $0.rootViewController is StatusBarHiddenHostViewController }
            ?? scene.windows.first { $0.isKeyWindow }
            ?? scene.windows.first
        guard let window else { return }

        if !(window.rootViewController is StatusBarHiddenHostViewController) {
            window.rootViewController = StatusBarHiddenHostViewController()
        }
        window.makeKeyAndVisible()
        window.rootViewController?.setNeedsStatusBarAppearanceUpdate()
    }

    /// A `UITraitCollection` pinning `preferredContentSizeCategory` to
    /// `.large` — iOS's out-of-the-box Dynamic Type default — for a snapshot's
    /// own explicit `traits:` argument (the `.image(size:traits:)` family; see
    /// ``ViewImageConfig/deterministicPhone`` for the `.image(on:)` family's
    /// equivalent pin).
    ///
    /// On 2026-07-06 the shared reference simulator's Dynamic Type setting was
    /// found knocked to `.medium` (one notch below `.large`), surviving Mac
    /// reboots. A snapshot's own `traits:` argument that never sets
    /// `preferredContentSizeCategory` (every pre-existing per-file `traits(_
    /// style:)` helper in this target did not) leaves that trait unspecified,
    /// so UIKit's `setOverrideTraitCollection(_:forChild:)` lets it fall
    /// through to the render's ambient trait environment — which, for an
    /// offscreen-rendered `Window` in this test process, reflects the *actual
    /// simulator's* live Dynamic Type setting rather than anything the test
    /// declared. With the sim at `.medium`, every text-bearing ref shrank
    /// ~4%, which read as unexplained host-level rendering drift rather than
    /// the real cause (sim state). Mixing this trait into a snapshot's
    /// `traits:` argument (`UITraitCollection(traitsFrom: [..., contentSizeTrait])`)
    /// makes that render immune to the sim's persisted setting regardless of
    /// what it drifts to next.
    static let contentSizeTrait = UITraitCollection(preferredContentSizeCategory: .large)

    /// Disables `UIView` animations and returns a closure that restores the
    /// previous state. Snapshot tests must render the settled *final* state, not
    /// a transient animation frame; disabling animations makes state changes
    /// applied during fixture assembly (chip / segment selection) take effect
    /// instantly rather than fading.
    ///
    /// Call at the start of a capture and invoke the returned closure (typically
    /// via `defer`) once the capture is done.
    static func disableAnimationsForCapture() -> () -> Void {
        let previous = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        return { UIView.setAnimationsEnabled(previous) }
    }

    /// Recursively removes every CoreAnimation animation from a view's whole
    /// layer tree (including layers not backed by a `UIView`, such as a
    /// `UISegmentedControl`'s selection indicator), snapping each layer to its
    /// final model value so the pixel capture is timing-independent.
    ///
    /// Needed on top of ``disableAnimationsForCapture()``: some UIKit controls
    /// kick off `CATransaction`-level implicit animations that ignore
    /// `UIView.areAnimationsEnabled`.
    static func snapAllAnimations(in view: UIView) {
        snapAllAnimations(inLayer: view.layer)
        for subview in view.subviews {
            snapAllAnimations(in: subview)
        }
    }

    private static func snapAllAnimations(inLayer layer: CALayer) {
        layer.removeAllAnimations()
        for sublayer in layer.sublayers ?? [] {
            snapAllAnimations(inLayer: sublayer)
        }
    }

    /// Resets every `UIScrollView` in the subtree to its natural top offset
    /// (`-adjustedContentInset.top`). Content that starts scrolled to the top
    /// makes this a no-op; it exists so a stray content offset (e.g. from a
    /// mid-load layout pass) can never make the pixel capture non-deterministic.
    static func pinScrollViewsToTop(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.contentOffset = CGPoint(x: 0, y: -scrollView.adjustedContentInset.top)
        }
        for subview in view.subviews {
            pinScrollViewsToTop(in: subview)
        }
    }
}
