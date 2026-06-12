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
        HasAlertService
    typealias Dependencies = OwnDependencies
    private let dependencies: OwnDependencies

    private let viewModel: NewPostViewModel

    private var observationTasks: [Task<Void, Never>] = []

    /// Invoked on successful submit with the new post's id, so the presenter
    /// can navigate to PostDetail.
    var onPosted: ((Components.Schemas.PostID) -> Void)?

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

    private lazy var bodyTextView: UITextView = {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = false
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.delegate = self
        return textView
    }()

    private lazy var bodyPlaceholderLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString("Body (optional, markdown)", comment: "Placeholder for the new-post body editor")
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        serverCommunityId: Components.Schemas.CommunityID?,
        initialCommunityName: String?,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = dependencies
        viewModel = NewPostViewModel(
            serverCommunityId: serverCommunityId,
            initialCommunityName: initialCommunityName,
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

    private func setup() {
        view.backgroundColor = .systemBackground

        navigationItem.title = NSLocalizedString("New post", comment: "Title of the new-post composer")
        navigationItem.leftBarButtonItem = cancelButton
        navigationItem.rightBarButtonItem = postButton

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

        stackView.addArrangedSubview(communityButton)
        stackView.addArrangedSubview(titleField)
        stackView.addArrangedSubview(postTypeControl)
        stackView.addArrangedSubview(urlField)
        stackView.addArrangedSubview(attachRow)
        stackView.addArrangedSubview(bodyTextView)
        stackView.addArrangedSubview(nsfwRow)

        bodyTextView.addSubview(bodyPlaceholderLabel)

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

            bodyTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
            bodyPlaceholderLabel.topAnchor.constraint(equalTo: bodyTextView.topAnchor, constant: 12),
            bodyPlaceholderLabel.leadingAnchor.constraint(equalTo: bodyTextView.leadingAnchor, constant: 12),
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
        bodyTextView.isEditable = enabled
        postTypeControl.isEnabled = enabled
        nsfwSwitch.isEnabled = enabled
        communityButton.isEnabled = enabled
        attachImageButton.isEnabled = enabled
    }

    // MARK: Actions

    @objc
    private func titleChanged() {
        viewModel.titleText = titleField.text ?? ""
    }

    @objc
    private func urlChanged() {
        viewModel.urlText = urlField.text ?? ""
    }

    @objc
    private func nsfwChanged() {
        viewModel.nsfw = nsfwSwitch.isOn
    }

    @objc
    private func postTypeChanged() {
        viewModel.postType = NewPostType(rawValue: postTypeControl.selectedSegmentIndex) ?? .text
        applyPostType()
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
        }
        let nav = UINavigationController(rootViewController: picker)
        present(nav, animated: true)
    }

    @objc
    private func attachImageTapped() {
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
        dismiss(animated: true)
    }

    @objc
    private func postTapped() {
        view.endEditing(false)
        Task { await viewModel.submit() }
    }
}

// MARK: - UITextViewDelegate

extension NewPostViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        viewModel.bodyText = textView.text
        bodyPlaceholderLabel.isHidden = !textView.text.isEmpty
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
        bodyTextView.text = viewModel.bodyText
        bodyPlaceholderLabel.isHidden = !viewModel.bodyText.isEmpty
    }
}

// MARK: - Presentation

extension NewPostViewController {
    /// Wraps the new-post composer in a navigation controller configured as a
    /// large detent sheet, ready to `present(...)`.
    static func makeSheet(
        serverCommunityId: Components.Schemas.CommunityID?,
        initialCommunityName: String?,
        accountKeychainId: String,
        dependencies: Dependencies,
        onPosted: @escaping (Components.Schemas.PostID) -> Void
    ) -> UIViewController {
        let composer = NewPostViewController(
            serverCommunityId: serverCommunityId,
            initialCommunityName: initialCommunityName,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )
        composer.onPosted = onPosted
        let navigationController = UINavigationController(rootViewController: composer)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        return navigationController
    }
}
