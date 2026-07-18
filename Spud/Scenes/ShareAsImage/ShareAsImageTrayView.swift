//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The editor's control tray, above the output bar: a passive hint line, the
/// appearance (Light/Dark) and canvas (Native/Square/Story) selectors, a
/// chain-depth stepper shown only for comment cards, and the "Alt Text" button.
///
/// The card's per-element toggles are NOT here — those are direct-manipulation
/// taps on the preview itself. The tray carries only the choices that have no
/// natural on-card target. All chrome honors Dynamic Type
/// (`adjustsFontForContentSizeCategory`); the card preview does not scale.
final class ShareAsImageTrayView: UIView {
    var onSelectAppearance: ((ShareCardOptions.Appearance) -> Void)?
    var onSelectCanvas: ((ShareCardOptions.Canvas) -> Void)?
    var onIncrementDepth: (() -> Void)?
    var onDecrementDepth: (() -> Void)?
    var onTapAltText: (() -> Void)?

    private let hintLabel = UILabel()
    private let appearanceControl = UISegmentedControl(items: ["Light", "Dark"])
    private let canvasControl = UISegmentedControl(items: ["Native", "Square", "Story"])

    private let depthMinusButton = UIButton(type: .system)
    private let depthPlusButton = UIButton(type: .system)
    private let depthLabel = UILabel()
    private let depthRow = UIStackView()

    private let altTextButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        hintLabel.text = "Tap any element to toggle it"
        hintLabel.font = .preferredFont(forTextStyle: .footnote)
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.textColor = .secondaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0

        appearanceControl.addAction(UIAction { [weak self] _ in
            self?.onSelectAppearance?(self?.appearanceControl.selectedSegmentIndex == 1 ? .dark : .light)
        }, for: .valueChanged)

        canvasControl.addAction(UIAction { [weak self] _ in
            let canvas: ShareCardOptions.Canvas = switch self?.canvasControl.selectedSegmentIndex {
            case 1: .square
            case 2: .story
            default: .native
            }
            self?.onSelectCanvas?(canvas)
        }, for: .valueChanged)

        setUpDepthRow()
        setUpAltTextButton()

        let stack = UIStackView(arrangedSubviews: [
            hintLabel, appearanceControl, canvasControl, depthRow, altTextButton,
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 8, trailing: 16)
        stack.setCustomSpacing(16, after: hintLabel)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setUpDepthRow() {
        var minusConfig = UIButton.Configuration.gray()
        minusConfig.image = UIImage(systemName: "minus")
        minusConfig.cornerStyle = .medium
        depthMinusButton.configuration = minusConfig
        depthMinusButton.accessibilityLabel = "Fewer ancestor comments"
        depthMinusButton.addAction(UIAction { [weak self] _ in self?.onDecrementDepth?() }, for: .touchUpInside)

        var plusConfig = UIButton.Configuration.gray()
        plusConfig.image = UIImage(systemName: "plus")
        plusConfig.cornerStyle = .medium
        depthPlusButton.configuration = plusConfig
        depthPlusButton.accessibilityLabel = "More ancestor comments"
        depthPlusButton.addAction(UIAction { [weak self] _ in self?.onIncrementDepth?() }, for: .touchUpInside)

        depthLabel.font = .preferredFont(forTextStyle: .subheadline)
        depthLabel.adjustsFontForContentSizeCategory = true
        depthLabel.textColor = .label
        depthLabel.textAlignment = .center

        depthRow.axis = .horizontal
        depthRow.spacing = 12
        depthRow.alignment = .center
        depthRow.distribution = .fill
        depthLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        depthRow.addArrangedSubview(depthMinusButton)
        depthRow.addArrangedSubview(depthLabel)
        depthRow.addArrangedSubview(depthPlusButton)
    }

    private func setUpAltTextButton() {
        var config = UIButton.Configuration.tinted()
        config.image = UIImage(systemName: "text.alignleft")
        config.imagePadding = 6
        config.title = "Alt Text"
        config.cornerStyle = .large
        altTextButton.configuration = config
        altTextButton.titleLabel?.adjustsFontForContentSizeCategory = true
        altTextButton.accessibilityHint = "Edit the description shared with the image"
        altTextButton.addAction(UIAction { [weak self] _ in self?.onTapAltText?() }, for: .touchUpInside)
    }

    /// Syncs the controls to the current options. `showsDepthStepper` reveals the
    /// depth stepper (false for post cards AND root comments — anything with no
    /// ancestors to step through); `maxChainDepth` bounds the ± buttons.
    func configure(options: ShareCardOptions, showsDepthStepper: Bool, maxChainDepth: Int) {
        appearanceControl.selectedSegmentIndex = options.appearance == .dark ? 1 : 0
        canvasControl.selectedSegmentIndex = switch options.canvas {
        case .native: 0
        case .square: 1
        case .story: 2
        }
        depthRow.isHidden = !showsDepthStepper
        depthLabel.text = "Depth \(options.chainDepth)"
        depthLabel.accessibilityLabel = "Ancestor comments: \(options.chainDepth)"
        depthMinusButton.isEnabled = options.chainDepth > 0
        depthPlusButton.isEnabled = options.chainDepth < maxChainDepth
    }
}
