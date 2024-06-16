//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SwiftUI
import UIKit

public struct SymbolImageResource: Sendable {
    let systemName: String

    public var image: UIImage {
        guard
            let image = UIImage(systemName: systemName, compatibleWith: nil)
        else {
            fatalError("Unable to load system symbol image named \(systemName).")
        }
        return image
    }

    public var swiftUIImage: SwiftUI.Image {
        SwiftUI.Image(systemName: systemName)
    }
}
