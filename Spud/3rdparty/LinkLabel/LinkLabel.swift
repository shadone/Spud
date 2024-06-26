//
//  LinkLabel.swift
//  TwIM
//
//  Created by Andrew Hart on 06/08/2015.
//  Copyright (c) 2015 Project Dent. All rights reserved.
//

import OSLog
import UIKit

private let logger = Logger.app

private func < <T: Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l < r
    case (nil, _?):
        return true
    default:
        return false
    }
}

private func >= <T: Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l >= r
    default:
        return !(lhs < rhs)
    }
}

private func <= <T: Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l <= r
    default:
        return !(rhs < lhs)
    }
}

private class Attribute {
    let attributeName: NSAttributedString.Key
    let value: Any
    let range: NSRange

    init(attributeName: NSAttributedString.Key, value: Any, range: NSRange) {
        self.attributeName = attributeName
        self.value = value
        self.range = range
    }
}

private class LinkAttribute {
    enum Link {
        case url(URL)
        case string(String)
    }

    let link: Link
    let range: NSRange

    init(link: Link, range: NSRange) {
        self.link = link
        self.range = range
    }
}

class LinkLabel: UILabel {
    // MARK: Public

    var linkTextAttributes: [NSAttributedString.Key: AnyObject] {
        didSet {
            setupAttributes()
        }
    }

    /// Text attributes displayed when a link has been highlighted
    var highlightedLinkTextAttributes: [NSAttributedString.Key: AnyObject] {
        didSet {
            setupAttributes()
        }
    }

    override var attributedText: NSAttributedString? {
        set {
            guard let newValue else {
                super.attributedText = newValue
                return
            }

            let range = NSMakeRange(0, newValue.length)

            let mutableAttributedText = NSMutableAttributedString(attributedString: newValue)

            var standardAttributes: [Attribute] = []
            var linkAttributes: [LinkAttribute] = []

            newValue.enumerateAttributes(in: range, options: [], using: { attributes, range, _ in
                for (key, value) in attributes {
                    switch key {
                    case .link:
                        let link: LinkAttribute.Link
                        if let urlValue = value as? URL {
                            link = .url(urlValue)
                        } else if let stringValue = value as? String {
                            if let urlValue = URL(lenientString: stringValue) {
                                link = .url(urlValue)
                            } else {
                                logger.warning("Attribute contains a link that cannot be represented as URL: '\(stringValue, privacy: .public)'")
                                link = .string(stringValue)
                            }
                        } else {
                            logger.assertionFailure("Got link that is neither URL or a String: \(type(of: value)): \(value)")
                            continue
                        }

                        let linkAttribute = LinkAttribute(
                            link: link,
                            range: range
                        )
                        linkAttributes.append(linkAttribute)

                    default:
                        let attribute = Attribute(
                            attributeName: key,
                            value: value,
                            range: range
                        )
                        standardAttributes.append(attribute)
                    }
                }
            })

            standardTextAttributes = standardAttributes
            self.linkAttributes = linkAttributes

            super.attributedText = mutableAttributedText

            setupAttributes()
        }

        get {
            super.attributedText
        }
    }

    var tapped: ((URL) -> Void)?

    // MARK: Private

    private var linkAttributes: [LinkAttribute] = []

    private var standardTextAttributes: [Attribute] = []

    private var highlightedLinkAttribute: LinkAttribute? {
        didSet {
            if highlightedLinkAttribute !== oldValue {
                setupAttributes()
            }
        }
    }

    // MARK: Functions

    override init(frame: CGRect) {
        linkTextAttributes = [
            .underlineStyle: NSNumber(value: NSUnderlineStyle.single.rawValue as Int),
        ]

        highlightedLinkTextAttributes = [
            .underlineStyle: NSNumber(value: NSUnderlineStyle.single.rawValue as Int),
        ]

        super.init(frame: frame)

        isUserInteractionEnabled = true

        let touchGestureRecognizer = TouchGestureRecognizer(
            target: self,
            action: #selector(respondToLinkLabelTouched(_:))
        )
        touchGestureRecognizer.delegate = self
        addGestureRecognizer(touchGestureRecognizer)

        let tapGestureRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(respondToLinkLabelTapped(_:))
        )
        tapGestureRecognizer.delegate = self
        addGestureRecognizer(tapGestureRecognizer)

        setupAttributes()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func link(atPoint point: CGPoint) -> LinkAttribute.Link? {
        let indexOfCharacter = indexOfCharacter(at: point)

        if indexOfCharacter == nil {
            return nil
        }

        for linkAttribute in linkAttributes {
            if indexOfCharacter! >= linkAttribute.range.location,
               indexOfCharacter! <= linkAttribute.range.location + linkAttribute.range.length
            {
                return linkAttribute.link
            }
        }

        return nil
    }

    @objc
    func respondToLinkLabelTouched(_ gestureRecognizer: TouchGestureRecognizer) {
        if linkAttributes.isEmpty {
            return
        }

        // Possible states are began or cancelled
        switch gestureRecognizer.state {
        case .began, .changed:
            let location = gestureRecognizer.location(in: self)
            if let indexOfCharacterTouched = indexOfCharacter(at: location) {
                for linkAttribute in linkAttributes {
                    let linkRange = linkAttribute.range

                    let touchedInsideLink =
                        indexOfCharacterTouched >= linkRange.location &&
                        indexOfCharacterTouched <= linkRange.location + linkRange.length

                    if touchedInsideLink {
                        highlightedLinkAttribute = linkAttribute
                        return
                    }
                }
            }

            highlightedLinkAttribute = nil

        case .ended, .failed, .cancelled:
            highlightedLinkAttribute = nil

        case .possible:
            break

        @unknown default:
            logger.assertionFailure()
        }
    }

    @objc
    func respondToLinkLabelTapped(_ gestureRecognizer: UITapGestureRecognizer) {
        if linkAttributes.isEmpty {
            return
        }

        let location = gestureRecognizer.location(in: self)
        guard let indexOfCharacterTouched = indexOfCharacter(at: location) else {
            return
        }

        for linkAttribute in linkAttributes {
            let linkRange = linkAttribute.range

            let touchedInsideLink =
                indexOfCharacterTouched >= linkRange.location &&
                indexOfCharacterTouched <= linkRange.location + linkRange.length

            if touchedInsideLink {
                switch linkAttribute.link {
                case let .url(url):
                    tapped?(url)

                case let .string(stringValue):
                    logger.warning("Tapped on a link that cannot be represented as URL: '\(stringValue, privacy: .public)'")
                }

                break
            }
        }
    }

    private func setupAttributes() {
        if attributedText == nil {
            super.attributedText = nil
            return
        }

        let mutableAttributedText = NSMutableAttributedString(attributedString: attributedText!)

        mutableAttributedText.removeAttributes()

        for attribute in standardTextAttributes {
            mutableAttributedText.addAttribute(attribute.attributeName, value: attribute.value, range: attribute.range)
        }

        for linkAttribute in linkAttributes {
            if linkAttribute === highlightedLinkAttribute {
                for (attributeName, value): (NSAttributedString.Key, AnyObject) in highlightedLinkTextAttributes {
                    mutableAttributedText.addAttribute(attributeName, value: value, range: linkAttribute.range)
                }
            } else {
                for (attributeName, value): (NSAttributedString.Key, AnyObject) in linkTextAttributes {
                    mutableAttributedText.addAttribute(attributeName, value: value, range: linkAttribute.range)
                }
            }
        }

        super.attributedText = mutableAttributedText
    }
}

// MARK: - UIGestureRecognizerDelegate

extension LinkLabel: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
