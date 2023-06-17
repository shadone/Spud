//
// Copyright (c) 2020-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

// Created by Brandon Evans
// https://combinecommunity.slack.com/archives/CN36JH38W/p1568827179008100?thread_ts=1568787054.005200&cid=CN36JH38W
extension Publisher {
    func combineLatest<Other: Publisher>(_ others: [Other]) -> AnyPublisher<[Output], Failure> where Other.Output == Output, Other.Failure == Failure {
        let selfWithArrayOutput = map { [$0] }.eraseToAnyPublisher()
        return others.reduce(selfWithArrayOutput) { combinedPublisher, nextPublisher in
            combinedPublisher.combineLatest(nextPublisher) { combinedOutput, nextOutput in
                combinedOutput + [nextOutput]
            }.eraseToAnyPublisher()
        }.eraseToAnyPublisher()
    }
}
