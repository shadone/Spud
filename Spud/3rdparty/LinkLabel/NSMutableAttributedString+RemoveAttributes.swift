//
//  NSMutableAttributedString+RemoveAttributes.swift
//  TwIM
//
//  Created by Andrew Hart on 06/08/2015.
//  Copyright (c) 2015 Project Dent. All rights reserved.
//

import Foundation

extension NSMutableAttributedString {
    func removeAttributes() {
        let range = NSMakeRange(0, length)
        removeAttributes(range: range)
    }

    func removeAttributes(range: NSRange) {
        enumerateAttributes(in: range, options: []) { attributes, range, _ in
            for attribute in attributes {
                self.removeAttribute(attribute.key, range: range)
            }
        }
    }
}
