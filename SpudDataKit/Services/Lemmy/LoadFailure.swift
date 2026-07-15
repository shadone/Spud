//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit

/// A remote load failure, narrowed to the three causes the UI distinguishes.
/// `diagnostics` carries detail for logging and the "copy details" action; it
/// is never shown verbatim in primary UI copy.
public struct LoadFailure: Error, Equatable {
    public enum Kind: Equatable {
        /// No usable network connection.
        case offline
        /// Reached the network but couldn't get a usable response: timeout,
        /// connection failure, or a server-side error.
        case unreachable
        /// Got a response Spud couldn't read (decode/parse failure) — most
        /// likely a Spud bug.
        case malformedResponse
    }

    public let kind: Kind
    public let diagnostics: String

    public init(kind: Kind, diagnostics: String) {
        self.kind = kind
        self.diagnostics = diagnostics
    }

    /// Classify a thrown error into a `LoadFailure`. `isOnline` reflects the
    /// reachability monitor at the moment of failure and takes precedence: if
    /// we know we're offline, the cause is `.offline` regardless of the error.
    public static func classify(_ error: Error, isOnline: Bool) -> LoadFailure {
        let diagnostics = String(describing: error)

        if !isOnline {
            return LoadFailure(kind: .offline, diagnostics: diagnostics)
        }

        // A decode/parse failure anywhere in the chain means we got bytes we
        // couldn't read — surfaced as a Spud bug.
        if containsDecodingError(error) {
            return LoadFailure(kind: .malformedResponse, diagnostics: diagnostics)
        }

        switch error {
        case let urlError as URLError:
            return LoadFailure(kind: kind(for: urlError), diagnostics: diagnostics)

        case let serviceError as LemmyServiceError:
            switch serviceError {
            case .internalInconsistency:
                // Reached either by LemmyServiceError(from:)'s fallback for an unexpected
                // error type, or by an explicit persistence failure (e.g. a feed page that
                // could not be written because the account/site row was not ready yet).
                // Both are transient and retryable - surface the retryable error, not a
                // "Spud bug" malformed-response surface. (Genuine decode failures are
                // already caught above by containsDecodingError.)
                return LoadFailure(kind: .unreachable, diagnostics: diagnostics)
            case let .apiError(apiError):
                return LoadFailure(kind: kind(forApiError: apiError), diagnostics: diagnostics)
            case .requiresAuthentication:
                // Auth is out of scope for this iteration; treat as unreachable.
                return LoadFailure(kind: .unreachable, diagnostics: diagnostics)
            case .invalidContent:
                // Malformed/un-sendable content is a client-side data-invariant
                // violation (a Spud bug), not a network condition — surface it as
                // the "Spud bug" malformed-response kind. In practice this is an
                // outbox-only error and shouldn't reach a read-path LoadFailure.
                return LoadFailure(kind: .malformedResponse, diagnostics: diagnostics)
            case .unsupportedByInstance:
                // Capability-gated screens (person profile, inbox, composer) show
                // their own dedicated "not supported on this instance" UI (see
                // `LemmyServiceError.unsupportedByInstance`); this generic
                // three-kind classifier has no matching bucket, so fall back to
                // the closest one — retrying can't help, same as `.unreachable`.
                return LoadFailure(kind: .unreachable, diagnostics: diagnostics)
            }

        case is TimeoutError:
            return LoadFailure(kind: .unreachable, diagnostics: diagnostics)

        default:
            return LoadFailure(kind: .unreachable, diagnostics: diagnostics)
        }
    }

    private static func kind(for urlError: URLError) -> Kind {
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        default:
            return .unreachable
        }
    }

    private static func containsDecodingError(_ error: Error) -> Bool {
        if error is DecodingError { return true }
        for underlying in (error as NSError).underlyingErrors {
            if containsDecodingError(underlying) { return true }
        }
        return false
    }

    /// `LemmyApiError` carries its cause as an associated value and does not
    /// bridge it into `NSError.underlyingErrors`, so inspect its cases directly.
    private static func kind(forApiError apiError: LemmyApiError) -> Kind {
        switch apiError {
        case .failedToDeserializeResponse:
            return .malformedResponse
        case let .network(underlying):
            if let urlError = underlying as? URLError {
                return kind(for: urlError)
            }
            return .unreachable
        case .serverError, .unauthorized:
            return .unreachable
        case let .unknownServerError(_, underlying):
            if let underlying, containsDecodingError(underlying) {
                return .malformedResponse
            }
            return .unreachable
        case let .unknown(underlying):
            if containsDecodingError(underlying) {
                return .malformedResponse
            }
            if let urlError = underlying as? URLError {
                return kind(for: urlError)
            }
            return .unreachable
        case .unsupportedByDialect:
            // Mirrors `.unsupportedByInstance` above: no dedicated bucket in
            // this generic three-kind classifier, and retrying can't help —
            // fall back to the closest one.
            return .unreachable
        }
    }
}
