//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

class SiteListIconImageView: UIView {
    // MARK: Public

    enum IconType {
        /// An actual instance icon.
        case image(UIImage)

        /// The image has failed to load, we display a "broken image icon".
        case imageFailure

        /// The instance does not have an icon set.
        case noIcon

        /// Used before we have an image set.
        case none
    }

    var iconType: IconType = .none {
        didSet {
            imageView.image = nil
            imageView.isHidden = true
            placeholderIconView.isHidden = true
            brokenView.isHidden = true

            switch iconType {
            case let .image(image):
                imageView.isHidden = false
                imageView.image = image

            case .imageFailure:
                brokenView.isHidden = false

            case .noIcon:
                placeholderIconView.isHidden = false

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

        let views = [
            imageView,
            placeholderIconView,
            brokenView,
        ]

        views.forEach { $0.isHidden = true }
        views.forEach(stackView.addArrangedSubview)

        return stackView
    }()

    lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        return imageView
    }()

    lazy var placeholderIconView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(white: 0.888, alpha: 1)
        return view
    }()

    lazy var placeholderIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(systemName: "building.2.crop.circle")!
        imageView.tintColor = .lightGray
        return imageView
    }()

    lazy var brokenView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(white: 0.888, alpha: 1)
        return view
    }()

    lazy var brokenImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(systemName: "questionmark.square.dashed")!
        imageView.tintColor = .lightGray
        return imageView
    }()

    // MARK: Functions

    init() {
        super.init(frame: .zero)

        layer.cornerRadius = 8
        clipsToBounds = true

        addSubview(stackView)

        placeholderIconView.addSubview(placeholderIconImageView)
        brokenView.addSubview(brokenImageView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderIconImageView.widthAnchor.constraint(equalToConstant: 48),
            placeholderIconImageView.heightAnchor.constraint(equalToConstant: 48),

            placeholderIconImageView.centerXAnchor.constraint(equalTo: placeholderIconView.centerXAnchor),
            placeholderIconImageView.centerYAnchor.constraint(equalTo: placeholderIconView.centerYAnchor),

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
        iconType = .none
    }
}
