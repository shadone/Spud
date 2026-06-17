//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents
import SpudDataKit
import SpudUtilKit

/// A Lemmy community exposed to App Intents / Siri / Spotlight. Identity is
/// `name@instanceHost`, which is federation-aware and stable across re-imports.
struct CommunityAppEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Community")
    static let defaultQuery = CommunityEntityQuery()

    var id: String
    var name: String
    var instanceActorId: String
    var iconURLString: String?

    /// The community's home instance, rebuilt from the stored actor id.
    var instance: InstanceActorId {
        InstanceActorId(from: instanceActorId) ?? .invalid
    }

    var displayRepresentation: DisplayRepresentation {
        if let iconURLString, let url = URL(string: iconURLString) {
            DisplayRepresentation(title: "\(name)", subtitle: "\(instance.host)", image: .init(url: url))
        } else {
            DisplayRepresentation(title: "\(name)", subtitle: "\(instance.host)")
        }
    }
}

extension CommunityAppEntity {
    /// Builds an entity from a persisted community row, mapping its actor id to
    /// the home instance. Nil when the row lacks the identity we need.
    init?(record: CommunityRecord) {
        guard
            let name = record.name,
            let actorId = record.actorId,
            let instance = InstanceActorId(from: actorId)
        else {
            return nil
        }
        self.init(
            id: "\(name)@\(instance.host)",
            name: name,
            instanceActorId: instance.actorId,
            iconURLString: record.iconUrl
        )
    }
}
