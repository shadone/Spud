//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// Decides whether a failed outbox send should be retried forever (transient)
/// or rolled back and surfaced (permanent). Distinct from `LoadFailure`, which
/// collapses auth into `.unreachable`; the outbox must treat auth as permanent
/// because a vote should not spin forever when the session is invalid.
///
/// Permanent cases include: auth errors, invalid/un-sendable content
/// (`LemmyServiceError.invalidContent`), structured Lemmy server rejections
/// (deleted/removed entity, banned, not-found, etc.), and client-error HTTP
/// status codes (4xx excluding 408 and 429). Transient cases include: network
/// errors, rate-limit rejections, server errors (5xx), 408, and 429.
public enum OutboxFailureClass: Sendable, Equatable {
    case transient
    case permanent

    /// Classify a thrown error into an `OutboxFailureClass`. `isOnline` reflects
    /// the reachability monitor at the moment of failure and takes precedence: if
    /// we know we're offline, the error is always transient — retry when online.
    public static func classify(_ error: Error, isOnline: Bool) -> OutboxFailureClass {
        if !isOnline { return .transient }

        switch error {
        case let serviceError as LemmyServiceError:
            switch serviceError {
            case let .apiError(apiError):
                return classify(apiError)
            case .requiresAuthentication:
                return .permanent
            case .invalidContent:
                // Malformed/un-sendable content is a programmer/data error: no
                // retry can ever make it valid, so park it (permanent) rather
                // than spin forever.
                return .permanent
            case .internalInconsistency:
                return .transient
            case .unsupportedByInstance:
                // The instance can't serve this endpoint at all (e.g. Lemmy
                // 1.0's partial v3 shim); no retry can succeed until Spud
                // speaks the newer API, so roll back rather than spin.
                return .permanent
            }
        case is URLError:
            return .transient
        case let apiError as LemmyApiError:
            return classify(apiError)
        default:
            return .transient
        }
    }

    private static func classify(_ apiError: LemmyApiError) -> OutboxFailureClass {
        switch apiError {
        case .unauthorized, .failedToDeserializeResponse:
            return .permanent
        case let .serverError(errorResponse):
            // A structured Lemmy rejection (deleted/removed entity, banned, not-found,
            // already-deleted, etc.) is permanent — retrying yields the same rejection.
            // Rate-limit errors are the exception: backing off and retrying later helps.
            if errorResponse.error.hasPrefix("rate_limit") {
                return .transient
            }
            return .permanent
        case let .unknownServerError(httpStatusCode, _):
            // Client errors (4xx) are permanent except 408 Request Timeout and
            // 429 Too Many Requests, which are worth retrying. 5xx are transient.
            if (400..<500).contains(httpStatusCode), httpStatusCode != 408, httpStatusCode != 429 {
                return .permanent
            }
            return .transient
        case .network, .unknown:
            return .transient
        case .unsupportedByDialect:
            // Mirrors `.unsupportedByInstance` above: the account's dialect
            // (e.g. PieFed) has no implementation for this endpoint at all, so
            // no retry can ever succeed — roll back rather than spin.
            return .permanent
        }
    }
}
