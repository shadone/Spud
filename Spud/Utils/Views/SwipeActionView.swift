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

            contentView.leadingAnchor.constraint(equalTo: swipeActionContentContainer.leadingAnchor, constant: margin.left),
            contentView.trailingAnchor.constraint(equalTo: swipeActionContentContainer.trailingAnchor, constant: margin.right),
            contentView.topAnchor.constraint(equalTo: swipeActionContentContainer.topAnchor, constant: margin.top),
            contentView.bottomAnchor.constraint(equalTo: swipeActionContentContainer.bottomAnchor, constant: margin.bottom),

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

    private func configurationUpdated() {
        panGestureRecognizer.isEnabled = configuration != nil

        leadingSwipeActionImageView.image = configuration?.leadingPrimaryAction.image
        trailingSwipeActionImageView.image = configuration?.trailingPrimaryAction.image
    }

    private func setImageWithPopAnimation(_ image: UIImage, on imageView: UIImageView) {
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
            UIView.animate(withDuration: 0.2) {
                self.layoutIfNeeded()
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
}
