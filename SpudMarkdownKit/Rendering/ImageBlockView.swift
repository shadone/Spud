//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A body image: an aspect-ratio box showing a loading spinner, a failed plate
/// (with an "Open in browser" escape hatch), or the loaded image with a "Tap to
/// zoom" chip; an optional italic alt caption sits 6pt below in every state.
final class ImageBlockView: UIView {
    enum State: Equatable {
        case loading
        case loaded(UIImage)
        case failed
    }

    private let url: URL
    private let altText: String?
    private let context: MarkdownContext
    private let onTapImage: ((URL, String?, CGRect) -> Void)?
    private let onOpenInBrowser: ((URL) -> Void)?

    private let box = UIView()
    private var boxAspect: NSLayoutConstraint?

    init(
        image: MarkdownImage,
        context: MarkdownContext,
        onTapImage: ((URL, String?, CGRect) -> Void)?,
        onOpenInBrowser: ((URL) -> Void)?,
        loader: MarkdownImageLoader?
    ) {
        url = image.url
        altText = image.altText
        self.context = context
        self.onTapImage = onTapImage
        self.onOpenInBrowser = onOpenInBrowser
        super.init(frame: .zero)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        box.clipsToBounds = true
        box.layer.cornerRadius = context.kind == .post ? 12 : 9
        box.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(box)

        if let altText {
            let caption = UILabel()
            caption.text = altText
            caption.numberOfLines = 0
            caption.font = .italicSystemFont(ofSize: context.smallFont.pointSize)
            caption.textColor = context.secondaryColor
            stack.addArrangedSubview(caption)
        }

        // The failed-state border is a CGColor snapshot; re-resolve on theme change.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ImageBlockView, _: UITraitCollection) in
            if view.box.layer.borderWidth > 0 {
                view.box.layer.borderColor = UIColor.separator.cgColor
            }
        }

        apply(state: .loading)

        if let loader {
            let capturedURL = url
            Task { [weak self] in
                let image = await loader(capturedURL)
                guard let self else { return }
                apply(state: image.map(State.loaded) ?? .failed)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Replaces the box's content for `state` and updates its aspect ratio.
    func apply(state: State) {
        box.subviews.forEach { $0.removeFromSuperview() }
        box.gestureRecognizers?.forEach { box.removeGestureRecognizer($0) }
        boxAspect?.isActive = false
        boxAspect = nil
        box.backgroundColor = nil
        box.layer.borderWidth = 0
        box.isUserInteractionEnabled = false

        switch state {
        case .loading:
            box.backgroundColor = .secondarySystemFill
            setBoxAspect(widthOverHeight: 16.0 / 10.0)
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.color = context.tertiaryColor
            spinner.startAnimating()
            placeStatusStack([spinner, statusLabel("Loading image\u{2026}", color: context.secondaryColor)])

        case let .loaded(image):
            box.backgroundColor = .clear
            let ratio = image.size.height > 0 ? image.size.width / image.size.height : 16.0 / 10.0
            setBoxAspect(widthOverHeight: ratio)
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: box.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: box.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: box.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            ])
            addZoomChip()
            box.isUserInteractionEnabled = true
            box.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(zoomTapped)))

        case .failed:
            box.backgroundColor = .secondarySystemFill
            box.layer.borderWidth = 0.5
            box.layer.borderColor = UIColor.separator.cgColor
            setBoxAspect(widthOverHeight: 16.0 / 10.0)
            let glyph = UIImageView(image: UIImage(systemName: "photo"))
            glyph.tintColor = context.tertiaryColor
            glyph.contentMode = .scaleAspectFit
            glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: context.kind == .post ? 30 : 24)
            glyph.isAccessibilityElement = false
            let open = UIButton(type: .system)
            open.setTitle("Open in browser", for: .normal)
            open.titleLabel?.font = .systemFont(ofSize: context.smallFont.pointSize, weight: .semibold)
            open.tintColor = context.accentColor
            open.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                onOpenInBrowser?(url)
            }, for: .touchUpInside)
            placeStatusStack([glyph, statusLabel("Image couldn\u{2019}t load", color: context.secondaryColor), open])
        }
    }

    private func setBoxAspect(widthOverHeight ratio: CGFloat) {
        let c = box.heightAnchor.constraint(equalTo: box.widthAnchor, multiplier: 1 / max(ratio, 0.05))
        c.isActive = true
        boxAspect = c
    }

    private func statusLabel(_ text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: context.smallFont.pointSize, weight: .semibold)
        label.textColor = color
        label.textAlignment = .center
        return label
    }

    private func placeStatusStack(_ views: [UIView]) {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: box.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -12),
        ])
    }

    private func addZoomChip() {
        let icon = UIImageView(image: UIImage(systemName: "plus.magnifyingglass"))
        icon.tintColor = .white
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: context.smallFont.pointSize, weight: .semibold)
        icon.isAccessibilityElement = false
        let label = UILabel()
        label.text = "Tap to zoom"
        label.font = .systemFont(ofSize: context.smallFont.pointSize * 0.92, weight: .semibold)
        label.textColor = .white

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 4
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false

        let chip = UIView()
        chip.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        chip.layer.cornerRadius = 8
        chip.clipsToBounds = true
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: chip.topAnchor),
            row.bottomAnchor.constraint(equalTo: chip.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: chip.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: chip.trailingAnchor),
        ])

        box.addSubview(chip)
        NSLayoutConstraint.activate([
            chip.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -9),
            chip.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -9),
        ])
    }

    @objc
    private func zoomTapped() {
        onTapImage?(url, altText, box.convert(box.bounds, to: nil))
    }
}
