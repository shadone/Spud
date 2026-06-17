//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// A read-only screen that renders a post's title and body as selectable,
/// copyable text. Reached from the post detail overflow menu's "Select Text"
/// action. Shows the raw text (the markdown source for the body) so the reader
/// can select and copy any range; iOS provides the selection and copy UI.
final class SelectableTextViewController: UIViewController {
    private let postTitle: String
    private let postBody: String?

    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 24, right: 12)
        textView.adjustsFontForContentSizeCategory = true
        textView.accessibilityIdentifier = "selectableText"
        return textView
    }()

    init(title: String, body: String?) {
        postTitle = title
        postBody = body
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Select Text", comment: "Title of the post text-selection screen")
        view.backgroundColor = Theme.background

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(done)
        )

        textView.attributedText = makeAttributedText()
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Title in a bold, Dynamic-Type-scaled heading; body in the body style.
    /// Both ranges are selectable.
    private func makeAttributedText() -> NSAttributedString {
        let result = NSMutableAttributedString()

        let titleFont: UIFont
        if let boldDescriptor = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .title2)
            .withSymbolicTraits(.traitBold)
        {
            titleFont = UIFont(descriptor: boldDescriptor, size: 0)
        } else {
            titleFont = UIFont.preferredFont(forTextStyle: .title2)
        }
        result.append(NSAttributedString(
            string: postTitle,
            attributes: [.font: titleFont, .foregroundColor: UIColor.label]
        ))

        if let body = postBody, !body.isEmpty {
            let bodyFont = UIFont.preferredFont(forTextStyle: .body)
            result.append(NSAttributedString(string: "\n\n", attributes: [.font: bodyFont]))
            result.append(NSAttributedString(
                string: body,
                attributes: [.font: bodyFont, .foregroundColor: UIColor.label]
            ))
        }

        return result
    }

    @objc
    private func done() {
        dismiss(animated: true)
    }
}
