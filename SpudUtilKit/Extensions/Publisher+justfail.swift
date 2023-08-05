//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

// By John Sundell
// https://www.swiftbysundell.com/articles/extending-combine-with-convenience-apis/
public extension AnyPublisher {
    static func just(_ output: Output) -> Self {
        Just(output)
            .setFailureType(to: Failure.self)
            .eraseToAnyPublisher()
    }

    static func fail(with error: Failure) -> Self {
        Fail(error: error).eraseToAnyPublisher()
    }

    static func empty(completeImmediately: Bool) -> Self {
        Empty(completeImmediately: completeImmediately, outputType: Output.self, failureType: Failure.self)
            .eraseToAnyPublisher()
    }
}
