//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import UIKit

private let logger = Logger.app

class SwipeActionView: UIView {
    // MARK: Public

    struct Configuration {
        struct Action {
            let image: UIImage
            let backgroundColor: UIColor
            /// Localized, state-aware title used for the image view's
            /// accessibility label (the swipe glyphs are otherwise unlabeled).
            var title: String = ""
        }

        let leadingPrimaryAction: Action
        let leadingSecondaryAction: Action
        let trailingPrimaryAction: Action
        let trailingSecondaryAction: Action
    }

    let panGestureRecognizer = UIPanGestureRecognizer()
    var configuration: Configuration? {
        didSet {
            configurationUpdated()
        }
    }

    enum ActionTrigger {
        case leadingPrimary
        case leadingSecondary
        case trailingPrimary
        case trailingSecondary
    }

    var trigger: ((ActionTrigger) -> Void)?

    // MARK: UI Properties

    lazy var swipeActionContentContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var leadingSwipeActionView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .red
        return view
    }()

    lazy var leadingSwipeActionImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    lazy var trailingSwipeActionView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .green
        return view
    }()

    lazy var trailingSwipeActionImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    // MARK: Private

    private var swipeActionContentContainerLeadingConstraint: NSLayoutConstraint!

    private var leadingSwipeActionTrailingConstraint: NSLayoutConstraint!
    private var trailingSwipeActionLeadingConstraint: NSLayoutConstraint!

    /// The four content-inset constraints, kept mutable so the owning cell can
    /// retune them live when the post-density preference changes.
    private var contentLeadingConstraint: NSLayoutConstraint!
    private var contentTrailingConstraint: NSLayoutConstraint!
    private var contentTopConstraint: NSLayoutConstraint!
    private var contentBottomConstraint: NSLayoutConstraint!

    private enum ActionState {
        case none
        case primary
        case secondary
    }

    private var actionState: ActionState = .none

    // MARK: Functions

    init(
        contentView: UIView,
        margin: UIEdgeInsets,
        configuration: Configuration?
    ) {
        self.configuration = configuration

        super.init(frame: .zero)

        addSubview(leadingSwipeActionView)
        addSubview(trailingSwipeActionView)
        addSubview(swipeActionContentContainer)

        swipeActionContentContainer.addSubview(contentView)

        leadingSwipeActionView.addSubview(leadingSwipeActionImageView)
        trailingSwipeActionView.addSubview(trailingSwipeActionImageView)

        let actionImageSize: CGFloat = 40
        let actionMinWidth: CGFloat = 64

        let swipeActionContentContainerLeadingConstraint = swipeActionContentContainer
            .leadingAnchor.constraint(equalTo: leadingAnchor)
        self.swipeActionContentContainerLeadingConstraint = swipeActionContentContainerLeadingConstraint

        let leadingSwipeActionTrailingConstraint = leadingSwipeActionImageView
            .trailingAnchor.constraint(lessThanOrEqualTo: swipeActionContentContainer.leadingAnchor, constant: 0)
        self.leadingSwipeActionTrailingConstraint = leadingSwipeActionTrailingConstraint

        let trailingSwipeActionLeadingConstraint = trailingSwipeActionImageView
            .leadingAnchor.constraint(greaterThanOrEqualTo: swipeActionContentContainer.trailingAnchor, constant: 0)
        self.trailingSwipeActionLeadingConstraint = trailingSwipeActionLeadingConstraint

        contentLeadingConstraint = contentView.leadingAnchor
            .constraint(equalTo: swipeActionContentContainer.leadingAnchor, constant: margin.left)
        contentTrailingConstraint = contentView.trailingAnchor
            .constraint(equalTo: swipeActionContentContainer.trailingAnchor, constant: margin.right)
        contentTopConstraint = contentView.topAnchor
            .constraint(equalTo: swipeActionContentContainer.topAnchor, constant: margin.top)
        contentBottomConstraint = contentView.bottomAnchor
            .constraint(equalTo: swipeActionContentContainer.bottomAnchor, constant: margin.bottom)

        NSLayoutConstraint.activate([
            leadingSwipeActionView.leadingAnchor.constraint(lessThanOrEqualTo: leadingAnchor),
            leadingSwipeActionView.trailingAnchor.constraint(equalTo: swipeActionContentContainer.leadingAnchor),
            leadingSwipeActionView.topAnchor.constraint(equalTo: swipeActionContentContainer.topAnchor),
            leadingSwipeActionView.bottomAnchor.constraint(equalTo: swipeActionContentContainer.bottomAnchor),

            trailingSwipeActionView.leadingAnchor.constraint(equalTo: swipeActionContentContainer.trailingAnchor),
            trailingSwipeActionView.trailingAnchor.constraint(greaterThanOrEqualTo: trailingAnchor),
            trailingSwipeActionView.topAnchor.constraint(equalTo: swipeActionContentContainer.topAnchor),
            trailingSwipeActionView.bottomAnchor.constraint(equalTo: swipeActionContentContainer.bottomAnchor),

            leadingSwipeActionView.widthAnchor.constraint(greaterThanOrEqualToConstant: actionMinWidth),
            trailingSwipeActionView.widthAnchor.constraint(greaterThanOrEqualToConstant: actionMinWidth),

            swipeActionContentContainerLeadingConstraint,
            swipeActionContentContainer.widthAnchor.constraint(equalTo: widthAnchor),
            swipeActionContentContainer.topAnchor.constraint(equalTo: topAnchor),
            swipeActionContentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentLeadingConstraint,
            contentTrailingConstraint,
            contentTopConstraint,
            contentBottomConstraint,

            leadingSwipeActionImageView.widthAnchor.constraint(equalToConstant: actionImageSize),
            leadingSwipeActionImageView.heightAnchor.constraint(equalToConstant: actionImageSize),
            trailingSwipeActionImageView.widthAnchor.constraint(equalToConstant: actionImageSize),
            trailingSwipeActionImageView.heightAnchor.constraint(equalToConstant: actionImageSize),

            leadingSwipeActionImageView.centerYAnchor.constraint(equalTo: leadingSwipeActionView.centerYAnchor),
            leadingSwipeActionTrailingConstraint,

            trailingSwipeActionImageView.centerYAnchor.constraint(equalTo: trailingSwipeActionView.centerYAnchor),
            trailingSwipeActionLeadingConstraint,
        ])

        configurationUpdated()

        panGestureRecognizer.addTarget(self, action: #selector(panHandler(_:)))
        panGestureRecognizer.delegate = self
        addGestureRecognizer(panGestureRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Retunes the content inset (used by the post-list cell when the density
    /// preference changes). `bottom`/`right` follow the same negative-constant
    /// convention as the init `margin`.
    func setContentMargin(_ margin: UIEdgeInsets) {
        contentLeadingConstraint.constant = margin.left
        contentTrailingConstraint.constant = margin.right
        contentTopConstraint.constant = margin.top
        contentBottomConstraint.constant = margin.bottom
    }

    private func configurationUpdated() {
        panGestureRecognizer.isEnabled = configuration != nil

        leadingSwipeActionImageView.image = configuration?.leadingPrimaryAction.image
        trailingSwipeActionImageView.image = configuration?.trailingPrimaryAction.image

        leadingSwipeActionImageView.isAccessibilityElement = false
        leadingSwipeActionImageView.accessibilityLabel = configuration?.leadingPrimaryAction.title
        trailingSwipeActionImageView.isAccessibilityElement = false
        trailingSwipeActionImageView.accessibilityLabel = configuration?.trailingPrimaryAction.title
    }

    private func setImageWithPopAnimation(_ image: UIImage, on imageView: UIImageView) {
        // Honor Reduce Motion: skip the scale "pop" and just swap the image.
        guard !UIAccessibility.isReduceMotionEnabled else {
            imageView.image = image
            imageView.transform = .identity
            return
        }
        UIView.animate(withDuration: 0.1) {
            imageView.image = image
            imageView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        } completion: { _ in
            UIView.animate(withDuration: 0.1) {
                imageView.transform = .identity
            }
        }
    }

    @objc
    private func panHandler(_ gestureRecognizer: UIPanGestureRecognizer) {
        let offsetX = gestureRecognizer.translation(in: self).x
        let swipeDistance = abs(offsetX)

        guard let configuration else {
            fatalError("Gesture should have been disabled")
        }

        switch gestureRecognizer.state {
        case .began:
            actionState = .none

            leadingSwipeActionImageView.image = configuration.leadingPrimaryAction.image
            leadingSwipeActionView.backgroundColor = configuration.leadingPrimaryAction.backgroundColor

            trailingSwipeActionImageView.image = configuration.trailingPrimaryAction.image
            trailingSwipeActionView.backgroundColor = configuration.trailingPrimaryAction.backgroundColor

        case .changed:
            swipeActionContentContainerLeadingConstraint.constant = offsetX

            let newActionState: ActionState
            if swipeDistance > (64 + 32) * 2 {
                newActionState = .secondary
            } else if swipeDistance > 64 + 32 {
                newActionState = .primary
            } else {
                newActionState = .none
            }

            if offsetX > 0 {
                if swipeDistance > 64 + 32 {
                    leadingSwipeActionTrailingConstraint.constant = 64 + 16 - swipeDistance
                } else {
                    leadingSwipeActionTrailingConstraint.constant = -16
                }

                if newActionState != actionState {
                    let newConfiguration: Configuration.Action
                    switch newActionState {
                    case .none, .primary:
                        newConfiguration = configuration.leadingPrimaryAction
                    case .secondary:
                        newConfiguration = configuration.leadingSecondaryAction
                    }
                    setImageWithPopAnimation(newConfiguration.image, on: leadingSwipeActionImageView)
                    leadingSwipeActionView.backgroundColor = newConfiguration.backgroundColor
                }
            }

            if offsetX < 0 {
                if swipeDistance > 64 + 32 {
                    trailingSwipeActionLeadingConstraint.constant = -1 * (64 + 16 - swipeDistance)
                } else {
                    trailingSwipeActionLeadingConstraint.constant = 16
                }

                if newActionState != actionState {
                    let newConfiguration: Configuration.Action
                    switch newActionState {
                    case .none, .primary:
                        newConfiguration = configuration.trailingPrimaryAction
                    case .secondary:
                        newConfiguration = configuration.trailingSecondaryAction
                    }
                    setImageWithPopAnimation(newConfiguration.image, on: trailingSwipeActionImageView)
                    trailingSwipeActionView.backgroundColor = newConfiguration.backgroundColor
                }
            }

            actionState = newActionState

        case .ended:
            swipeActionContentContainerLeadingConstraint.constant = 0
            // Honor Reduce Motion: snap the content back without animating.
            if UIAccessibility.isReduceMotionEnabled {
                layoutIfNeeded()
            } else {
                UIView.animate(withDuration: 0.2) {
                    self.layoutIfNeeded()
                }
            }

            let isLeadingAction = offsetX > 0

            switch actionState {
            case .none:
                break

            case .primary:
                if isLeadingAction {
                    trigger?(.leadingPrimary)
                } else {
                    trigger?(.trailingPrimary)
                }

            case .secondary:
                if isLeadingAction {
                    trigger?(.leadingSecondary)
                } else {
                    trigger?(.trailingSecondary)
                }
            }

        case .cancelled:
            swipeActionContentContainerLeadingConstraint.constant = 0

        case .failed:
            swipeActionContentContainerLeadingConstraint.constant = 0

        case .possible:
            break

        @unknown default:
            logger.assertionFailure()
        }
    }
}

extension SwipeActionView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }

        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Let edge-driven navigation win when a horizontal swipe starts on this row.
        // Without this the row's swipe-to-action pan beats both the custom right-edge
        // forward gesture (a UIScreenEdgePanGestureRecognizer) and the system
        // left-edge back gesture (the nav controller's interactive-pop recognizer,
        // which is a private class, not a public UIScreenEdgePanGestureRecognizer).
        // Off the edges those gestures fail immediately, so mid-row swipe actions
        // still work without perceptible delay.
        if otherGestureRecognizer is UIScreenEdgePanGestureRecognizer {
            return true
        }
        return otherGestureRecognizer === enclosingNavigationController?.interactivePopGestureRecognizer
    }

    /// Walks the responder chain to the nearest enclosing navigation controller,
    /// used to identify the system left-edge back gesture by identity.
    private var enclosingNavigationController: UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController.navigationController
            }
            responder = current.next
        }
        return nil
    }
}
