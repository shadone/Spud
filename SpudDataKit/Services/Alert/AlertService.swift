//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import OSLog

private let logger = Logger(.alertService)

/// Helper for handling errors and displaying the appropriate message to the user.
public protocol AlertServiceType: AnyObject {
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

public protocol HasAlertService {
    var alertService: AlertServiceType { get }
}

public class AlertService: AlertServiceType {
    public init() { }

    public func errorHandler(
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

    public func errorHandler(
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

    public func image(
        error: ImageLoadingError,
        for imageUrl: URL
    ) {
        logger.error("Failed to load image '\(imageUrl, privacy: .public)': \(error, privacy: .public)")
    }
}
