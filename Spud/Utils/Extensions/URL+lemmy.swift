//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension URL {
    enum SpudInternalLink {
        /// Identifies a Person at a given Instance.
        ///
        /// - Parameter personId: PersonId identifier local to the specified instance.
        /// - Parameter instance: Instance actorId. e.g. "https://lemmy.world", see ``URL/normalizedInstanceUrlString``.
        ///
        /// - Note: the instance specifies the Lemmy instance the personId is valid for. I.e. it is **not** the persons home site.
        case person(personId: PersonId, instance: String)

        var url: URL {
            switch self {
            case let .person(personId, instance):
                guard
                    let encodedinstance = instance
                        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                else {
                    fatalError("Failed to url encode '\(self)'")
                }
                return URL(string: "spud://internal/person?personId=\(personId)&instance=\(encodedinstance)")!
            }
        }
    }

    var spud: SpudInternalLink? {
        guard
            let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
            components.scheme == "spud",
            components.host == "internal"
        else {
            return nil
        }

        if components.path == "/person" {
            guard
                let personIdString = components.queryItems?
                    .first(where: { $0.name == "personId" })?.value,
                let personId = PersonId(personIdString),
                let instance = components.queryItems?
                    .first(where: { $0.name == "instance" })?.value
            else {
                assertionFailure()
                return nil
            }

            return .person(personId: personId, instance: instance)
        }

        return nil
    }
}
