//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import UIKit

class PostListThumbnailImageView: UIView {
    // MARK: Public

    enum ThumbnailType {
        /// An actual image thumbnail.
        case image(UIImage)

        /// The image has failed to load, we display a "broken image icon".
        case imageFailure

        /// We display a text post icon.
        case text

        /// Used before we have an image set.
        case none
    }

    var thumbnailType: ThumbnailType = .none {
        didSet {
            imageView.image = nil
            imageView.isHidden = true
            textPlaceholderView.isHidden = true
            brokenView.isHidden = true

            switch thumbnailType {
            case let .image(image):
                imageView.isHidden = false
                imageView.image = image

            case .imageFailure:
                brokenView.isHidden = false

            case .text:
                textPlaceholderView.isHidden = false

            case .none:
                break
            }
        }
    }

    // MARK: UI Properties

    lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical

        let subviews = [
            imageView,
            textPlaceholderView,
            brokenView,
        ]
        for view in subviews {
            view.isHidden = true
            stackView.addArrangedSubview(view)
        }

        return stackView
    }()

    lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        return imageView
    }()

    lazy var textPlaceholderView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Design.TextPost.Thumbnail.background.color
        return view
    }()

    lazy var textPlaceholderImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = Design.TextPost.Thumbnail.icon.image
        imageView.tintColor = Design.TextPost.Thumbnail.iconTint.color
        return imageView
    }()

    lazy var brokenView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Design.ImagePost.BrokenThumbnail.background.color
        return view
    }()

    lazy var brokenImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = Design.ImagePost.BrokenThumbnail.icon.image
        imageView.tintColor = Design.ImagePost.BrokenThumbnail.iconTint.color
        return imageView
    }()

    // MARK: Functions

    init() {
        super.init(frame: .zero)

        layer.cornerRadius = 8
        clipsToBounds = true

        addSubview(stackView)

        textPlaceholderView.addSubview(textPlaceholderImageView)
        brokenView.addSubview(brokenImageView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            textPlaceholderImageView.widthAnchor.constraint(equalToConstant: 48),
            textPlaceholderImageView.heightAnchor.constraint(equalToConstant: 48),

            textPlaceholderImageView.centerXAnchor.constraint(equalTo: textPlaceholderView.centerXAnchor),
            textPlaceholderImageView.centerYAnchor.constraint(equalTo: textPlaceholderView.centerYAnchor),

            brokenImageView.widthAnchor.constraint(equalToConstant: 48),
            brokenImageView.heightAnchor.constraint(equalToConstant: 48),

            brokenImageView.centerXAnchor.constraint(equalTo: brokenView.centerXAnchor),
            brokenImageView.centerYAnchor.constraint(equalTo: brokenView.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        thumbnailType = .none
    }
}
