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

    var longPressed: ((URL) -> Void)?

    // MARK: Private

    private var linkAttributes: [LinkAttribute] = [] {
        didSet {
            // The set of exposed link accessibility children changes whenever
            // the link ranges change, so invalidate the cache.
            cachedAccessibilityElements = nil
        }
    }

    private var standardTextAttributes: [Attribute] = []

    /// Cached per-link accessibility children, rebuilt when the links or the
    /// label bounds change. Lets repeated VoiceOver/XCUITest queries avoid
    /// re-laying out the text on every access.
    private var cachedAccessibilityElements: [Any]?
    private var cachedAccessibilityElementsBounds: CGRect = .null

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

        let longPressGestureRecognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(respondToLinkLabelLongPressed(_:))
        )
        longPressGestureRecognizer.delegate = self
        addGestureRecognizer(longPressGestureRecognizer)

        setupAttributes()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Whether `point` (in this label's coordinate space) lands on a tappable
    /// link range. Used by hosts that overlay their own tap gesture (e.g. the
    /// comment-collapse tap) to defer to link taps.
    func hasLink(at point: CGPoint) -> Bool {
        guard !linkAttributes.isEmpty else { return false }
        return link(atPoint: point) != nil
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
    func respondToLinkLabelLongPressed(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .began, !linkAttributes.isEmpty else {
            return
        }
        // Clear any touch-driven highlight before handing off so the link does
        // not stay visually highlighted behind the presented menu.
        highlightedLinkAttribute = nil
        let location = gestureRecognizer.location(in: self)
        switch link(atPoint: location) {
        case let .url(url):
            longPressed?(url)
        case .string, .none:
            break
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

// MARK: - Accessibility

extension LinkLabel {
    /// A label that exposes link children must be a *container*, not an
    /// element itself — otherwise UIKit reads the whole label and never
    /// descends to the per-link children. With no links we keep the default
    /// element behaviour so the text is still read.
    override var isAccessibilityElement: Bool {
        get { linkAttributes.isEmpty }
        set { /* computed from link state */ }
    }

    /// Each tappable link range is surfaced to VoiceOver (and XCUITest) as a
    /// separate child element framed at that range's bounding rect, carrying
    /// the link text as its label, the destination URL as its value, and the
    /// `.link` trait. This both lets VoiceOver users land on and activate
    /// individual links and lets XCUITest query a link by its text instead of
    /// tapping a fragile coordinate offset.
    ///
    /// When there are no links the label behaves as a plain accessibility
    /// element (its text is read as a whole), so we return `nil` to let UIKit
    /// fall back to the default behaviour.
    override var accessibilityElements: [Any]? {
        get {
            guard !linkAttributes.isEmpty, attributedText != nil else {
                return nil
            }
            if let cachedAccessibilityElements,
               cachedAccessibilityElementsBounds == bounds
            {
                return cachedAccessibilityElements
            }
            let elements = makeAccessibilityElements()
            cachedAccessibilityElements = elements
            cachedAccessibilityElementsBounds = bounds
            return elements
        }
        set {
            // The element list is computed; ignore external writes.
        }
    }

    private func makeAccessibilityElements() -> [Any] {
        // The whole-text element comes first so VoiceOver reads the full
        // attributed string, then offers each link as a focusable child.
        let textElement = UIAccessibilityElement(accessibilityContainer: self)
        textElement.accessibilityLabel = attributedText?.string
        textElement.accessibilityFrameInContainerSpace = bounds

        var elements: [Any] = [textElement]

        for linkAttribute in linkAttributes {
            let element = UIAccessibilityElement(accessibilityContainer: self)

            let linkText = (attributedText?.string as NSString?)?
                .substring(with: clampedRange(linkAttribute.range))
            element.accessibilityLabel = linkText

            switch linkAttribute.link {
            case let .url(url):
                element.accessibilityValue = url.absoluteString
            case let .string(string):
                element.accessibilityValue = string
            }

            element.accessibilityHint = "Double tap to open link"
            element.accessibilityTraits = [.link]
            element.accessibilityFrameInContainerSpace = boundingRect(for: linkAttribute.range)

            elements.append(element)
        }

        return elements
    }

    /// Clamps a range to the current attributed string's length, guarding
    /// against stale ranges produced before the text was replaced.
    private func clampedRange(_ range: NSRange) -> NSRange {
        let length = attributedText?.length ?? 0
        let location = max(0, min(range.location, length))
        let maxLength = length - location
        return NSRange(location: location, length: max(0, min(range.length, maxLength)))
    }

    /// The bounding rect (in this label's coordinate space) enclosing the glyphs
    /// for `range`, matching the text-container geometry used by
    /// `indexOfCharacter(at:)` so hit-test and accessibility frames agree.
    private func boundingRect(for range: NSRange) -> CGRect {
        guard let attributedText else { return bounds }

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer()
        let textStorage = NSTextStorage(attributedString: attributedText)

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = lineBreakMode
        textContainer.maximumNumberOfLines = numberOfLines
        textContainer.size = bounds.size

        let textBoundingBox = layoutManager.usedRect(for: textContainer)
        let textContainerOffset = CGPoint(
            x: (bounds.size.width - textBoundingBox.size.width) * 0.5 - textBoundingBox.origin.x,
            y: (bounds.size.height - textBoundingBox.size.height) * 0.5 - textBoundingBox.origin.y
        )

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: clampedRange(range),
            actualCharacterRange: nil
        )
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

        return rect.offsetBy(dx: textContainerOffset.x, dy: textContainerOffset.y)
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
