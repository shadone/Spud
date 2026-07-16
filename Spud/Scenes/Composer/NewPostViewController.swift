//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import PhotosUI
import SpudDataKit
import SpudUIKit
import UIKit

private let logger = Logger.app

/// The Apollo-style new-post composer: a sheet with a community picker, title
/// field, text/link/image affordances, a markdown body editor, a URL field, an
/// image-attach button (PHPicker -> pict-rs upload), and an NSFW toggle.
///
/// PHPickerViewController runs out-of-process, so it needs no photo-library
/// permission and no `NSPhotoLibraryUsageDescription` key — we never touch
/// `PHPhotoLibrary` here.
final class NewPostViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasImageService &
        HasPreferencesService
    typealias Dependencies = OwnDependencies
    private let dependencies: OwnDependencies

    private let viewModel: NewPostViewModel

    private var observationTasks: [Task<Void, Never>] = []

    /// Invoked on successful submit with the new post's id, so the presenter
    /// can navigate to PostDetail. Used by the non-optimistic path.
    var onPosted: ((Lemmy.PostID) -> Void)?

    /// Invoked once the post has been durably enqueued, carrying the client token
    /// so the presenter can push the optimistic pending-post screen.
    var onQueued: ((String) -> Void)?

    /// Invoked once an EDIT has been durably enqueued (its optimistic write
    /// already applied), so the presenter can simply dismiss back to the post —
    /// the open post header already reflects the edit via its GRDB observation.
    var onEditQueued: (() -> Void)?

    // MARK: UI

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        return scrollView
    }()

    private lazy var stackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.isLayoutMarginsRelativeArrangement = true
        return stack
    }()

    private lazy var communityButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.image = UIImage(systemName: "person.3")
        config.imagePadding = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: #selector(communityTapped), for: .touchUpInside)
        return button
    }()

    private lazy var titleField: UITextField = {
        let field = UITextField()
        field.placeholder = NSLocalizedString("Title", comment: "Placeholder for the new-post title field")
        field.font = .preferredFont(forTextStyle: .headline)
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .roundedRect
        field.returnKeyType = .next
        field.addTarget(self, action: #selector(titleChanged), for: .editingChanged)
        return field
    }()

    private lazy var postTypeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            NSLocalizedString("Text", comment: "New-post text type"),
            NSLocalizedString("Link", comment: "New-post link type"),
            NSLocalizedString("Image", comment: "New-post image type"),
        ])
        control.selectedSegmentIndex = NewPostType.text.rawValue
        control.addTarget(self, action: #selector(postTypeChanged), for: .valueChanged)
        return control
    }()

    private lazy var urlField: UITextField = {
        let field = UITextField()
        field.placeholder = NSLocalizedString("URL", comment: "Placeholder for the new-post link URL field")
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .roundedRect
        field.keyboardType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.addTarget(self, action: #selector(urlChanged), for: .editingChanged)
        return field
    }()

    private lazy var attachImageButton: UIButton = {
        var config = UIButton.Configuration.bordered()
        config.title = NSLocalizedString("Attach image", comment: "Button to attach an image to a new post")
        config.image = UIImage(systemName: "photo.on.rectangle")
        config.imagePadding = 8
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: #selector(attachImageTapped), for: .touchUpInside)
        return button
    }()

    private lazy var uploadProgressView: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var bodyEditorView: MarkdownEditorView = {
        let editor = MarkdownEditorView()
        editor.imageService = dependencies.imageService
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.placeholder = NSLocalizedString("Body (optional, markdown)", comment: "Placeholder for the new-post body editor")
        editor.textView.isScrollEnabled = false
        editor.layer.borderColor = UIColor.separator.cgColor
        editor.layer.borderWidth = 1
        editor.layer.cornerRadius = 8
        editor.clipsToBounds = true
        editor.textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        editor.onTextChange = { [weak self] text in
            self?.viewModel.bodyText = text
            self?.viewModel.draftDidChange()
        }
        editor.onPreviewLinkTapped = { url in
            UIApplication.shared.open(url)
        }
        return editor
    }()

    private lazy var bodyModeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            NSLocalizedString("Write", comment: "New-post body write-mode segment"),
            NSLocalizedString("Preview", comment: "New-post body preview-mode segment"),
        ])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(bodyModeChanged), for: .valueChanged)
        return control
    }()

    private lazy var nsfwSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.addTarget(self, action: #selector(nsfwChanged), for: .valueChanged)
        return toggle
    }()

    private lazy var cancelButton = UIBarButtonItem(
        barButtonSystemItem: .cancel,
        target: self,
        action: #selector(cancelTapped)
    )

    private lazy var postButton = UIBarButtonItem(
        title: NSLocalizedString("Post", comment: "New-post submit button"),
        style: .done,
        target: self,
        action: #selector(postTapped)
    )

    private lazy var activityIndicator = UIActivityIndicatorView(style: .medium)

    // MARK: Functions

    init(
        serverCommunityId: Lemmy.CommunityID?,
        initialCommunityName: String?,
        accountKeychainId: String,
        dependencies: Dependencies,
        editPostServerId: Int64? = nil,
        initialTitle: String? = nil,
        initialBody: String? = nil,
        initialUrl: String? = nil,
        initialNsfw: Bool = false
    ) {
        self.dependencies = dependencies
        viewModel = NewPostViewModel(
            serverCommunityId: serverCommunityId,
            initialCommunityName: initialCommunityName,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: accountKeychainId),
            dependencies: dependencies,
            editPostServerId: editPostServerId,
            initialTitle: initialTitle,
            initialBody: initialBody,
            initialUrl: initialUrl,
            initialNsfw: initialNsfw
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

        // Mail-style draft restore: reload a previously-saved draft (if any) for
        // this community and reflect it back into the editable fields.
        Task { @MainActor [weak self] in
            await self?.viewModel.loadExistingDraft()
            self?.reflectDraftFields()
        }

        // Persist whatever the user has typed if the app is backgrounded
        // mid-compose, so nothing is lost on a cold restart.
        NotificationCenter.default.addObserver(
            forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.viewModel.flushDraft() }
        }
    }

    /// Pushes the view model's draft fields into the editable UI after a draft
    /// load (the view model is the source of truth for restored text).
    private func reflectDraftFields() {
        titleField.text = viewModel.titleText
        urlField.text = viewModel.urlText
        bodyEditorView.text = viewModel.bodyText
        nsfwSwitch.isOn = viewModel.nsfw
        postTypeControl.selectedSegmentIndex = viewModel.postType.rawValue
        applyPostType()
        updateCommunityButton()
    }

    private func setup() {
        view.backgroundColor = Theme.background

        navigationItem.title = viewModel.navigationTitle
        postButton.title = viewModel.submitButtonTitle
        navigationItem.leftBarButtonItem = cancelButton
        navigationItem.rightBarButtonItem = postButton

        // In edit mode the community is fixed: show it, but don't let the user
        // re-target the post to a different community.
        communityButton.isEnabled = viewModel.canChangeCommunity

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        let attachRow = UIStackView(arrangedSubviews: [attachImageButton, uploadProgressView, UIView()])
        attachRow.axis = .horizontal
        attachRow.spacing = 8
        attachRow.alignment = .center

        let nsfwLabel = UILabel()
        nsfwLabel.text = NSLocalizedString("NSFW", comment: "Label for the new-post NSFW toggle")
        nsfwLabel.font = .preferredFont(forTextStyle: .body)
        nsfwLabel.adjustsFontForContentSizeCategory = true
        let nsfwRow = UIStackView(arrangedSubviews: [nsfwLabel, UIView(), nsfwSwitch])
        nsfwRow.axis = .horizontal
        nsfwRow.alignment = .center

        let bodyHeaderRow = UIStackView(arrangedSubviews: [UIView(), bodyModeControl])
        bodyHeaderRow.axis = .horizontal
        bodyHeaderRow.alignment = .center

        stackView.addArrangedSubview(communityButton)
        stackView.addArrangedSubview(titleField)
        stackView.addArrangedSubview(postTypeControl)
        stackView.addArrangedSubview(urlField)
        stackView.addArrangedSubview(attachRow)
        stackView.addArrangedSubview(bodyHeaderRow)
        stackView.addArrangedSubview(bodyEditorView)
        stackView.addArrangedSubview(nsfwRow)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            bodyEditorView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])

        applyPostType()
        updateCommunityButton()
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

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await _ in ObservationStream.values(of: { viewModel.community }) {
                self?.updateCommunityButton()
            }
        })

        observationTasks.append(Task { @MainActor [weak self, viewModel] in
            for await uploading in ObservationStream.values(of: { viewModel.isUploadingImage }) {
                self?.applyUploading(uploading)
            }
        })
    }

    private func applyUploading(_ uploading: Bool) {
        if uploading {
            uploadProgressView.startAnimating()
            attachImageButton.isEnabled = false
        } else {
            uploadProgressView.stopAnimating()
            attachImageButton.isEnabled = true
        }
    }

    private func updateCommunityButton() {
        communityButton.setTitle(viewModel.communityButtonTitle, for: .normal)
    }

    private func applyPostType() {
        switch viewModel.postType {
        case .text:
            urlField.isHidden = true
        case .link, .image:
            urlField.isHidden = false
        }
    }

    private func apply(submissionState state: NewPostSubmissionState) {
        switch state {
        case .editing:
            setFormEnabled(true)
            navigationItem.rightBarButtonItem = postButton

        case .uploadingImage:
            // Form stays interactive except the attach button (handled by the
            // uploading binding); no nav-bar spinner for image upload.
            break

        case .submitting:
            setFormEnabled(false)
            activityIndicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: activityIndicator)

        case let .finished(serverPostId):
            view.endEditing(true)
            Haptics.success()
            dismiss(animated: true) { [onPosted] in
                onPosted?(serverPostId)
            }

        case let .queued(clientToken):
            view.endEditing(true)
            Haptics.success()
            dismiss(animated: true) { [onQueued] in
                onQueued?(clientToken)
            }

        case .editQueued:
            view.endEditing(true)
            Haptics.success()
            dismiss(animated: true) { [onEditQueued] in
                onEditQueued?()
            }

        case let .failed(message):
            setFormEnabled(true)
            navigationItem.rightBarButtonItem = postButton
            Haptics.warning()
            viewModel.didPresentFailure()
            presentErrorAlert(message: message)
        }
    }

    private func setFormEnabled(_ enabled: Bool) {
        titleField.isEnabled = enabled
        urlField.isEnabled = enabled
        bodyEditorView.textView.isEditable = enabled
        bodyModeControl.isEnabled = enabled
        postTypeControl.isEnabled = enabled
        nsfwSwitch.isEnabled = enabled
        // The community stays locked in edit mode regardless of form-enabled state.
        communityButton.isEnabled = enabled && viewModel.canChangeCommunity
        attachImageButton.isEnabled = enabled
    }

    // MARK: Actions

    @objc
    private func bodyModeChanged() {
        bodyEditorView.setMode(bodyModeControl.selectedSegmentIndex == 0 ? .write : .preview)
    }

    @objc
    private func titleChanged() {
        viewModel.titleText = titleField.text ?? ""
        viewModel.draftDidChange()
    }

    @objc
    private func urlChanged() {
        viewModel.urlText = urlField.text ?? ""
        viewModel.draftDidChange()
    }

    @objc
    private func nsfwChanged() {
        viewModel.nsfw = nsfwSwitch.isOn
        viewModel.draftDidChange()
    }

    @objc
    private func postTypeChanged() {
        viewModel.postType = NewPostType(rawValue: postTypeControl.selectedSegmentIndex) ?? .text
        applyPostType()
        viewModel.draftDidChange()
    }

    @objc
    private func communityTapped() {
        view.endEditing(true)
        let picker = CommunityPickerViewController(
            accountKeychainId: viewModel.accountKeychainId,
            dependencies: dependencies
        )
        picker.onSelect = { [weak self] community in
            self?.viewModel.community = community
            self?.viewModel.draftDidChange()
        }
        let nav = UINavigationController(rootViewController: picker)
        present(nav, animated: true)
    }

    /// Capability check first — Spud now speaks the native Lemmy v4 API for
    /// every Lemmy version, so this gate's only live trigger today is PieFed
    /// (no image-upload endpoint yet; see docs/features/piefed.md): explain,
    /// don't hide — the button stays visible and enabled either way, the
    /// sheet just explains why picking an image won't work yet. Read live at
    /// action time (no caching in the VC).
    @objc
    private func attachImageTapped() {
        let capabilities = viewModel.capabilities
        guard capabilities.can(.imageUpload) else {
            presentCapabilityGate(for: .imageUpload, host: viewModel.instanceHost, software: capabilities.software, sourceView: attachImageButton)
            return
        }
        view.endEditing(true)
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc
    private func cancelTapped() {
        view.endEditing(true)

        // No content typed: just dismiss, nothing to keep.
        let hasContent = !(titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyEditorView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(urlField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasContent else {
            dismiss(animated: true)
            return
        }

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Save Draft", comment: "New-post keep-draft action"),
            style: .default
        ) { [weak self] _ in
            Task { await self?.viewModel.flushDraft()
                await MainActor.run { self?.dismiss(animated: true) }
            }
        })
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("Delete Draft", comment: "New-post discard-draft action"),
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
        Task { await viewModel.submit() }
    }
}

