//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

class LinkPreviewView: UIButton {
    // MARK: Public

    var thumbnailImage: UIImage? {
        get {
            thumbnailImageView.image
        }
        set {
            setThumbnailImage(newValue)
        }
    }

    var url: URL? {
        didSet {
            textChanged()
        }
    }

    var anchorText: String? {
        didSet { textChanged() }
    }

    var title: String? {
        didSet { textChanged() }
    }

    var isVideo: Bool = false {
        didSet { playBadgeImageView.isHidden = !isVideo }
    }

    var tapped: ((URL) -> Void)?

    // MARK: Private

    lazy var thumbnailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }()

    lazy var thumbnailPlaceholderImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.image = UIImage(systemName: "safari")!
        imageView.tintColor = .secondaryLabel
        return imageView
    }()

    lazy var primaryLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.isHidden = true
        return label
    }()

    lazy var linkLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    lazy var textStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [primaryLabel, linkLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }()

    lazy var playBadgeImageView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "play.circle.fill"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .white
        view.contentMode = .scaleAspectFit
        view.isHidden = true
        return view
    }()

    lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 10

        let chevron = UIImage(systemName: "chevron.right")!
        let chevronImageView = UIImageView(image: chevron)
        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronImageView.tintColor = UIColor.secondaryLabel
        chevronImageView.contentMode = .scaleAspectFit

        let subviews = [
            thumbnailImageView,
            textStackView,
            chevronImageView,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        NSLayoutConstraint.activate([
            thumbnailImageView.topAnchor.constraint(equalTo: stackView.topAnchor),
            thumbnailImageView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
            thumbnailImageView.widthAnchor.constraint(equalToConstant: 64),
            thumbnailImageView.heightAnchor.constraint(equalTo: thumbnailImageView.widthAnchor),

            chevronImageView.widthAnchor.constraint(equalToConstant: 12),
            chevronImageView.heightAnchor.constraint(equalToConstant: 24),
        ])

        return stackView
    }()

    // MARK: Functions

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .secondarySystemBackground

        layer.cornerRadius = 8
        layer.borderColor = UIColor.systemBackground.cgColor
        layer.borderWidth = 1
        layer.masksToBounds = true

        addSubview(thumbnailPlaceholderImageView)
        addSubview(stackView)

        thumbnailImageView.addSubview(playBadgeImageView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            thumbnailPlaceholderImageView.centerXAnchor.constraint(equalTo: thumbnailImageView.centerXAnchor),
            thumbnailPlaceholderImageView.centerYAnchor.constraint(equalTo: thumbnailImageView.centerYAnchor),
            thumbnailPlaceholderImageView.widthAnchor.constraint(equalToConstant: 24),
            thumbnailPlaceholderImageView.heightAnchor.constraint(equalToConstant: 24),

            playBadgeImageView.centerXAnchor.constraint(equalTo: thumbnailImageView.centerXAnchor),
            playBadgeImageView.centerYAnchor.constraint(equalTo: thumbnailImageView.centerYAnchor),
            playBadgeImageView.widthAnchor.constraint(equalToConstant: 28),
            playBadgeImageView.heightAnchor.constraint(equalToConstant: 28),
        ])

        addTarget(self, action: #selector(tapHandler), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        url = nil
        thumbnailImage = nil
        anchorText = nil
        title = nil
        isVideo = false
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if super.hitTest(point, with: event) != nil {
            // if clicked on one of my children, report that the button itself is the target.
            return self
        }
        return nil
    }

    private func hostPathString() -> String {
        guard let url else { return "" }
        guard let host = url.canonicalHost else {
            return url.absoluteString
        }
        return host + url.path
    }

    private func hostPathAttributedString() -> NSAttributedString {
        guard let url else { return NSAttributedString() }
        let hostAttributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                return paragraph
            }(),
            .foregroundColor: UIColor.label,
        ]
        let pathAttributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                return paragraph
            }(),
            .foregroundColor: UIColor.secondaryLabel,
        ]

        guard let hostString = url.canonicalHost else {
            return NSAttributedString(string: url.absoluteString, attributes: hostAttributes)
        }
        let pathString = url.path

        let host = NSAttributedString(string: hostString, attributes: hostAttributes)
        let path = NSAttributedString(string: pathString, attributes: pathAttributes)

        let result = NSMutableAttributedString()
        result.append(host)
        result.append(path)
        return result
    }

    private func textChanged() {
        if let title, !title.isEmpty {
            primaryLabel.isHidden = false
            primaryLabel.text = title
        } else if let anchorText, !anchorText.isEmpty {
            primaryLabel.isHidden = false
            primaryLabel.text = anchorText
        } else {
            primaryLabel.isHidden = true
        }

        // Secondary line: "anchor · host/path" when a title occupies the primary
        // line and we still have anchor text; otherwise just host/path.
        let host = hostPathString()
        if title != nil, let anchorText, !anchorText.isEmpty {
            linkLabel.attributedText = NSAttributedString(
                string: "\(anchorText) · \(host)",
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            )
        } else {
            linkLabel.attributedText = hostPathAttributedString()
        }
    }

    private func setThumbnailImage(_ image: UIImage?) {
        thumbnailImageView.image = image
    }

    @objc
    private func tapHandler() {
        guard let url else { return }
        tapped?(url)
    }
}

@available(iOS 17, *)
#Preview {
    let linkPreview = LinkPreviewView()
    linkPreview.url = URL(string: "https://example.com/")!
    linkPreview.thumbnailImage = UIImage(systemName: "clear.fill")!
    return linkPreview
}

@available(iOS 17, *)
#Preview("very long link") {
    let linkPreview = LinkPreviewView()
    linkPreview.url = URL(string: "https://example.com/very-long/path-that-does-not-fit-on-screen/yes-really-long")!
    linkPreview.thumbnailImage = UIImage(systemName: "clear.fill")!
    return linkPreview
}
