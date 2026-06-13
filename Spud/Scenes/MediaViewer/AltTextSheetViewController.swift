//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Bottom sheet showing an image's full description (alt text), opened from the
/// media-viewer caption pill. Mirrors the Claude Design ALT sheet: a dark sheet
/// with a grabber, an "ALT — Image description" header with a Done button, and
/// the description text. Sized to fit its content, draggable up to full height.
final class AltTextSheetViewController: UIViewController {
    private let altText: String
    private var didConfigureDetent = false

    init(altText: String) {
        self.altText = altText
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
            // Replaced with a content-fitting custom detent once laid out.
            sheet.detents = [.medium(), .large()]
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString(
            "Image description",
            comment: "Title of the media-viewer alt-text sheet"
        )
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var doneButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = NSLocalizedString("Done", comment: "Dismisses the alt-text sheet")
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textColor = UIColor(white: 0.84, alpha: 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        label.attributedText = NSAttributedString(
            string: altText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                .paragraphStyle: paragraph,
            ]
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var contentStack: UIStackView = {
        let header = UIStackView(arrangedSubviews: [
            AltBadgeLabel(pointSize: 11),
            titleLabel,
            doneButton,
        ])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8
        // Under the stack's default fill distribution, the low-hugging title
        // stretches to take the slack, pushing Done to the trailing edge.
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [header, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        // The viewer is a black/dark context; the sheet matches the design's
        // near-black surface rather than the themed system background.
        view.backgroundColor = UIColor(red: 0.102, green: 0.102, blue: 0.110, alpha: 1)

        view.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard
            let sheet = sheetPresentationController,
            !didConfigureDetent,
            view.bounds.width > 0
        else { return }
        didConfigureDetent = true

        let fittingHeight = contentStack.systemLayoutSizeFitting(
            CGSize(width: view.bounds.width - 40, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        // header top inset + bottom inset + grabber breathing room + safe area.
        let total = fittingHeight + 16 + 20 + 24 + view.safeAreaInsets.bottom

        sheet.animateChanges {
            sheet.detents = [
                .custom { context in min(total, context.maximumDetentValue * 0.85) },
                .large(),
            ]
        }
    }

    @objc
    private func doneTapped() {
        dismiss(animated: true)
    }
}
