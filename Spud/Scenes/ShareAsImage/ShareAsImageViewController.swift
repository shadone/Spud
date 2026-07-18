//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

/// The "Share as Image" editor sheet (settled Editor C design): a live,
/// scaled-to-fit preview of the share card centered on a dark dotted stage, with
/// direct-manipulation tap targets ON the preview (tap an element to toggle it),
/// a control tray (appearance / canvas / chain depth / alt text), and an output
/// bar (Share / Save to Photos / Copy).
///
/// State lives in ``ShareAsImageViewModel``; this controller renders it. The
/// preview uses ``ShareCardView/applyForEditor(options:)`` so toggled-off
/// sections stay visible-but-dimmed (tappable to restore) — but every EXPORT
/// path builds a FRESH card configured from the same content/options and renders
/// THAT (rendering mutates the view's bounds, so the on-screen preview must never
/// be handed to ``ShareCardImageRenderer``). See
/// `ShareAsImageViewController+Output.swift` for the output actions.
final class ShareAsImageViewController: UIViewController {
    let viewModel: ShareAsImageViewModel
    let content: ShareCardContent
    let imageService: ImageServiceType

    /// The media image the preview already resolved, cached so the export card
    /// can be handed the exact same bitmap without re-fetching.
    var loadedMediaImage: UIImage?

    private let scrollView = UIScrollView()
    private let canvasView = ShareAsImageCanvasView()
    private let previewContainer = UIView()
    // Internal (not private): the tap-region construction lives in
    // `ShareAsImageViewController+TapRegions.swift`, a separate file that maps
    // these onto the overlay's tap targets.
    let tapOverlay = ShareAsImageTapOverlayView()
    private let nsfwRevealPill = UIButton(type: .system)
    private let trayView = ShareAsImageTrayView()

    // Output-bar buttons are internal (not `private`) rather than file-private
    // because `ShareAsImageViewController+Output.swift` — a separate file — both
    // wires their taps and, for the re-entrancy guard, disables/spinners all
    // three from a single helper (`setOutputBarBusy`).
    let shareButton = UIButton(type: .system)
    let saveButton = UIButton(type: .system)
    let copyButton = UIButton(type: .system)