// MARK: - PHPickerViewControllerDelegate

extension NewPostViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let provider = results.first?.itemProvider else { return }

        // Load the image as raw JPEG-able data off the picker's NSItemProvider.
        provider.loadDataRepresentation(forTypeIdentifier: "public.image") { [weak self] data, error in
            guard let self else { return }
            if let error {
                logger.error("Failed to load picked image: \(String(describing: error), privacy: .public)")
                return
            }
            guard let data, let image = UIImage(data: data) else { return }

            // Normalise to JPEG so the upload mime type and filename are honest.
            let jpegData = image.jpegData(compressionQuality: 0.85) ?? data
            let fileName = "upload-\(UUID().uuidString).jpg"

            Task { @MainActor [weak self] in
                guard let self else { return }
                await viewModel.uploadImage(imageData: jpegData, fileName: fileName)
                syncFieldsFromViewModel()
            }
        }
    }

    /// After an image upload mutates the view model (url or body), reflect it
    /// back into the editable fields.
    private func syncFieldsFromViewModel() {
        urlField.text = viewModel.urlText
        bodyEditorView.text = viewModel.bodyText
    }
}

// MARK: - Presentation

extension NewPostViewController {
    /// Wraps the new-post composer in a navigation controller configured as a
    /// large detent sheet, ready to `present(...)`.
    static func makeSheet(
        serverCommunityId: Lemmy.CommunityID?,
        initialCommunityName: String?,
        accountKeychainId: String,
        dependencies: Dependencies,
        onQueued: @escaping (String) -> Void
    ) -> UIViewController {
        let composer = NewPostViewController(
            serverCommunityId: serverCommunityId,
            initialCommunityName: initialCommunityName,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )
        composer.onQueued = onQueued
        let navigationController = UINavigationController(rootViewController: composer)
        // Set .pageSheet before reading sheetPresentationController: on iPad the
        // default is .formSheet, which leaves that property nil and silently drops
        // the detents configuration.
        navigationController.modalPresentationStyle = .pageSheet
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        return navigationController
    }

