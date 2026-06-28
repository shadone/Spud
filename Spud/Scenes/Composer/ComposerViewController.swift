//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import SpudDataKit
import SpudUIKit
import UIKit

private let logger = Logger.app

/// Minimal markdown comment composer presented as a sheet. Backs the reply
/// flow today; reused later for posts/edits/DMs by extending `ComposerTarget`.
final class ComposerViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasImageService
    typealias Dependencies = OwnDependencies

    private let dependencies: OwnDependencies
    private let viewModel: ComposerViewModel

    private var observationTasks: [Task<Void, Never>] = []

    // MARK: UI

    private lazy var editorView: MarkdownEditorView = {
        let editor = MarkdownEditorView()
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        editor.onTextChange = { [weak self] text in
            self?.viewModel.bodyText = text
            self?.viewModel.bodyDidChange()
        }
        editor.onPreviewLinkTapped = { [weak self] url in
            self?.openPreviewLink(url)
        }
        editor.imageService = dependencies.imageService
        return editor
    }()

    private lazy var modeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            NSLocalizedString("Write", comment: "Composer write-mode segment"),
            NSLocalizedString("Preview", comment: "Composer preview-mode segment"),
        ])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        return control
    }()

    private lazy var cancelButton = UIBarButtonItem(
        barButtonSystemItem: .cancel,
        target: self,
        action: #selector(cancelTapped)
    )

    private lazy var postButton = UIBarButtonItem(
        title: viewModel.submitButtonTitle,
        style: .done,
        target: self,
        action: #selector(postTapped)
    )

    private lazy var activityIndicator = UIActivityIndicatorView(style: .medium)

    // MARK: Functions

    init(
        target: ComposerTarget,
        accountKeychainId: String,
        initialBody: String? = nil,
        dependencies: Dependencies
    ) {
        self.dependencies = dependencies
        viewModel = ComposerViewModel(
            target: target,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: accountKeychainId),
            initialBody: initialBody,
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

        Task { @MainActor [weak self] in
            await self?.viewModel.loadExistingDraft()
            self?.editorView.text = self?.viewModel.bodyText ?? ""
        }

        NotificationCenter.default.addObserver(
            forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.viewModel.flushDraft() }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if editorView.mode == .write {
            editorView.textView.becomeFirstResponder()
        }
    }

    private func setup() {
        view.backgroundColor = Theme.background

        navigationItem.title = viewModel.navigationTitle
        navigationItem.leftBarButtonItem = cancelButton
        navigationItem.rightBarButtonItem = postButton
        navigationItem.titleView = modeControl

        editorView.text = viewModel.bodyText

        view.addSubview(editorView)
        NSLayoutConstraint.activate([
            editorView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            editorView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
    }

    @objc
    private func modeChanged() {
        editorView.setMode(modeControl.selectedSegmentIndex == 0 ? .write : .preview)
    }

    /// Opens a link tapped in the rendered preview. The comment composer has
    /// no AppService, so route through the system handler.
    private func openPreviewLink(_ url: URL) {
        UIApplication.shared.open(url)
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
            editorView.textView.isEditable = true
            navigationItem.rightBarButtonItem = postButton

        case .submitting:
            editorView.textView.isEditable = false
            activityIndicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: activityIndicator)

        case .finished:
            view.endEditing(true)
            dismiss(animated: true)

        case let .failed(message):
            editorView.textView.isEditable = true
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
        let trimmed = viewModel.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { dismiss(animated: true)
            return
        }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Save Draft", comment: "Composer keep-draft action"),
            style: .default
        ) { [weak self] _ in
            Task { await self?.viewModel.flushDraft()
                await MainActor.run { self?.dismiss(animated: true) }
            }
        })
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Delete Draft", comment: "Composer discard-draft action"),
            style: .destructive
        ) { [weak self] _ in
            Task { await self?.viewModel.discardDraft()
                await MainActor.run { self?.dismiss(animated: true) }
            }
        })
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "Cancel dismiss"),
            style: .cancel
        ))
        sheet.popoverPresentationController?.barButtonItem = cancelButton
        present(sheet, animated: true)
    }

    @objc
    private func postTapped() {
        view.endEditing(false)
        Task { await viewModel.post() }
    }
}

// MARK: - Presentation

extension ComposerViewController {
    /// Wraps the composer in a navigation controller configured as a
    /// medium/large detent sheet, ready to `present(...)`.
    static func makeSheet(
        target: ComposerTarget,
        accountKeychainId: String,
        initialBody: String? = nil,
        dependencies: Dependencies
    ) -> UIViewController {
        let composer = ComposerViewController(
            target: target,
            accountKeychainId: accountKeychainId,
            initialBody: initialBody,
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
