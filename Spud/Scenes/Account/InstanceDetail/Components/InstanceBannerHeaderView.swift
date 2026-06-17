//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

/// Banner image + overlapping rounded instance icon + name/host identity.
/// Shared by both instance-detail screens. The owning controller overlays its
/// own transparent nav buttons; this view draws only the banner and identity.
final class InstanceBannerHeaderView: UIView {
    let bannerHeight: CGFloat = 158

    private let bannerImageView = UIImageView()
    private let iconImageView = UIImageView()
    private let iconLetterLabel = UILabel()
    private var imageTasks: [Task<Void, Never>] = []
    private let host: String

    init(name: String, host: String) {
        self.host = host
        super.init(frame: .zero)

        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.clipsToBounds = true
        bannerImageView.backgroundColor = Self.placeholderColor(seed: host, saturation: 0.5, brightness: 0.5)
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bannerImageView)

        iconImageView.contentMode = .scaleAspectFill
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = 16
        iconImageView.layer.cornerCurve = .continuous
        iconImageView.layer.borderWidth = 3
        iconImageView.layer.borderColor = Theme.groupedBackground.cgColor
        iconImageView.backgroundColor = Self.placeholderColor(seed: host, saturation: 0.45, brightness: 0.55)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconLetterLabel.text = String(name.prefix(1)).uppercased()
        iconLetterLabel.font = .systemFont(ofSize: 26, weight: .heavy)
        iconLetterLabel.textColor = .white
        iconLetterLabel.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.addSubview(iconLetterLabel)
        addSubview(iconImageView)

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 20, weight: .heavy)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 2

        let hostLabel = UILabel()
        hostLabel.text = host
        hostLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        hostLabel.textColor = .secondaryLabel

        let identity = UIStackView(arrangedSubviews: [nameLabel, hostLabel])
        identity.axis = .vertical
        identity.spacing = 3
        identity.translatesAutoresizingMaskIntoConstraints = false
        addSubview(identity)

        NSLayoutConstraint.activate([
            bannerImageView.topAnchor.constraint(equalTo: topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: bannerHeight),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconImageView.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: -30),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),
            iconLetterLabel.centerXAnchor.constraint(equalTo: iconImageView.centerXAnchor),
            iconLetterLabel.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor),

            identity.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 13),
            identity.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            identity.bottomAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: -2),

            bottomAnchor.constraint(equalTo: iconImageView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { imageTasks.forEach { $0.cancel() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconImageView.layer.borderColor = Theme.groupedBackground.cgColor
    }

    func loadImages(iconUrl: String?, bannerUrl: String?, imageService: ImageServiceType) {
        if let url = iconUrl.flatMap(URL.init(string:)) {
            iconLetterLabel.isHidden = true
            fetch(url, into: iconImageView, imageService: imageService, fallbackLetter: true)
        }
        if let url = bannerUrl.flatMap(URL.init(string:)) {
            fetch(url, into: bannerImageView, imageService: imageService, fallbackLetter: false)
        }
    }

    private func fetch(_ url: URL, into imageView: UIImageView, imageService: ImageServiceType, fallbackLetter: Bool) {
        let stream = imageService.fetch(url)
        let task = Task { [weak self] in
            for await state in stream {
                guard let self else { return }
                switch state {
                case .loading: break
                case let .ready(image):
                    imageView.image = image
                    if fallbackLetter { iconLetterLabel.isHidden = true }
                case .failure:
                    if fallbackLetter { iconLetterLabel.isHidden = false }
                }
            }
        }
        imageTasks.append(task)
    }

    private static func placeholderColor(seed: String, saturation: CGFloat, brightness: CGFloat) -> UIColor {
        let hue = CGFloat(seed.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 360) / 360
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }
}
