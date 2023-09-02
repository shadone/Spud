//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import UIKit

private let logger = Logger(.utils)

public extension UIImage {
    func fittingHeight(for maxWidth: CGFloat) -> CGFloat {
        guard size.height != 0 else {
            logger.assertionFailure("Why zero height image?")
            return 42
        }
        let aspectRatio = size.width / size.height
        return maxWidth / aspectRatio
    }
}
