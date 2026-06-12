//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import SpudDataKit
import UIKit

private let logger = Logger.app

/// Minimal markdown comment composer presented as a sheet. Backs the reply
/// flow today; reused later for posts/edits/DMs by extending `ComposerTarget`.
final class ComposerViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService
    typealias Dependencies = OwnDependencies

    private let viewModel: ComposerViewModel

    private var observationTasks: [Task<Void, Never>] = []

    // MARK: UI

    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.delegate = self
        return textView
    }()

    private lazy var cancelButton = UIBarButtonItem(
        barButtonSystemItem: .cancel,
        target: self,
        action: #selector(cancelTapped)
    )

    private lazy var postButton = UIBarButtonItem(
        title: NSLocalizedString("Post", comment: "Composer submit button"),
        style: .done,
        target: self,
        action: #selector(postTapped)
    )

    private lazy var activityIndicator = UIActivityIndicatorView(style: .medium)

    // MARK: Functions

    init(
        target: ComposerTarget,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        viewModel = ComposerViewModel(
            target: target,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for task in observationTasks {
            task.cancel()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        bindViewModel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    private func setup() {
        view.backgroundColor = .systemBackground

        navigationItem.title = viewModel.navigationTitle
        navigationItem.leftBarButtonItem = cancelButton
        navigationItem.rightBarButtonItem = postButton

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
    }

    private func bindViewModel() {
        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await canPost in ObservationStream.values(of: { viewModel.canPost }) {
                self?.postButton.isEnabled = canPost
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await state in ObservationStream.values(of: { viewModel.submissionState }) {
                self?.apply(submissionState: state)
            }
        })
    }

    private func apply(submissionState state: ComposerSubmissionState) {
        switch state {
        case .editing:
            textView.isEditable = true
            navigationItem.rightBarButtonItem = postButton

        case .submitting:
            textView.isEditable = false
            activityIndicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: activityIndicator)

        case .finished:
            view.endEditing(true)
            dismiss(animated: true)

        case let .failed(message):
            textView.isEditable = true
            navigationItem.rightBarButtonItem = postButton
            // Reset to editing so a retry starts clean, then surface the error
            // while keeping the draft text intact.
            viewModel.didPresentFailure()
            presentErrorAlert(message: message)
        }
    }

    @objc
    private func cancelTapped() {
        view.endEditing(true)
        dismiss(animated: true)
    }

    @objc
    private func postTapped() {
        view.endEditing(false)
        Task { await viewModel.post() }
    }
}

// MARK: - UITextViewDelegate

extension ComposerViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        viewModel.bodyText = textView.text
    }
}

// MARK: - Presentation

extension ComposerViewController {
    /// Wraps the composer in a navigation controller configured as a
    /// medium/large detent sheet, ready to `present(...)`.
    static func makeSheet(
        target: ComposerTarget,
        accountKeychainId: String,
        dependencies: Dependencies
    ) -> UIViewController {
        let composer = ComposerViewController(
            target: target,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )
        let navigationController = UINavigationController(rootViewController: composer)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        return navigationController
    }
}
