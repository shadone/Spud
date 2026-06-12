//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.LoginResponse {
    static func fake(
        jwt: String? = nil,
        registrationCreated: Bool = false,
        verifyEmailSent: Bool = false
    ) -> Components.Schemas.LoginResponse {
        .init(
            jwt: jwt,
            registration_created: registrationCreated,
            verify_email_sent: verifyEmailSent
        )
    }
}
