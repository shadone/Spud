//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import SpudDataKit

/// View-model state for HistoryViewController. Holds the active history mode and
/// the search text; the view controller observes these and (re)starts the GRDB
/// history stream when they change.
@MainActor
@Observable
final class HistoryViewModel {
    @ObservationIgnored
    let accountKeychainId: String

    var mode: HistoryMode = .read

    /// Raw text from the search bar. `searchQuery` is the normalized form fed to
    /// the observation.
    var searchText: String = ""

    /// Trimmed search text, or nil when blank (no search filter).
    var searchQuery: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    init(accountKeychainId: String) {
        self.accountKeychainId = accountKeychainId
    }
}
