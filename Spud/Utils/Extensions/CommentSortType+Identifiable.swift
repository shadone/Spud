//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

// Marking as @retroactive here. This is ahcky and wrong, but we need it to be Identifiable
// and the type is generated by OpenAPI generator where we cannot influence its protocol
// conformance.
extension Components.Schemas.CommentSortType: @retroactive Identifiable {
    public var id: String { rawValue }
}
