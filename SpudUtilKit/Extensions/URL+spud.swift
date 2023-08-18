//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import os.log

private let logger = Logger(.utils)

public extension URL {
    enum SpudInternalLink {
        /// Identifies a Person at a given Instance.
        ///
        /// - Parameter personId: person identifier local to the specified instance.
        /// - Parameter instance: Instance actorId. e.g. "https://lemmy.world".
        ///
        /// - Note: the instance specifies the Lemmy instance the personId is valid for. I.e. it is **not** the persons home site.
        case person(personId: Int32, instance: InstanceActorId)

        /// Identifies a Post at a given Instance.
        ///
        /// - Parameter postId: post identifier local to the specified instance.
        /// - Parameter instance: Instance actorId. e.g. "https://lemmy.world".
        ///
        /// - Note: the instance specifies the Lemmy instance the personId is valid for. I.e. it is **not** the persons home site.
        case post(postId: Int32, instance: InstanceActorId)

        public var url: URL {
            switch self {
            case let .person(personId, instance):
                guard
                    let encodedInstance = instance.actorId
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                else {
                    fatalError("Failed to url encode '\(self)'")
                }
                return URL(string: "info.ddenis.spud://internal/person?personId=\(personId)&instance=\(encodedInstance)")!

            case let .post(postId, instance):
                guard
                    let encodedInstance = instance.actorId
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                else {
                    fatalError("Failed to url encode '\(self)'")
                }
                return URL(string: "info.ddenis.spud://internal/post?postId=\(postId)&instance=\(encodedInstance)")!
            }
        }
    }

    var spud: SpudInternalLink? {
        guard
            let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
            components.scheme == "info.ddenis.spud",
            components.host == "internal"
        else {
            return nil
        }

        if components.path == "/person" {
            guard
                let personIdString = components.queryItems?
                .first(where: { $0.name == "personId" })?.value,
                let personId = Int32(personIdString),
                let instanceString = components.queryItems?
                .first(where: { $0.name == "instance" })?.value,
                let instance = InstanceActorId(from: instanceString)
            else {
                logger.warning("Invalid internal link: \(absoluteString, privacy: .public)")
                return nil
            }

            return .person(personId: personId, instance: instance)
        } else if components.path == "/post" {
            guard
                let postIdString = components.queryItems?
                .first(where: { $0.name == "postId" })?.value,
                let postId = Int32(postIdString),
                let instanceString = components.queryItems?
                .first(where: { $0.name == "instance" })?.value,
                let instance = InstanceActorId(from: instanceString)
            else {
                logger.warning("Invalid internal link: \(absoluteString, privacy: .public)")
                return nil
            }

            return .post(postId: postId, instance: instance)
        }

        logger.warning("Invalid internal link: \(absoluteString, privacy: .public)")
        return nil
    }
}
