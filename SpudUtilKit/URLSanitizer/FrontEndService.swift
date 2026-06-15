//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A third-party site that can be redirected to a privacy-preserving
/// front-end. The raw value is the stable key persisted in the config.
public enum FrontEndService: String, Codable, CaseIterable, Sendable {
    case twitter
    case youtube
    case reddit
    case imgur
}
