//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Represents an "actor id" for an instance (Lemmy or otherwise).
///
/// The sole purpose of this type is to ensure consistency in handling of actorIds, regardless where
/// they come from - even if entered by a user in e.g. camel case.
public struct InstanceActorId: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let host: String
    public let port: Int?

    public static let invalid = InstanceActorId(host: "", port: nil)

    public var isValid: Bool {
        !host.isEmpty
    }

    public var debugDescription: String { hostWithPort }

    /// Returns actorId for the instance.
    ///
    /// See also ``url``.
    public var actorId: String {
        if let port {
            return "https://\(host):\(port)"
        } else {
            return "https://\(host)"
        }
    }

    /// Returns a more compact representation of ``actorId`` without a scheme.
    public var hostWithPort: String {
        if let port {
            return "\(host):\(port)"
        } else {
            return "\(host)"
        }
    }

    /// Returns a url for the instance or `nil` if the instance actor id is invalid.
    ///
    /// See also ``actorId``.
    public var url: URL? {
        guard isValid else { return nil }
        return URL(string: actorId)
    }

    public var description: String { actorId }

    // MARK: Functions

    init(host: String, port: Int?) {
        self.host = host
        self.port = port
    }

    public init?(from url: URL) {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
            let host = components.host,
            !host.isEmpty
        else {
            return nil
        }

        self.host = host.lowercased()
        port = components.port
    }

    public init?(from stringValue: String) {
        if
            let components = URLComponents(string: stringValue),
            let host = components.host
        {
            // easy, input could be parsed as url
            self.host = host.lowercased()
            port = components.port
            return
        }

        // Validate that input is just a domain with optional port.
        // This is very basic and naive validation meant to only
        // catch obvious accidental mistakes and typos.

        // TODO: use iOS 16 regex api
        let regex = #"([\w.-]+)(:(\d+))?"#
        // swiftformat:disable:next redundantStaticSelf
        let matches = Self.allMatches(regex: regex, in: stringValue)
        guard matches.count == 3 else {
            return nil
        }

        host = matches[0].lowercased()
        port = Int(matches[2])

        if host.isEmpty {
            return nil
        }
    }

    static func allMatches(regex: String, in input: String) -> [String] {
        // https://jayeshkawli.com/regular-expressions-in-swift-ios/
        guard
            let regex = try? NSRegularExpression(pattern: regex)
        else {
            return []
        }

        let results = regex.matches(
            in: input,
            range: NSRange(input.startIndex..<input.endIndex, in: input)
        )

        let finalResult = results.map { match in
            (0..<match.numberOfRanges).map { range -> String in
                let rangeBounds = match.range(at: range)
                guard let range = Range(rangeBounds, in: input) else {
                    return ""
                }
                return String(input[range])
            }
        }.filter { !$0.isEmpty }

        var allMatches: [String] = []

        // Iterate over the final result which includes all the matches and groups
        // We will store all the matching strings
        for result in finalResult {
            for (index, resultText) in result.enumerated() {
                // Skip the match. Go to the next elements which represent matching groups
                if index == 0 {
                    continue
                }
                allMatches.append(resultText)
            }
        }

        return allMatches
    }
}
