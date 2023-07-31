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

    /// Returns a closure for handling errors coming from ``AccountService`` requests.
    func errorHandler(
        for request: AlertHandlerRequest
    ) -> (Subscribers.Completion<AccountServiceLoginError>) -> Void

    /// Returns a closure for handling errors coming from ``ImageService`` requests.
    func image(
        error: ImageLoadingError,
        for imageUrl: URL
    )
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

    func image(
        error: ImageLoadingError,
        for imageUrl: URL
    ) {
        logger.error("Failed to load image '\(imageUrl, privacy: .public)': \(error, privacy: .public)")
    }
}
