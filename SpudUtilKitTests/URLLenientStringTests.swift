//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct URLLenientStringTests {
    @Test
    func knownProblematicUrls() {
        #expect(
            URL(lenientString: "https://matrix.to/#/#lemmy-admin-support-topics:discuss.online")?.absoluteString ==
                "https://matrix.to/#/%23lemmy-admin-support-topics:discuss.online"
        )

        #expect(
            URL(lenientString: "https://www.reddit.com/r/oslo/comments/i63epw/lyst_til_å_finne_en_psykolog_som_hjelper_noen_med/")?.absoluteString ==
                "https://www.reddit.com/r/oslo/comments/i63epw/lyst_til_%C3%A5_finne_en_psykolog_som_hjelper_noen_med/"
        )
    }
}
