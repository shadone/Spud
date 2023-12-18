//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

enum PersonFormatter {
    static func string(personCreatedDate date: Date) -> String {
        date.relativeString
    }
}
