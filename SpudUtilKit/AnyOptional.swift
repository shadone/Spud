//
// Copyright (c) 2020-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

// By Ryoichi Izumita
// https://medium.com/@r.izumita/implementing-ignorenil-method-inside-publisher-of-combine-1622a8453b
//
// Also inspired by John Sundell's
// https://www.swiftbysundell.com/articles/property-wrappers-in-swift/

// > Since our property wrapper's Value type isn't optional, but
// > can still contain nil values, we'll have to introduce this
// > protocol to enable us to cast any assigned value into a type
// > that we can compare against nil:

public protocol AnyOptional {
    associatedtype Wrapped

    var optional: Wrapped? { get }

    var isNil: Bool { get }
}

extension Optional: AnyOptional {
    public var optional: Wrapped? { self }

    public var isNil: Bool { self == nil }
}
