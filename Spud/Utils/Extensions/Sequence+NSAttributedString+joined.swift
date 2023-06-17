//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

protocol NSAttributedStringProtocol {}
extension NSAttributedString: NSAttributedStringProtocol {}

extension Sequence where Element: NSAttributedStringProtocol {
    func joined() -> NSMutableAttributedString {
        reduce(into: NSMutableAttributedString()) { result, element in
            let attributedString = element as! NSAttributedString
            result.append(attributedString)
        }
    }
}

extension Sequence where Element == NSAttributedStringProtocol? {
    func joined() -> NSMutableAttributedString {
        compactMap { $0 }
            .reduce(into: NSMutableAttributedString()) { result, element in
                let attributedString = element as! NSAttributedString
                result.append(attributedString)
            }
    }
}
