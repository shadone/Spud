//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

extension URL {
    enum Lemmy {
        case person(name: String)

        var url: URL {
            switch self {
            case let .person(name):
                guard
                    let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                else {
                    fatalError("Failed to url encode '\(name)'")
                }
                return URL(string: "spud://lemmy/person?name=\(encodedName)")!
            }
        }
    }

    var lemmy: Lemmy? {
        guard
            let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
            components.host == "lemmy"
        else {
            return nil
        }

        if components.path == "/person" {
            guard
                let name = components.queryItems?.first(where: { $0.name == "name" })?.value
            else {
                assertionFailure()
                return nil
            }

            return .person(name: name)
        }

        return nil
    }
}
