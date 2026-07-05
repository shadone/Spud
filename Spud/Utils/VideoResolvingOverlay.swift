//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A brief full-screen dim + spinner shown while a video-host URL is resolved to
/// a playable stream. The full-bleed container also swallows touches so a second
/// tap can't start a second resolve. Removed via `dismiss()`.
@MainActor
final class VideoResolvingOverlay {
    private let container: UIView

    private init(container: UIView) {
        self.container = container
    }

    static func present(in viewController: UIViewController) -> VideoResolvingOverlay {
        let host = viewController.view!

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.black.withAlphaComponent(0.25)

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        container.addSubview(spinner)

        host.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: host.topAnchor),
            container.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return VideoResolvingOverlay(container: container)
    }

    func dismiss() {
        container.removeFromSuperview()
    }
}
