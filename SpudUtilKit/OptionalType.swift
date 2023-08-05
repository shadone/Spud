//
// Copyright (c) 2020-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

// By Ryoichi Izumita
// https://medium.com/@r.izumita/implementing-ignorenil-method-inside-publisher-of-combine-1622a8453b

public protocol OptionalType {
    associatedtype Wrapped

    var optional: Wrapped? { get }
}

extension Optional: OptionalType {
    public var optional: Wrapped? { self }
}
