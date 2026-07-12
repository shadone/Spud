//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import SpudUtilKit

/// Drives `CustomInstanceEntryViewController`: a single free-text address
/// field for a Lemmy instance not in the bundled/Explorer directory (e.g. a
/// private, non-federated server). Deliberately service-free - validation is
/// pure and entirely client-side, and there is no network reachability probe
/// here (a hard probe could false-block a WAF'd/offline private instance,
/// which is exactly the use case this screen exists for).
@MainActor
@Observable
final class CustomInstanceEntryViewModel {
    /// The result of validating a typed address. `Equatable` is synthesized
    /// since `InstanceActorId` itself conforms.
    enum ValidationResult: Equatable {
        case valid(InstanceActorId)
        case invalid
    }

    var addressText: String = "" {
        didSet { errorText = nil }
    }

    /// Inline field error, set by `resolveInstance()` on invalid input; `nil`
    /// clears it (also cleared automatically as soon as the text changes).
    var errorText: String?

    var continueEnabled: Bool {
        !addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Validates `text` as an instance address. Pure and side-effect-free so
    /// it's directly unit-testable.
    ///
    /// `InstanceActorId(from:)`'s own parsing is intentionally naive (it
    /// exists to normalize host / `https://host` / port / trailing-slash
    /// input, not to reject typos) - it accepts a single bare word with no
    /// dot as a "valid" host. This adds the one check that matters for a
    /// user-typed address: reject when the parse fails outright, OR the
    /// result is invalid, OR the host has no dot (an obvious typo/junk
    /// entry, e.g. a single word). Deliberately does NOT probe the network:
    /// a private/WAF'd instance must still validate client-side.
    static func validate(_ text: String) -> ValidationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            let instance = InstanceActorId(from: trimmed),
            instance.isValid,
            instance.host.contains(".")
        else {
            return .invalid
        }
        return .valid(instance)
    }

    /// Validates `addressText`. On success clears `errorText` and returns the
    /// resolved instance; on failure sets `errorText` and returns `nil` so the
    /// caller knows not to proceed.
    func resolveInstance() -> InstanceActorId? {
        switch Self.validate(addressText) {
        case let .valid(instance):
            errorText = nil
            return instance
        case .invalid:
            errorText = NSLocalizedString(
                "Enter a valid instance address, like lemmy.example.com.",
                comment: "Custom instance entry: inline validation error for an empty/malformed address"
            )
            return nil
        }
    }
}