    /// The nav-bar Done button. Internal (not private) so the output actions in
    /// `ShareAsImageViewController+Output.swift` can disable it while an export
    /// is in flight — dismissing the editor mid-export can orphan the share sheet.
    let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: nil, action: nil)

    // Internal (not private): read by the tap-region construction in
    // `ShareAsImageViewController+TapRegions.swift`.
    var postCard: ShareCardView?
    var chainCard: ShareChainCardView?
    private var previewCardView: UIView {
        postCard ?? chainCard!
    }

    /// The card timestamp's determinism seam, matching ``ShareCardView``:
    /// production passes `.current`; snapshot tests pin `en_US_POSIX`/`GMT` so a
    /// recorded editor reference never depends on the running machine's locale.
    /// Internal (not private) so the export path in
    /// `ShareAsImageViewController+Output.swift` renders its fresh cards through
    /// the same seam as the preview.
    let locale: Locale
    let timeZone: TimeZone

    private let horizontalMargin: CGFloat = 20
    private let verticalMargin: CGFloat = 24
    private var isLayingOutPreview = false

    init(
        content: ShareCardContent,
        imageService: ImageServiceType,
        preferencesService: PreferencesServiceType,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        self.content = content
        self.imageService = imageService
        self.locale = locale
        self.timeZone = timeZone
        viewModel = ShareAsImageViewModel(content: content, preferencesService: preferencesService)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Wraps the editor in a navigation controller as a large-detent page sheet.
    static func makeSheet(
        content: ShareCardContent,
        imageService: ImageServiceType,
        preferencesService: PreferencesServiceType
    ) -> UIViewController {
        let editor = ShareAsImageViewController(
            content: content,
            imageService: imageService,
            preferencesService: preferencesService
        )
        let navigationController = UINavigationController(rootViewController: editor)
        // Set .pageSheet before reading sheetPresentationController: on iPad the
        // default is .formSheet, which leaves that property nil and silently
        // drops the detents configuration.
        navigationController.modalPresentationStyle = .pageSheet
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        return navigationController
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Share as Image"
        doneButton.target = self
        doneButton.action = #selector(doneTapped)
        navigationItem.rightBarButtonItem = doneButton

        makePreviewCard()
        setUpHierarchy()
        wireTray()
        wireNsfwPill()
        // The preview card loads its own media once `applyForEditor` runs (it
        // forces the media visible so the image loads regardless of the current
        // showMedia toggle), which also warms `loadedMediaImage` for export.
        refreshPreview(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPreview()
    }

    // MARK: - Preview card

    private func makePreviewCard() {
        switch content.kind {
        case .post:
            let card = ShareCardView(content: content, options: viewModel.options, locale: locale, timeZone: timeZone)
            card.imageLoader = { [weak self] url in
                let image = await self?.loadImage(url)
                self?.loadedMediaImage = image
                return image
            }
            card.onLayoutChange = { [weak self] in self?.layoutPreview() }
            postCard = card
        case .comment:
            chainCard = ShareChainCardView(
                content: content,
                options: viewModel.options,
                locale: locale,
                timeZone: timeZone
            )
        }
    }

    /// Resolves the image at `url` via the image service (used by both the
    /// preview card's loader and the export path in
    /// `ShareAsImageViewController+Output.swift`).
    func loadImage(_ url: URL) async -> UIImage? {
        for await state in imageService.fetch(url) {
            if case let .ready(image) = state { return image }
        }
        return nil
    }

    // MARK: - Hierarchy

    private func setUpHierarchy() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        canvasView.translatesAutoresizingMaskIntoConstraints = false

        previewContainer.addSubview(previewCardView)
        previewContainer.addSubview(tapOverlay)

        scrollView.addSubview(previewContainer)
        scrollView.addSubview(nsfwRevealPill)

        let bottomBar = makeBottomBar()

        view.addSubview(canvasView)
        view.addSubview(scrollView)
        view.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeBottomBar() -> UIView {
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let outputBar = makeOutputBar()

        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [trayView, outputBar])
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        trayView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(separator)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor),
        ])
        return container
    }

    private func makeOutputBar() -> UIView {
        var shareConfig = UIButton.Configuration.borderedProminent()
        shareConfig.image = UIImage(systemName: "square.and.arrow.up")
        shareConfig.imagePadding = 8
        shareConfig.title = "Share"
        shareConfig.cornerStyle = .large
        shareButton.configuration = shareConfig
        shareButton.titleLabel?.adjustsFontForContentSizeCategory = true
        shareButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        shareButton.addAction(UIAction { [weak self] _ in self?.shareTapped() }, for: .touchUpInside)

        configureIconButton(saveButton, systemImage: "square.and.arrow.down", accessibility: "Save to Photos")
        saveButton.addAction(UIAction { [weak self] _ in self?.saveTapped() }, for: .touchUpInside)

        configureIconButton(copyButton, systemImage: "doc.on.doc", accessibility: "Copy image")
        copyButton.addAction(UIAction { [weak self] _ in self?.copyTapped() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [shareButton, saveButton, copyButton])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16)
        return stack
    }

    private func configureIconButton(_ button: UIButton, systemImage: String, accessibility: String) {
        var config = UIButton.Configuration.bordered()
        config.image = UIImage(systemName: systemImage)
        config.cornerStyle = .large
        button.configuration = config
        button.accessibilityLabel = accessibility
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func wireTray() {
        trayView.onSelectAppearance = { [weak self] appearance in
            self?.viewModel.setAppearance(appearance)
            self?.refreshPreview(animated: true)
            Haptics.tap()
        }
        trayView.onSelectCanvas = { [weak self] canvas in
            self?.viewModel.setCanvas(canvas)
            self?.refreshPreview(animated: false)
            Haptics.tap()
        }
        trayView.onIncrementDepth = { [weak self] in
            self?.viewModel.incrementChainDepth()
            self?.refreshPreview(animated: true)
            Haptics.tap()
        }
        trayView.onDecrementDepth = { [weak self] in
            self?.viewModel.decrementChainDepth()
            self?.refreshPreview(animated: true)
            Haptics.tap()
        }
        trayView.onTapAltText = { [weak self] in self?.presentAltTextEditor() }
    }

    private func wireNsfwPill() {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = UIColor(white: 0, alpha: 0.7)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.image = UIImage(systemName: "eye")
        config.imagePadding = 6
        nsfwRevealPill.configuration = config
        nsfwRevealPill.titleLabel?.adjustsFontForContentSizeCategory = true
        nsfwRevealPill.addAction(UIAction { [weak self] _ in
            self?.viewModel.toggleNsfwRevealed()
            self?.refreshPreview(animated: true)
            Haptics.tap()
        }, for: .touchUpInside)
    }

    // MARK: - Refresh + layout

    /// Re-applies the current options to the preview (with editor ghosting), then
    /// re-derives the tap regions, NSFW pill, alt-text label, and tray state.
    /// `animated` cross-dissolves the card so a toggle reads as a state change.
    ///
    /// Internal (not private): the direct-manipulation `toggle(_:)` helper in
    /// `ShareAsImageViewController+TapRegions.swift` calls back into it.
    func refreshPreview(animated: Bool) {
        let apply = { [self] in
            postCard?.applyForEditor(options: viewModel.options)
            chainCard?.applyForEditor(options: viewModel.options)
        }
        if animated {
            UIView.transition(
                with: previewContainer,
                duration: 0.18,
                options: [.transitionCrossDissolve, .allowUserInteraction],
                animations: apply
            )
        } else {
            apply()
        }
        trayView.configure(
            options: viewModel.options,
            showsDepthStepper: viewModel.showsDepthStepper,
            maxChainDepth: viewModel.maxChainDepth
        )
        layoutPreview()
        previewCardView.isAccessibilityElement = true
        previewCardView.accessibilityLabel = viewModel.currentAltText
    }

    private func layoutPreview() {
        guard !isLayingOutPreview, scrollView.bounds.width > 0 else { return }
        isLayingOutPreview = true
        defer { isLayingOutPreview = false }

        previewContainer.transform = .identity
        let width = ShareCardView.designWidth
        let height = previewCardView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let nativeSize = CGSize(width: width, height: max(height, 1))

        previewContainer.bounds = CGRect(origin: .zero, size: nativeSize)
        previewCardView.frame = previewContainer.bounds
        tapOverlay.frame = previewContainer.bounds
        previewContainer.layoutIfNeeded()

        let availableWidth = scrollView.bounds.width - 2 * horizontalMargin
        let scale = min(1, availableWidth / width)
        previewContainer.transform = CGAffineTransform(scaleX: scale, y: scale)

        let scaledHeight = nativeSize.height * scale
        let contentHeight = max(scrollView.bounds.height, scaledHeight + 2 * verticalMargin)
        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: contentHeight)
        previewContainer.center = CGPoint(x: scrollView.bounds.width / 2, y: contentHeight / 2)

        updateTapRegions()
        updateNsfwPill()
    }

    // MARK: - NSFW pill

    private func updateNsfwPill() {
        guard let post = content.post, post.isNsfw, viewModel.options.showMedia, let mediaView = postCard?.mediaView else {
            nsfwRevealPill.isHidden = true
            return
        }
        nsfwRevealPill.isHidden = false
        let revealed = viewModel.options.nsfwRevealed
        nsfwRevealPill.configuration?.title = revealed ? "Hide for this card" : "Reveal for this card"
        nsfwRevealPill.configuration?.image = UIImage(systemName: revealed ? "eye.slash" : "eye")
        nsfwRevealPill.sizeToFit()
        // Position over the media's (scaled) on-screen center; the pill lives in
        // the scrollView (unscaled) so its text stays legible.
        let center = scrollView.convert(CGPoint(x: mediaView.bounds.midX, y: mediaView.bounds.midY), from: mediaView)
        nsfwRevealPill.center = center
    }

    // MARK: - Alt text

    private func presentAltTextEditor() {
        let editor = ShareAsImageAltTextViewController(
            currentText: viewModel.currentAltText,
            isAuto: viewModel.isAltTextAuto,
            autoText: ShareCardAltText.make(content: content, options: viewModel.options)
        )
        editor.onSave = { [weak self] text in
            self?.viewModel.setAltTextOverride(text)
            self?.refreshPreview(animated: false)
        }
        let navigationController = UINavigationController(rootViewController: editor)
        navigationController.modalPresentationStyle = .pageSheet
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    // MARK: - Done

    @objc
    private func doneTapped() {
        viewModel.persist()
        dismiss(animated: true)
    }

    #if DEBUG
    /// Test seam: injects the preview's media image synchronously (bypassing the
    /// async image loader) so a snapshot renders the media state deterministically
    /// with no network/timing dependency. Mirrors ``ShareCardView/setMediaImage(_:)``.
    func injectPreviewMediaForTesting(_ image: UIImage) {
        loadedMediaImage = image
        postCard?.setMediaImage(image)
        layoutPreview()
    }
    #endif
}
