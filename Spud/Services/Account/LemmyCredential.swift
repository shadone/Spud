//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import os.log

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
            os_log("Failed to encode credential: %{public}",
                   log: .auth, type: .error,
                   error.localizedDescription)
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func fromString(_ stringValue: String) -> LemmyCredential? {
        guard let data = stringValue.data(using: .utf8) else {
            assertionFailure()
            return nil
        }
        do {
            return try JSONDecoder().decode(self, from: data)
        } catch {
            os_log("Failed to decode credential: %{public}@",
                   log: .auth, type: .error,
                   error.localizedDescription)
            return nil
        }
    }
}
