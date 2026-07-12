//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Top-of-thread "Load earlier messages" affordance for a DM thread.
///
/// A DM thread grows upward (newest at the bottom), so the control that pulls in
/// older history belongs at the TOP, above the oldest message. It shows a
/// tappable button, or an in-progress spinner while a load is running.
///
/// The header keeps a CONSTANT height across the button and spinner states (the
/// button stays in the Auto Layout even while hidden), so a load toggling
/// button↔spinner never changes the header height mid-prepend — which would
/// otherwise shift the scroll-anchor the view controller restores when older
/// rows are inserted above the reading position.
final class DMLoadEarlierHeaderView: UIView {
    /// Invoked when the user taps the button.
    var onTap: (() -> Void)?

    private lazy var button: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = NSLocalizedString(
            "Load earlier messages",
            comment: "DM thread: button that fetches older conversation history"
        )
        config.image = UIImage(systemName: "arrow.up")
        config.imagePadding = 6
        config.buttonSize = .small
        // Dynamic Type: resolve the title font against the current content-size
        // category. UIButton re-runs this transformer when the category changes,
        // so the label scales without a manual observer.
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = UIFont.preferredFont(forTextStyle: .subheadline)
            return updated
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        button.accessibilityHint = NSLocalizedString(
            "Loads older messages in this conversation.",
            comment: "DM thread: accessibility hint for the load-earlier button"
        )
        return button
    }()

    private lazy var spinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        return spinner
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(button)
        addSubview(spinner)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            // The spinner overlays the button's slot so the two states occupy the
            // same footprint (constant header height).
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Switch between the tappable button and an in-progress spinner. The button
    /// stays in the layout while hidden, so the header height is unchanged.
    func setLoading(_ isLoading: Bool) {
        button.isHidden = isLoading
        if isLoading {
            spinner.startAnimating()
            // While loading, present the header as a single, non-interactive
            // progress element rather than exposing the now-hidden button.
            isAccessibilityElement = true
            accessibilityLabel = NSLocalizedString(
                "Loading earlier messages",
                comment: "DM thread: accessibility announcement while older history loads"
            )
            accessibilityTraits = [.notEnabled, .updatesFrequently]
        } else {
            spinner.stopAnimating()
            // Hand accessibility focus back to the button itself.
            isAccessibilityElement = false
        }
    }

    @objc
    private func handleTap() {
        onTap?()
    }
}
