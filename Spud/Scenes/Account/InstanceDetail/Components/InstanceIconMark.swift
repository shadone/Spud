//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A square rounded "identicon" mark: a deterministic hue-tinted background
/// (seeded by a string, e.g. an instance host) plus the first letter of a
/// display source, uppercased and centered. Shared by `InstanceCommunityRowView`
/// and `InstanceMetaCommunityRowView` so the two community-row styles can never
/// visually drift apart — callers are responsible for sizing the returned view
/// (both existing call sites use a 38pt width/height constraint).
enum InstanceIconMark {
    static func make(hueSeed: String, letterSource: String) -> UIView {
        let container = UIView()
        container.layer.cornerRadius = 10
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        let hue = CGFloat(hueSeed.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 360) / 360
        container.backgroundColor = UIColor(hue: hue, saturation: 0.45, brightness: 0.55, alpha: 1)
        let letter = UILabel()
        letter.text = String(letterSource.prefix(1)).uppercased()
        letter.font = .systemFont(ofSize: 16, weight: .bold)
        letter.textColor = .white
        letter.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(letter)
        NSLayoutConstraint.activate([
            letter.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            letter.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }
}
