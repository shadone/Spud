//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudMarkdownKit
import SpudUIKit
import UIKit

/// "About this server": the instance sidebar rendered as Markdown, clamped to a
/// few lines with a bottom fade and a Read more / Show less toggle.
final class InstanceAboutServerView: UIView {
    /// Fired when expand/collapse changes the intrinsic height so a scrolling
    /// host can re-measure.
    var onHeightChange: (() -> Void)?

    private let header = InstanceSectionHeader()
    private let card = UIView()
    private let bodyView: MarkdownBodyView = {
        let context = MarkdownContext(kind: .post, textScale: 0, density: .comfortable)
        return MarkdownBodyView(context: context)
    }()

    private let fade = GradientView()
    private let toggleButton = UIButton(type: .system)
    private var expanded = false
    private var collapsedHeightConstraint: NSLayoutConstraint!

    private let collapsedHeight: CGFloat = 124

    override init(frame: CGRect) {
        super.init(frame: frame)
        header.configure(title: "About this server", count: nil)

        card.backgroundColor = Theme.secondaryGroupedBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true

        let clip = UIView()
        clip.clipsToBounds = true
        clip.translatesAutoresizingMaskIntoConstraints = false
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(bodyView)
        clip.addSubview(fade)
        fade.translatesAutoresizingMaskIntoConstraints = false
        fade.isUserInteractionEnabled = false

        toggleButton.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .bold)
        toggleButton.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)

        let separator = UIView()
        separator.backgroundColor = .separator

        let outer = UIStackView(arrangedSubviews: [header, card])
        outer.axis = .vertical
        outer.spacing = 8
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)

        card.addSubview(clip)
        card.addSubview(separator)
        card.addSubview(toggleButton)
        clip.translatesAutoresizingMaskIntoConstraints = false
        separator.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.translatesAutoresizingMaskIntoConstraints = false

        collapsedHeightConstraint = clip.heightAnchor.constraint(equalToConstant: collapsedHeight)
        collapsedHeightConstraint.isActive = true

        let bodyBottom = bodyView.bottomAnchor.constraint(equalTo: clip.bottomAnchor)
        bodyBottom.priority = .defaultLow

        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),

            clip.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            clip.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            clip.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),

            bodyView.topAnchor.constraint(equalTo: clip.topAnchor),
            bodyView.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            bodyBottom,

            fade.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            fade.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            fade.heightAnchor.constraint(equalToConstant: 46),

            separator.topAnchor.constraint(equalTo: clip.bottomAnchor, constant: 11),
            separator.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            toggleButton.topAnchor.constraint(equalTo: separator.bottomAnchor),
            toggleButton.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            toggleButton.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            toggleButton.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            toggleButton.heightAnchor.constraint(equalToConstant: 42),
        ])
        applyState()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(sidebar: String, imageService: ImageServiceType?) {
        if let imageService {
            bodyView.imageLoader = { [imageService] url in
                for await state in imageService.fetch(url) {
                    if case let .ready(image) = state { return image }
                }
                return nil
            }
        }
        bodyView.setBlocks(MarkdownBlockCache.shared.blocks(for: sidebar))
    }

    private func toggle() {
        expanded.toggle()
        let animate = !UIAccessibility.isReduceMotionEnabled
        if animate {
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut]) {
                self.applyState()
                self.superview?.layoutIfNeeded()
            } completion: { _ in
                self.onHeightChange?()
            }
        } else {
            applyState()
            superview?.layoutIfNeeded()
            onHeightChange?()
        }
    }

    private func applyState() {
        collapsedHeightConstraint.isActive = !expanded
        fade.isHidden = expanded
        let accent = ThemeManager.currentAccentColor
        toggleButton.setTitleColor(accent, for: .normal)
        toggleButton.setTitle(expanded ? "Show less" : "Read more", for: .normal)
        toggleButton.setImage(UIImage(systemName: expanded ? "chevron.up" : "chevron.down"), for: .normal)
        toggleButton.tintColor = accent
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fade.topColor = Theme.secondaryGroupedBackground.withAlphaComponent(0)
        fade.bottomColor = Theme.secondaryGroupedBackground
    }
}

/// A simple vertical gradient used for the collapsed-sidebar fade.
final class GradientView: UIView {
    var topColor: UIColor = .clear {
        didSet { update() }
    }

    var bottomColor: UIColor = .clear {
        didSet { update() }
    }

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    private func update() {
        gradientLayer.colors = [topColor.cgColor, bottomColor.cgColor]
        gradientLayer.locations = [0, 0.86]
    }
}
