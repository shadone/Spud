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
            case .internalInconsistency:
                return .transient
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
        case .network, .serverError, .unknownServerError, .unknown:
            return .transient
        }
    }
}
