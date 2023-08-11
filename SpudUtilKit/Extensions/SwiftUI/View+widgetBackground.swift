//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import WidgetKit
import SwiftUI

public extension View {
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            return containerBackground(color, for: .widget)
        } else {
            return background(color)
        }
    }
}
