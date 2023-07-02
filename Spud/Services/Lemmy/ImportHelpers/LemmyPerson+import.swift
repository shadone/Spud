//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log
import LemmyKit

extension LemmyPerson {
    func set(from model: LocalUserView) {
        guard let context = managedObjectContext else {
            assertionFailure()
            return
        }

        func createPersonInfo() -> LemmyPersonInfo {
            let personInfo = LemmyPersonInfo(in: context)
            personInfo.person = self
            return personInfo
        }

        self.personId = model.local_user.person_id

        let personInfo = self.personInfo ?? createPersonInfo()
        self.personInfo = personInfo

        personInfo.set(from: model)
    }
}
