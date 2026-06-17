//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// An internal link that stays inside the body: a `[^n]` reference jumps to its
/// definition, and a definition's return affordance jumps back to the reference.
/// `MarkdownBodyView` decodes and handles these itself (scrolling within the host
/// scroll view) rather than forwarding them to the app's link delegate.
enum MarkdownFootnoteLink: Equatable {
    case toDefinition(label: String)
    case toReference(label: String)

    private static let scheme = "spud-markdown"
    private static let definitionHost = "footnote-def"
    private static let referenceHost = "footnote-ref"

    static func url(_ link: MarkdownFootnoteLink) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        switch link {
        case let .toDefinition(label):
            components.host = definitionHost
            components.queryItems = [URLQueryItem(name: "label", value: label)]
        case let .toReference(label):
            components.host = referenceHost
            components.queryItems = [URLQueryItem(name: "label", value: label)]
        }
        return components.url ?? URL(string: "\(scheme)://\(definitionHost)")!
    }

    init?(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.scheme,
              let label = components.queryItems?.first(where: { $0.name == "label" })?.value
        else { return nil }
        switch components.host {
        case Self.definitionHost: self = .toDefinition(label: label)
        case Self.referenceHost: self = .toReference(label: label)
        default: return nil
        }
    }
}
