//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Lemmy.LoginResponse {
    static func fake(
        jwt: String? = nil,
        registrationCreated: Bool = false,
        verifyEmailSent: Bool = false
    ) -> Lemmy.LoginResponse {
        .init(
            jwt: jwt,
            registration_created: registrationCreated,
            verify_email_sent: verifyEmailSent
        )
    }
}
