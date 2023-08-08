//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SwiftUI
import UIKit

public struct DesignColorResource {
    let asset: ColorAsset

    public var color: UIColor { asset.color }
    public var swiftUIColor: SwiftUI.Color { asset.swiftUIColor }
}

extension ColorAsset {
    var resource: DesignColorResource {
        .init(asset: self)
    }
}
