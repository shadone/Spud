//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Asynchronously provides a decoded image for a body image URL. The host
/// supplies it: the Lab synthesizes one offline; Spud wires its `ImageService`
/// at integration. Invoked on the main actor (an implementation may hop to a
/// background queue internally and resume on the main actor). Returning `nil`
/// puts the image block into its failed state.
public typealias MarkdownImageLoader = @MainActor (URL) async -> UIImage?
