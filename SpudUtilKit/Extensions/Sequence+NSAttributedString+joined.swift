//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public protocol NSAttributedStringProtocol {}
extension NSAttributedString: NSAttributedStringProtocol {}

public extension Sequence where Element: NSAttributedStringProtocol {
    func joined() -> NSMutableAttributedString {
        reduce(into: NSMutableAttributedString()) { result, element in
            let attributedString = element as! NSAttributedString
            result.append(attributedString)
        }
    }
}

public extension Sequence where Element == NSAttributedStringProtocol? {
    func joined() -> NSMutableAttributedString {
        compactMap { $0 }
            .reduce(into: NSMutableAttributedString()) { result, element in
                let attributedString = element as! NSAttributedString
                result.append(attributedString)
            }
    }
}
