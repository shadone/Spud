//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit

private let logger = Logger.app

/// View model for the Person profile screen. Holds plain @Observable state
/// driven by `appDatabase.observePersonProfile`. Fields default to empty
/// strings before the first snapshot arrives.
@MainActor
@Observable
final class PersonViewModel {
    var name: String = ""
    var homeInstance: String = ""
    var displayName: String?
    var numberOfPosts: String = ""
    var numberOfComments: String = ""
    var accountAge: String = ""

    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    init(personRowId: Int64?, appDatabase: AppDatabase) {
        guard let personRowId else { return }
        observationTask = Task { [weak self] in
            for await row in appDatabase.observePersonProfile(personRowId: personRowId) {
                if Task.isCancelled { break }
                guard let row else { continue }
                await MainActor.run { self?.apply(row: row) }
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    private func apply(row: PersonProfileRow) {
        name = row.name
        homeInstance = "@\(row.instanceHostname)"
        displayName = row.displayName
        numberOfPosts = CommentsFormatter.string(from: row.numberOfPosts)
        numberOfComments = CommentsFormatter.string(from: row.numberOfComments)
        if let createdDate = row.personCreatedDate {
            accountAge = PersonFormatter.string(personCreatedDate: createdDate)
        } else {
            accountAge = ""
        }
    }
}
