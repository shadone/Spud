//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SwiftUI

// https://www.avanderlee.com/swiftui/conditional-view-modifier/
public extension View {
    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
    @ViewBuilder
    func `if`(
        _ condition: @autoclosure () -> Bool,
        transform: (Self) -> some View
    ) -> some View {
        if condition() {
            transform(self)
        } else {
            self
        }
    }
}
