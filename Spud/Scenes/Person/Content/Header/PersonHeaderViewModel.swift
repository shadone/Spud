//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import LemmyKit
import UIKit

class PersonHeaderViewModel {
    typealias Dependencies =
        HasVoid
    private let dependencies: Dependencies

    // MARK: Public

    var commentKarma: AnyPublisher<String, Never> {
        personInfo.publisher(for: \.totalScoreForComments)
            .map {
                PersonFormatter.string(totalScoreForComment: $0)
            }
            .eraseToAnyPublisher()
    }

    var postKarma: AnyPublisher<String, Never> {
        personInfo.publisher(for: \.totalScoreForPosts)
            .map {
                PersonFormatter.string(totalScoreForPosts: $0)
            }
            .eraseToAnyPublisher()
    }

    var accountAge: AnyPublisher<String, Never> {
        personInfo.publisher(for: \.accountCreationDate)
            .map {
                PersonFormatter.string(accountCreationDate: $0)
            }
            .eraseToAnyPublisher()
    }

    // MARK: Private

    private let personInfo: LemmyPersonInfo

    // MARK: Functions

    init(
        personInfo: LemmyPersonInfo,
        dependencies: Dependencies
    ) {
        self.personInfo = personInfo
        self.dependencies = dependencies
    }
}
