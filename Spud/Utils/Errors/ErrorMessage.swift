//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit

/// Maps the error types thrown by the service layer into short, user-facing
/// strings suitable for a `UIAlertController` message. Centralised so every
/// write call site presents consistent copy.
enum ErrorMessage {
    static func userFacing(for error: Error) -> String {
        switch error {
        case let serviceError as LemmyServiceError:
            return userFacing(for: serviceError)
        case let apiError as LemmyApiError:
            return userFacing(for: apiError)
        default:
            return error.localizedDescription
        }
    }

    static func userFacing(for error: LemmyServiceError) -> String {
        switch error {
        case .requiresAuthentication:
            return NSLocalizedString(
                "You need to be signed in to do that.",
                comment: "Error shown when a write action is attempted on a signed-out account"
            )
        case let .apiError(apiError):
            return userFacing(for: apiError)
        case .invalidContent:
            return NSLocalizedString(
                "This message can't be sent.",
                comment: "Error shown when content is malformed or un-sendable (e.g. a direct message with no recipient)"
            )
        case let .internalInconsistency(description):
            return description
        }
    }

    static func userFacing(for error: LemmyApiError) -> String {
        switch error {
        case let .network(underlying):
            return underlying.localizedDescription
        case .failedToDeserializeResponse:
            return NSLocalizedString(
                "The server returned a response we could not understand.",
                comment: "Error shown when an API response cannot be parsed"
            )
        case let .serverError(response):
            return response.error
        case let .unauthorized(message):
            return message ?? NSLocalizedString(
                "You are not authorized to do that.",
                comment: "Error shown when the server rejects a request as unauthorized"
            )
        case let .unknownServerError(httpStatusCode, _):
            return String(
                format: NSLocalizedString(
                    "The server returned an unexpected error (%d).",
                    comment: "Error shown for an unexpected HTTP status; %d is the status code"
                ),
                httpStatusCode
            )
        case let .unknown(underlying):
            return underlying.localizedDescription
        }
    }
}
