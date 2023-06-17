//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

extension Publisher {
    func wrapInOptional() -> Publishers.Map<Self, Output?> {
        map { Optional($0) }
    }
}
