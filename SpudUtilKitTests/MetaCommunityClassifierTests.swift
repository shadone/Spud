//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudUtilKit

struct MetaCommunityClassifierTests {
    @Test
    func nameMatchingInstanceDomainLabelIsHigh() {
        let c = MetaCommunityClassifier.classify(
            name: "tchncs", title: "tchncs", instanceHost: "discuss.tchncs.de", siteName: nil
        )
        #expect(c.isMeta)
        #expect(c.confidence == .high)
        #expect(c.reason == .nameMatchesInstance)
    }

    @Test
    func nameMatchingSiteNameIsHigh() {
        let c = MetaCommunityClassifier.classify(
            name: "lemmyworld", title: "Lemmy.World Meta", instanceHost: "lemmy.world", siteName: "Lemmy.World"
        )
        #expect(c.isMeta)
        #expect(c.confidence == .high)
    }

    @Test
    func strongKeywordIsHigh() {
        for name in ["meta", "announcements", "changelog", "sitenews", "site", "instance"] {
            let c = MetaCommunityClassifier.classify(
                name: name, title: nil, instanceHost: "example.social", siteName: nil
            )
            #expect(c.isMeta, "\(name) should be meta")
            #expect(c.confidence == .high, "\(name) should be high")
            #expect(c.reason == .strongKeyword)
        }
    }

    @Test
    func broadKeywordIsLow() {
        for name in ["support", "help", "feedback", "news", "updates", "welcome", "general", "lounge", "rules"] {
            let c = MetaCommunityClassifier.classify(
                name: name, title: nil, instanceHost: "example.social", siteName: nil
            )
            #expect(c.isMeta, "\(name) should be meta")
            #expect(c.confidence == .low, "\(name) should be low")
            #expect(c.reason == .broadKeyword)
        }
    }

    @Test
    func multiWordTitleMatchesOnToken() {
        // Broad recall: the NAME token "general" (not the title) matches the
        // broad keyword set.
        let c = MetaCommunityClassifier.classify(
            name: "general_discussion", title: "General Discussion", instanceHost: "example.social", siteName: nil
        )
        #expect(c.isMeta)
        #expect(c.confidence == .low)
    }

    @Test
    func titleBorneStrongKeywordIsHigh() {
        // Recall: a generic name with a strong keyword only in the title is
        // still flagged HIGH.
        let c = MetaCommunityClassifier.classify(
            name: "offtopic", title: "Site Announcements",
            instanceHost: "example.social", siteName: nil
        )
        #expect(c.isMeta)
        #expect(c.confidence == .high)
        #expect(c.reason == .strongKeyword)
    }

    @Test
    func broadKeywordInTitleAloneDoesNotFlag() {
        // Broad keywords are name-only: "news" in the title must NOT flag an
        // ordinary community.
        let c = MetaCommunityClassifier.classify(
            name: "photos", title: "Photo News",
            instanceHost: "example.social", siteName: nil
        )
        #expect(!c.isMeta)
    }

    @Test
    func multiWordSiteNameMatchesTitle() {
        // Identity match via the whole title against a multi-word site name.
        let c = MetaCommunityClassifier.classify(
            name: "chat", title: "Lemmy World",
            instanceHost: "lemmy.world", siteName: "Lemmy World"
        )
        #expect(c.isMeta)
        #expect(c.confidence == .high)
        #expect(c.reason == .nameMatchesInstance)
    }

    @Test
    func ordinaryCommunityIsNotMeta() {
        let c = MetaCommunityClassifier.classify(
            name: "photography", title: "Photography", instanceHost: "lemmy.world", siteName: "Lemmy.World"
        )
        #expect(!c.isMeta)
        #expect(c.reason == .notMeta)
    }

    @Test
    func domainLabelMatchIsEqualityNotSubstring() {
        // "world" is the TLD-adjacent label of lemmy.world; the primary label is
        // "lemmy". A community named "world" must NOT be flagged by the domain.
        let c = MetaCommunityClassifier.classify(
            name: "world", title: "World News", instanceHost: "lemmy.world", siteName: nil
        )
        #expect(!c.isMeta)
    }

    @Test
    func normalizationIgnoresCaseAndSeparators() {
        let c = MetaCommunityClassifier.classify(
            name: "Site-News", title: nil, instanceHost: "example.social", siteName: nil
        )
        #expect(c.isMeta)
        #expect(c.confidence == .high) // "sitenews" is strong
    }

    @Test
    func strongWinsOverBroadWhenBothPresent() {
        let c = MetaCommunityClassifier.classify(
            name: "meta", title: "Support & Meta", instanceHost: "example.social", siteName: nil
        )
        #expect(c.confidence == .high)
        #expect(c.reason == .strongKeyword)
    }
}
