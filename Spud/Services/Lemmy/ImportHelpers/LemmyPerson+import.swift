//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log
import LemmyKit

private let logger = Logger(.app)

extension LemmyPerson {
    convenience init(
        _ model: Person,
        site: LemmySite,
        in context: NSManagedObjectContext
    ) {
        self.init(context: context)

        personId = model.id

        set(from: model)

        createdAt = Date()
        updatedAt = createdAt

        self.site = site
    }

    private func getOrCreatePersonInfo() -> LemmyPersonInfo? {
        func createPersonInfo() -> LemmyPersonInfo? {
            guard let context = managedObjectContext else {
                assertionFailure()
                return nil
            }

            let personInfo = LemmyPersonInfo(in: context)
            personInfo.person = self

            return personInfo
        }

        guard let personInfo else {
            personInfo = createPersonInfo()
            return personInfo
        }
        return personInfo
    }

    func set(from model: LocalUserView) {
        assert(personId == model.local_user.person_id)
        //self.personId = model.local_user.person_id

        let personInfo = getOrCreatePersonInfo()
        personInfo?.set(from: model)
    }

    func set(from model: Person) {
        assert(personId == model.id)

        let personInfo = getOrCreatePersonInfo()
        personInfo?.set(from: model)

        updatedAt = Date()
    }

    func set(from model: PersonView) {
        assert(personId == model.person.id)

        set(from: model.person)

        let personInfo = getOrCreatePersonInfo()
        personInfo?.set(from: model)

        updatedAt = Date()
    }

    static func upsert(
        _ model: Person,
        site: LemmySite,
        in context: NSManagedObjectContext
    ) -> LemmyPerson {
        let request = LemmyPerson.fetchRequest() as NSFetchRequest<LemmyPerson>
        request.predicate = NSPredicate(
            format: "personId == %d && site == %@",
            model.id, site
        )
        do {
            let results = try context.fetch(request)
            if results.count == 0 {
                return LemmyPerson(model, site: site, in: context)
            } else if results.count == 1 {
                let person = results[0]
                // TODO: is it ok to set here and touch updatedAt since we do partial update.
                // The aggregates data is not available at this point.
                // E.g. when fetching posts we find the creator in Person and update with
                // whatever info the Post contains, but it isn't everything.
                person.set(from: model)
                person.updatedAt = Date()
                return person
            } else {
                assertionFailure("Found \(results.count) persons with id '\(model.id)'")
                return results[0]
            }
        } catch {
            logger.error("""
                Failed to fetch persons for upserting: \
                \(String(describing: error), privacy: .public)
                """)
            assertionFailure()
            return LemmyPerson(model, site: site, in: context)
        }
    }
}
