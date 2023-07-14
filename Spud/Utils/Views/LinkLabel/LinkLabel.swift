//
//  LinkLabel.swift
//  TwIM
//
//  Created by Andrew Hart on 06/08/2015.
//  Copyright (c) 2015 Project Dent. All rights reserved.
//

import UIKit
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

fileprivate func <= <T: Comparable>(lhs: T?, rhs: T?) -> Bool {
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
    let url: URL
    let range: NSRange

    init(url: URL, range: NSRange) {
        self.url = url
        self.range = range
    }
}

class LinkLabel: UILabel {
    // MARK: Public

    var linkTextAttributes: [NSAttributedString.Key: AnyObject] {
        didSet {
            self.setupAttributes()
        }
    }

    /// Text attributes displayed when a link has been highlighted
    var highlightedLinkTextAttributes: [NSAttributedString.Key: AnyObject] {
        didSet {
            self.setupAttributes()
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

            newValue.enumerateAttributes(in: range, options: [], using: { (attributes, range, _) in
                attributes.forEach { (key, value) in
                    switch key {
                    case .link:
                        guard let urlValue = value as? URL else {
                            assertionFailure()
                            return
                        }

                        let linkAttribute = LinkAttribute(
                            url: urlValue,
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

            self.standardTextAttributes = standardAttributes
            self.linkAttributes = linkAttributes

            super.attributedText = mutableAttributedText

            self.setupAttributes()
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
            if self.highlightedLinkAttribute !== oldValue {
                self.setupAttributes()
            }
        }
    }

    // MARK: Functions

    override init(frame: CGRect) {
        linkTextAttributes = [
            .underlineStyle: NSNumber(value: NSUnderlineStyle.single.rawValue as Int)
        ]

        highlightedLinkTextAttributes = [
            .underlineStyle: NSNumber(value: NSUnderlineStyle.single.rawValue as Int)
        ]

        super.init(frame: frame)

        self.isUserInteractionEnabled = true

        let touchGestureRecognizer = TouchGestureRecognizer(
            target: self,
            action: #selector(respondToLinkLabelTouched(_:))
        )
        touchGestureRecognizer.delegate = self
        self.addGestureRecognizer(touchGestureRecognizer)

        let tapGestureRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(respondToLinkLabelTapped(_:))
        )
        tapGestureRecognizer.delegate = self
        self.addGestureRecognizer(tapGestureRecognizer)

        self.setupAttributes()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func link(atPoint point: CGPoint) -> URL? {
        let indexOfCharacter = self.indexOfCharacter(at: point)

        if indexOfCharacter == nil {
            return nil
        }

        for linkAttribute in self.linkAttributes {
            if indexOfCharacter! >= linkAttribute.range.location &&
                indexOfCharacter! <= linkAttribute.range.location + linkAttribute.range.length {
                return linkAttribute.url
            }
        }

        return nil
    }

    @objc func respondToLinkLabelTouched(_ gestureRecognizer: TouchGestureRecognizer) {
        if self.linkAttributes.count == 0 {
            return
        }

        //Possible states are began or cancelled
        switch gestureRecognizer.state {
        case .began, .changed:
            let location = gestureRecognizer.location(in: self)
            if let indexOfCharacterTouched = indexOfCharacter(at: location) {
                for linkAttribute in self.linkAttributes {
                    let linkRange = linkAttribute.range

                    let touchedInsideLink =
                        indexOfCharacterTouched >= linkRange.location &&
                        indexOfCharacterTouched <= linkRange.location + linkRange.length

                    if touchedInsideLink {
                        self.highlightedLinkAttribute = linkAttribute
                        return
                    }
                }
            }

            self.highlightedLinkAttribute = nil

        case .ended, .failed, .cancelled:
            self.highlightedLinkAttribute = nil

        case .possible:
            break

        @unknown default:
            assertionFailure()
        }
    }

    @objc func respondToLinkLabelTapped(_ gestureRecognizer: UITapGestureRecognizer) {
        if self.linkAttributes.count == 0 {
            return
        }

        let location = gestureRecognizer.location(in: self)
        guard let indexOfCharacterTouched = indexOfCharacter(at: location) else {
            return
        }

        for linkAttribute in self.linkAttributes {
            let linkRange = linkAttribute.range

            let touchedInsideLink =
                indexOfCharacterTouched >= linkRange.location &&
                indexOfCharacterTouched <= linkRange.location + linkRange.length

            if touchedInsideLink {
                tapped?(linkAttribute.url)
                break
            }
        }
    }

    private func setupAttributes() {
        if self.attributedText == nil {
            super.attributedText = nil
            return
        }

        let mutableAttributedText = NSMutableAttributedString(attributedString: self.attributedText!)

        mutableAttributedText.removeAttributes()

        for attribute in self.standardTextAttributes {
            mutableAttributedText.addAttribute(attribute.attributeName, value: attribute.value, range: attribute.range)
        }

        for linkAttribute in self.linkAttributes {
            if linkAttribute === self.highlightedLinkAttribute {
                for (attributeName, value): (NSAttributedString.Key, AnyObject) in self.highlightedLinkTextAttributes {
                    mutableAttributedText.addAttribute(attributeName, value: value, range: linkAttribute.range)
                }
            } else {
                for (attributeName, value): (NSAttributedString.Key, AnyObject) in self.linkTextAttributes {
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
        return true
    }
}