    /// Wraps the new-post composer, pre-filled with a source post's title/url/
    /// body, in a navigation controller configured as a large detent sheet,
    /// ready to `present(...)`. Mirrors `makeSheet` (a brand-new post, no
    /// `editPostServerId`, community picker left open so the user picks the
    /// cross-post's target community) but forwards the seeded content — see
    /// `NewPostViewModel.hasSeededInitialContent` for how that content is
    /// protected from being clobbered by a stale draft.
    static func makeCrossPostSheet(
        initialTitle: String,
        initialUrl: String?,
        initialBody: String?,
        accountKeychainId: String,
        dependencies: Dependencies,
        onQueued: @escaping (String) -> Void
    ) -> UIViewController {
        let composer = NewPostViewController(
            serverCommunityId: nil,
            initialCommunityName: nil,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies,
            initialTitle: initialTitle,
            initialBody: initialBody,
            initialUrl: initialUrl
        )
        composer.onQueued = onQueued
        let navigationController = UINavigationController(rootViewController: composer)
        // Set .pageSheet before reading sheetPresentationController: on iPad the
        // default is .formSheet, which leaves that property nil and silently drops
        // the detents configuration.
        navigationController.modalPresentationStyle = .pageSheet
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        return navigationController
    }

    /// Wraps the composer in edit mode (seeded with an existing post) in a
    /// navigation controller configured as a large detent sheet, ready to
    /// `present(...)`. The composer self-dismisses once the edit is durably
    /// enqueued; the open post header reflects the optimistic edit via its GRDB
    /// observation, so no presenter callback is needed. `onEditQueued` is an
    /// optional post-dismiss hook for any future presenter that needs one.
    static func makeEditSheet(
        serverPostId: Int64,
        serverCommunityId: Lemmy.CommunityID,
        communityName: String,
        title: String,
        body: String?,
        url: String?,
        nsfw: Bool,
        accountKeychainId: String,
        dependencies: Dependencies,
        onEditQueued: (() -> Void)? = nil
    ) -> UIViewController {
        let composer = NewPostViewController(
            serverCommunityId: serverCommunityId,
            initialCommunityName: communityName,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies,
            editPostServerId: serverPostId,
            initialTitle: title,
            initialBody: body,
            initialUrl: url,
            initialNsfw: nsfw
        )
        composer.onEditQueued = onEditQueued
        let navigationController = UINavigationController(rootViewController: composer)
        // Set .pageSheet before reading sheetPresentationController: on iPad the
        // default is .formSheet, which leaves that property nil and silently drops
        // the detents configuration.
        navigationController.modalPresentationStyle = .pageSheet
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        return navigationController
    }
}
