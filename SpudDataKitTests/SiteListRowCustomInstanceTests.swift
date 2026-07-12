//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import Testing
@testable import SpudDataKit

/// `SiteListRow.forTypedInstance` builds the bare row used for a user-typed
/// instance address that isn't in the Explorer directory (see
/// `CustomInstanceEntryViewController` in the app target, and the `MainWindow`
/// DEBUG UI-test seam, which both construct a row this way).
struct SiteListRowCustomInstanceTests {
    @Test
    func forTypedInstance_carriesInstanceAndHost() throws {
        let instance = try #require(InstanceActorId(from: "lemmy.example.com"))
        let row = SiteListRow.forTypedInstance(instance)

        #expect(row.instance == instance)
        #expect(row.hostname == "lemmy.example.com")
    }

    @Test
    func forTypedInstance_defaultsDirectoryFieldsToNil() throws {
        let instance = try #require(InstanceActorId(from: "lemmy.example.com"))
        let row = SiteListRow.forTypedInstance(instance)

        #expect(row.id == 0)
        #expect(row.name == nil)
        #expect(row.descriptionText == nil)
        #expect(row.iconUrl == nil)
        #expect(row.score == 0)
        #expect(row.usersTotal == nil)
        #expect(row.usersActiveMonth == nil)
        #expect(row.uptimeAllTime == nil)
        #expect(row.isNsfw == false)
        #expect(row.languageCodes.isEmpty)
        #expect(row.tags.isEmpty)
    }

    /// The register affordance stays reachable for a typed instance since we
    /// cannot know the real registration mode without a `getSite` call.
    @Test
    func forTypedInstance_isOpenRegistrationTrue() throws {
        let instance = try #require(InstanceActorId(from: "lemmy.example.com"))
        let row = SiteListRow.forTypedInstance(instance)

        #expect(row.isOpenRegistration == true)
    }
}
