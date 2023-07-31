//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import os.log

private let logger = Logger(.alertService)

/// Helper for handling errors and displaying the appropriate message to the user.
protocol AlertServiceType: AnyObject {
    /// Returns a closure for handling errors coming from ``LemmyService`` requests.
    func errorHandler(
        for request: AlertHandlerRequest
    ) -> (Subscribers.Completion<LemmyServiceError>) -> Void

    func errorHandler(
        for request: AlertHandlerRequest
    ) -> (Subscribers.Completion<AccountServiceLoginError>) -> Void
}

protocol HasAlertService {
    var alertService: AlertServiceType { get }
}

class AlertService: AlertServiceType {
    func errorHandler(
        for request: AlertHandlerRequest
    ) -> (Subscribers.Completion<LemmyServiceError>) -> Void {
        { completion in
            switch completion {
            case .finished:
                break

            case let .failure(error):
                logger.error("\(request) request failed: \(error, privacy: .public)")
            }
        }
    }

    func errorHandler(
        for request: AlertHandlerRequest
    ) -> (Subscribers.Completion<AccountServiceLoginError>) -> Void {
        { completion in
            switch completion {
            case .finished:
                break

            case let .failure(error):
                logger.error("\(request) request failed: \(error, privacy: .public)")
            }
        }
    }
}
