//
// Copyright (c) 2020-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

// By Ryoichi Izumita
// https://medium.com/@r.izumita/implementing-ignorenil-method-inside-publisher-of-combine-1622a8453b
public extension Publisher where Output: OptionalType {
    func ignoreNil() -> AnyPublisher<Output.Wrapped, Failure> {
        flatMap { output -> AnyPublisher<Output.Wrapped, Failure> in
            guard
                let output = output.optional
            else {
                return Empty<Output.Wrapped, Failure>(completeImmediately: false)
                    .eraseToAnyPublisher()
            }
            return .just(output)
        }.eraseToAnyPublisher()
    }
}
