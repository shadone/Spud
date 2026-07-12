//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import Testing
@testable import Spud

/// `CustomInstanceEntryViewModel.validate(_:)` is the pure client-side
/// validation behind the "Add your own instance" screen. It layers one extra
/// rule on top of `InstanceActorId(from:)`'s own (deliberately naive) parsing:
/// reject a host with no dot, since that parser accepts a single bare word as
/// a "valid" host and a typed instance address is a prime typo target.
/// Deliberately has no network/reachability assertions - the whole feature
/// exists for instances that legitimately won't answer a preflight probe
/// (private, non-federated, WAF'd).
@MainActor
struct CustomInstanceEntryViewModelTests {
    // MARK: validate(_:) - valid input

    @Test
    func validate_bareHost_isValid() {
        let result = CustomInstanceEntryViewModel.validate("lemmy.example.com")
        guard case let .valid(instance) = result else {
            Issue.record("expected .valid, got \(result)")
            return
        }
        #expect(instance.host == "lemmy.example.com")
    }

    @Test
    func validate_httpsScheme_isValid() {
        let result = CustomInstanceEntryViewModel.validate("https://lemmy.example.com")
        guard case let .valid(instance) = result else {
            Issue.record("expected .valid, got \(result)")
            return
        }
        #expect(instance.host == "lemmy.example.com")
    }

    @Test
    func validate_trailingSlash_isValid() {
        let result = CustomInstanceEntryViewModel.validate("https://lemmy.example.com/")
        guard case let .valid(instance) = result else {
            Issue.record("expected .valid, got \(result)")
            return
        }
        #expect(instance.host == "lemmy.example.com")
    }

    @Test
    func validate_withPort_isValid() {
        let result = CustomInstanceEntryViewModel.validate("lemmy.example.com:1234")
        guard case let .valid(instance) = result else {
            Issue.record("expected .valid, got \(result)")
            return
        }
        #expect(instance.host == "lemmy.example.com")
        #expect(instance.port == 1234)
    }

    @Test
    func validate_surroundingWhitespace_isTrimmedAndValid() {
        let result = CustomInstanceEntryViewModel.validate("  lemmy.example.com  ")
        guard case let .valid(instance) = result else {
            Issue.record("expected .valid, got \(result)")
            return
        }
        #expect(instance.host == "lemmy.example.com")
    }

    // MARK: validate(_:) - invalid input

    @Test
    func validate_empty_isInvalid() {
        #expect(CustomInstanceEntryViewModel.validate("") == .invalid)
    }

    @Test
    func validate_whitespaceOnly_isInvalid() {
        #expect(CustomInstanceEntryViewModel.validate("   ") == .invalid)
    }

    @Test
    func validate_multiWordJunk_isInvalid() {
        #expect(CustomInstanceEntryViewModel.validate("not a domain") == .invalid)
    }

    /// `InstanceActorId(from:)` itself accepts a single bare word with no dot
    /// (its regex is naive by design); the VM layers the dot requirement on
    /// top so an obvious single-word typo shows a validation error instead of
    /// silently proceeding to a login attempt.
    @Test
    func validate_singleWordWithNoDot_isInvalid() {
        #expect(CustomInstanceEntryViewModel.validate("junk") == .invalid)
    }

    @Test
    func validate_malformedPunctuation_isInvalid() {
        #expect(CustomInstanceEntryViewModel.validate("mkyong,com") == .invalid)
    }

    // MARK: resolveInstance() - drives errorText

    @Test
    func resolveInstance_valid_clearsErrorAndReturnsInstance() {
        let viewModel = CustomInstanceEntryViewModel()
        viewModel.addressText = "lemmy.example.com"

        let instance = viewModel.resolveInstance()

        #expect(instance?.host == "lemmy.example.com")
        #expect(viewModel.errorText == nil)
    }

    @Test
    func resolveInstance_invalid_setsErrorAndReturnsNil() {
        let viewModel = CustomInstanceEntryViewModel()
        viewModel.addressText = "junk"

        let instance = viewModel.resolveInstance()

        #expect(instance == nil)
        #expect(viewModel.errorText != nil)
    }

    @Test
    func continueEnabled_falseWhenEmpty_trueOnceTyped() {
        let viewModel = CustomInstanceEntryViewModel()
        #expect(viewModel.continueEnabled == false)

        viewModel.addressText = "lemmy.example.com"
        #expect(viewModel.continueEnabled == true)
    }
}
