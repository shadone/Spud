//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
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
                // The fetch path only reaches this via LemmyServiceError(from:)'s
                // fallback for an unexpected error type — treat as a Spud bug.
                return LoadFailure(kind: .malformedResponse, diagnostics: diagnostics)
            case let .apiError(apiError):
                if let urlError = firstURLError(in: apiError) {
                    return LoadFailure(kind: kind(for: urlError), diagnostics: diagnostics)
                }
                return LoadFailure(kind: .unreachable, diagnostics: diagnostics)
            case .requiresAuthentication:
                // Auth is out of scope for this iteration; treat as unreachable.
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

    private static func firstURLError(in error: Error) -> URLError? {
        if let urlError = error as? URLError { return urlError }
        for underlying in (error as NSError).underlyingErrors {
            if let found = firstURLError(in: underlying) { return found }
        }
        return nil
    }
}
