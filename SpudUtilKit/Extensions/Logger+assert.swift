//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

public extension Logger {
    func assert(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure @escaping () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        if !condition() {
            let message = message()
            warning("Assertion failure at \(file, privacy: .public):\(line, privacy: .public): \(message, privacy: .public)")
            #if DEBUG
            Swift.assertionFailure(message, file: file, line: line)
            #endif
        }
    }
}
