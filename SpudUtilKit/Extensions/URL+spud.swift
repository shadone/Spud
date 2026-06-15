//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

private let logger = Logger.utils

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

        /// Identifies a Community by name, as seen from a given Instance.
        ///
        /// - Parameter name: the bare community name, e.g. "world".
        /// - Parameter instance: Instance actorId the name is resolved against,
        ///   e.g. "https://lemmy.world".
        case community(name: String, instance: InstanceActorId)

        /// A Lemmy object identified only by its canonical ActivityPub URL.
        ///
        /// Used for body-text links to posts and users whose local id is not
        /// known until resolved. The handler resolves it via `resolve_object`
        /// under the current account, then routes by the returned object type.
        case objectAtURL(url: URL)

        /// A Lemmy instance, e.g. tapped from a bare `lemmy.world` in body text.
        case instance(instance: InstanceActorId)

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

            case let .community(name, instance):
                guard
                    let encodedName = name
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                    let encodedInstance = instance.actorId
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                else {
                    fatalError("Failed to url encode '\(self)'")
                }
                return URL(string: "info.ddenis.spud://internal/community?name=\(encodedName)&instance=\(encodedInstance)")!

            case let .objectAtURL(url):
                // `.urlQueryAllowed` permits `&`, `=` and `?`, which would let an
                // embedded URL's own query split the outer query on parse. Escape
                // those sub-delimiters so the inner URL round-trips intact.
                let queryValueAllowed = CharacterSet.urlQueryAllowed
                    .subtracting(CharacterSet(charactersIn: "&=?+"))
                guard
                    let encodedURL = url.absoluteString
                    .addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
                else {
                    fatalError("Failed to url encode '\(self)'")
                }
                return URL(string: "info.ddenis.spud://internal/resolve?url=\(encodedURL)")!

            case let .instance(instance):
                guard
                    let encodedInstance = instance.actorId
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                else {
                    fatalError("Failed to url encode '\(self)'")
                }
                return URL(string: "info.ddenis.spud://internal/instance?instance=\(encodedInstance)")!
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
        } else if components.path == "/community" {
            guard
                let name = components.queryItems?
                .first(where: { $0.name == "name" })?.value,
                let instanceString = components.queryItems?
                .first(where: { $0.name == "instance" })?.value,
                let instance = InstanceActorId(from: instanceString)
            else {
                logger.warning("Invalid internal link: \(absoluteString, privacy: .public)")
                return nil
            }

            return .community(name: name, instance: instance)
        } else if components.path == "/resolve" {
            guard
                let urlString = components.queryItems?
                .first(where: { $0.name == "url" })?.value,
                let resolvedURL = URL(string: urlString)
            else {
                logger.warning("Invalid internal link: \(absoluteString, privacy: .public)")
                return nil
            }

            return .objectAtURL(url: resolvedURL)
        } else if components.path == "/instance" {
            guard
                let instanceString = components.queryItems?
                .first(where: { $0.name == "instance" })?.value,
                let instance = InstanceActorId(from: instanceString)
            else {
                logger.warning("Invalid internal link: \(absoluteString, privacy: .public)")
                return nil
            }

            return .instance(instance: instance)
        }

        logger.warning("Invalid internal link: \(absoluteString, privacy: .public)")
        return nil
    }
}
