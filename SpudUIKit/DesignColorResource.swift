//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SwiftUI
import UIKit

public struct DesignColorResource: Sendable {
    let asset: ColorAsset

    public var color: UIColor {
        asset.color
    }

    public var swiftUIColor: SwiftUI.Color {
        asset.swiftUIColor
    }
}

extension ColorAsset {
    var resource: DesignColorResource {
        .init(asset: self)
    }
}

/// SwiftGen 6.6.3 emits `ColorAsset` without Swift 6 `Sendable` conformance.
/// It's a final class with a `lazy var color` that is read-only after first
/// access; treating it as `@unchecked Sendable` matches its actual use as a
/// process-wide singleton accessed from any thread.
extension ColorAsset: @unchecked Sendable { }
