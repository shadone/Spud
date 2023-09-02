//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

private let logger = Logger(.auth)

struct LemmyCredential: Codable {
    let jwt: String
}

extension LemmyCredential {
    func toString() -> String? {
        let data: Data

        do {
            // TODO: shall we decode jwt and store the metadata e.g. claims?
            data = try JSONEncoder().encode(self)
        } catch {
            logger.error("Failed to encode credential: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func fromString(_ stringValue: String) -> LemmyCredential? {
        guard let data = stringValue.data(using: .utf8) else {
            logger.assertionFailure()
            return nil
        }
        do {
            return try JSONDecoder().decode(self, from: data)
        } catch {
            logger.error("Failed to decode credential: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
