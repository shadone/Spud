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
            urlChanged()
        }
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

    lazy var linkLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.numberOfLines = 1
        return label
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
            linkLabel,
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

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            thumbnailPlaceholderImageView.centerXAnchor.constraint(equalTo: thumbnailImageView.centerXAnchor),
            thumbnailPlaceholderImageView.centerYAnchor.constraint(equalTo: thumbnailImageView.centerYAnchor),
            thumbnailPlaceholderImageView.widthAnchor.constraint(equalToConstant: 24),
            thumbnailPlaceholderImageView.heightAnchor.constraint(equalToConstant: 24),
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
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if super.hitTest(point, with: event) != nil {
            // if clicked on one of my children, report that the button itself is the target.
            return self
        }
        return nil
    }

    private func urlChanged() {
        guard let url else { return }
        linkLabel.attributedText = {
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
        }()
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
