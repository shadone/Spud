//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

extension Notification.Name {
    /// Posted by `PrivacyScreenMonitor` when sensitive content appears or
    /// disappears (the 0 <-> 1 transition), so each scene's `PrivacyScreen` can
    /// re-evaluate whether to cover its window.
    static let privacyScreenSensitiveContentDidChange = Notification.Name("privacyScreenSensitiveContentDidChange")
}

/// App-wide count of how many sensitive (NSFW) surfaces are currently on screen.
///
/// A surface that shows NSFW content full-screen (the media viewer) brackets its
/// visibility with `beginSensitiveContent()` / `endSensitiveContent()`. The
/// per-scene `PrivacyScreen` reads `isShowingSensitiveContent` to decide whether
/// to cover the window for the iOS app-switcher snapshot and during screen
/// capture, so NSFW content does not leak into either.
@MainActor
final class PrivacyScreenMonitor {
    static let shared = PrivacyScreenMonitor()

    private(set) var sensitiveCount = 0

    var isShowingSensitiveContent: Bool {
        sensitiveCount > 0
    }

    func beginSensitiveContent() {
        sensitiveCount += 1
        if sensitiveCount == 1 { postChange() }
    }

    func endSensitiveContent() {
        guard sensitiveCount > 0 else { return }
        sensitiveCount -= 1
        if sensitiveCount == 0 { postChange() }
    }

    private func postChange() {
        NotificationCenter.default.post(name: .privacyScreenSensitiveContentDidChange, object: nil)
    }
}

/// Covers a window with an opaque privacy screen so NSFW content cannot leak into
/// the iOS app-switcher snapshot (taken as the scene resigns active) or a screen
/// recording / mirror (`UIScreen.isCaptured`).
///
/// The cover is shown only while a sensitive surface is on screen *and* the scene
/// is backgrounded or the screen is being captured — so the user still sees the
/// content they deliberately opened while actively using the app. iOS does not let
/// an app prevent a manual screenshot, so that case is out of scope.
@MainActor
final class PrivacyScreen {
    private weak var window: UIWindow?
    private var coverView: PrivacyCoverView?
    /// Whether the owning scene is foreground-active. The cover is suppressed while
    /// active and not captured, so deliberately-opened content stays visible.
    private var isSceneActive = true

    init(window: UIWindow) {
        self.window = window
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(stateChanged),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(stateChanged),
            name: .privacyScreenSensitiveContentDidChange,
            object: nil
        )
    }

    func sceneWillResignActive() {
        isSceneActive = false
        update()
    }

    func sceneDidBecomeActive() {
        isSceneActive = true
        update()
    }

    @objc
    private func stateChanged() {
        update()
    }

    /// Whether the privacy cover should be shown given the current state. Pure, so
    /// the policy is unit-testable without a live window or capture session.
    static func shouldCover(isSensitive: Bool, isSceneActive: Bool, isCaptured: Bool) -> Bool {
        isSensitive && (!isSceneActive || isCaptured)
    }

    private func update() {
        let isCaptured = window?.windowScene?.screen.isCaptured ?? false
        let shouldCover = Self.shouldCover(
            isSensitive: PrivacyScreenMonitor.shared.isShowingSensitiveContent,
            isSceneActive: isSceneActive,
            isCaptured: isCaptured
        )
        if shouldCover {
            showCover()
        } else {
            hideCover()
        }
    }

    private func showCover() {
        guard let window, coverView == nil else { return }
        let cover = PrivacyCoverView(frame: window.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Add as a direct window subview so it sits above the root content and any
        // presented modal (e.g. the media viewer).
        window.addSubview(cover)
        coverView = cover
    }

    private func hideCover() {
        coverView?.removeFromSuperview()
        coverView = nil
    }
}

/// The opaque placeholder shown in place of sensitive content: a solid themed
/// background with a centered "hidden" glyph, so the app-switcher snapshot and any
/// screen capture show nothing revealing.
final class PrivacyCoverView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.background
        isUserInteractionEnabled = false

        let icon = UIImageView(image: UIImage(systemName: "eye.slash.fill"))
        icon.tintColor = .tertiaryLabel
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)

        let label = UILabel()
        label.text = NSLocalizedString("Hidden for privacy", comment: "Privacy cover shown over NSFW content in the app switcher / screen recording")
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
        ])

        isAccessibilityElement = true
        accessibilityLabel = label.text
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
