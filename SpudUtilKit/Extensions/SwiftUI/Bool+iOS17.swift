//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension Bool {
     static var iOS17: Bool {
         if #available(iOS 17, *) {
             return true
         } else {
             return false
         }
     }
 }
