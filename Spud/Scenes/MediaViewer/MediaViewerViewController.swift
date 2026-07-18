//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import Photos
import SpudDataKit
import SpudUIKit
import UIKit

private let logger = Logger.app

/// Full-screen image / media viewer.
///
/// Hosts one or more `MediaItem`s in a horizontally-paged `UIPageViewController`
/// (single item = no paging). Each page is a zoomable, pannable image. The
/// viewer itself owns:
///   - an interactive swipe-down-to-dismiss gesture, with the black backdrop
///     fading proportionally to drag distance,
///   - an auto-hiding top bar (close / share / save) toggled by single tap,
///   - share (`UIActivityViewController`) and save-to-Photos actions.
///
/// Presented full-screen with a cross-dissolve via `MediaViewerTransition`.
final class MediaViewerViewController: UIViewController {
    typealias OwnDependencies = HasImageService
    typealias Dependencies = OwnDependencies

    // MARK: Private

    private let items: [MediaItem]
    private let imageService: ImageServiceType
    private var currentIndex: Int

    /// True when any item is NSFW; gates privacy-screen registration.
    private let containsSensitiveContent: Bool
    /// Tracks the balanced begin/end of the sensitive-content registration.
    private var didRegisterSensitive = false

    /// Distance the user must drag down (after the gesture resolves to a
    /// dismiss) before release commits the dismissal.
    private let dismissThreshold: CGFloat = 120

    /// The chrome (top bar, page dots, alt-text pill) starts hidden so the
    /// image fills the screen on open; a single tap reveals it.
    private var isBarHidden = true

    /// The chrome state captured when a swipe-to-dismiss pan begins, so a
    /// cancelled swipe springs back to however the chrome was before the drag
    /// rather than always revealing it.
    private var barHiddenBeforePan = true

    // MARK: UI Properties

    private lazy var backgroundView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .black
        return view
    }()

    private lazy var pageViewController: UIPageViewController = {
        let pageVC = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]
        )
        pageVC.dataSource = items.count > 1 ? self : nil
        pageVC.delegate = self
        return pageVC
    }()

    private lazy var topBarBackgroundView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var closeButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "xmark")
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        button.accessibilityLabel = NSLocalizedString("Close", comment: "Accessibility label for the media viewer close button")
        return button
    }()

    private lazy var shareButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "square.and.arrow.up")
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        button.accessibilityLabel = NSLocalizedString("Share", comment: "Accessibility label for the media viewer share button")
        return button
    }()

    private lazy var saveButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "arrow.down.to.line")
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        button.accessibilityLabel = NSLocalizedString("Save to Photos", comment: "Accessibility label for the media viewer save button")
        return button
    }()

    private lazy var pageControl: UIPageControl = {
        let control = UIPageControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.numberOfPages = items.count
        control.currentPage = currentIndex
        control.hidesForSinglePage = true
        control.isUserInteractionEnabled = false
        control.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.3)
        control.currentPageIndicatorTintColor = .white
        return control
    }()

    /// The collapsed alt-text affordance: a tappable "[ALT] Image description ⌃"
    /// pill pinned above the page dots that opens the full description sheet.
    /// Hidden when the current item carries no alt text; fades with the chrome.
    private lazy var captionContainer: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.isHidden = true
        return view
    }()

    private lazy var captionStack: UIStackView = {
        let title = UILabel()
        title.text = Self.altPillLabel
        title.font = .systemFont(ofSize: 13, weight: .regular)
        title.textColor = UIColor.white.withAlphaComponent(0.88)

        let chevron = UIImageView(image: UIImage(
            systemName: "chevron.up",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        ))
        chevron.tintColor = UIColor.white.withAlphaComponent(0.7)
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [AltBadgeLabel(pointSize: 10.5), title, chevron])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Touches are handled by the container's tap gesture.
        stack.isUserInteractionEnabled = false
        return stack
    }()

    /// A non-blocking "Showing low-resolution preview" pill shown in the chrome
    /// when the current page's full-resolution image couldn't load but its
    /// preloaded thumbnail is on screen (slow network / offline). Created lazily
    /// the first time a page degrades; fades with the rest of the chrome.
    private lazy var lowResPreviewPill: LowResPreviewPillView = {
        let pill = LowResPreviewPillView(
            title: NSLocalizedString(
                "Showing low-resolution preview",
                comment: "Media-viewer pill shown when only a low-res preview of an image is available"
            ),
            showsRetryHint: false
        )
        pill.configureAccessibility(
            isInteractive: false,
            hint: NSLocalizedString(
                "The full-resolution image is unavailable.",
                comment: "VoiceOver hint for the media-viewer low-res preview pill"
            )
        )
        pill.isHidden = true
        return pill
    }()

    /// The current page's alt text, shown in the sheet opened from the pill.
    private var currentAltText: String?

    private static let altPillLabel = NSLocalizedString(
        "Image description",
        comment: "Media-viewer alt-text pill label"
    )

    private var singleTapGesture: UITapGestureRecognizer?

    private var topBarTopConstraint: NSLayoutConstraint!

    // MARK: Functions

    init(items: [MediaItem], startIndex: Int, dependencies: Dependencies) {
        precondition(!items.isEmpty, "MediaViewer requires at least one item")
        self.items = items
        currentIndex = min(max(0, startIndex), items.count - 1)
        containsSensitiveContent = items.contains { $0.isNsfw }
        imageService = dependencies.imageService
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .custom
        modalPresentationCapturesStatusBarAppearance = true
        transitioningDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Convenience factory mirroring the codebase's `make…` presentation
    /// pattern. Builds the viewer ready to `present(_:animated:)`.
    static func make(
        items: [MediaItem],
        startIndex: Int = 0,
        dependencies: Dependencies
    ) -> MediaViewerViewController {
        MediaViewerViewController(items: items, startIndex: startIndex, dependencies: dependencies)
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        view.addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        addChild(pageViewController)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageViewController.view)
        NSLayoutConstraint.activate([
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        pageViewController.didMove(toParent: self)

        let firstPage = makePage(at: currentIndex)
        pageViewController.setViewControllers([firstPage], direction: .forward, animated: false)

        setupTopBar()
        setupGestures()
        applyPageControlVisibility()
        updateCaption()

        // Start with the chrome hidden; a single tap reveals it.
        setBar(hidden: true, animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // While NSFW media is on screen, register it as sensitive so the privacy
        // screen hides it from the app-switcher snapshot and screen captures.
        // Registration persists across backgrounding (appear/disappear don't fire
        // then) and is balanced on dismissal in viewWillDisappear.
        if containsSensitiveContent, !didRegisterSensitive {
            didRegisterSensitive = true
            PrivacyScreenMonitor.shared.beginSensitiveContent()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if didRegisterSensitive {
            didRegisterSensitive = false
            PrivacyScreenMonitor.shared.endSensitiveContent()
        }
    }

    private func setupTopBar() {
        view.addSubview(topBarBackgroundView)
        topBarBackgroundView.contentView.addSubview(closeButton)
        topBarBackgroundView.contentView.addSubview(shareButton)
        topBarBackgroundView.contentView.addSubview(saveButton)

        view.addSubview(pageControl)

        view.addSubview(captionContainer)
        captionContainer.contentView.addSubview(captionStack)
        let pillTap = UITapGestureRecognizer(target: self, action: #selector(captionTapped))
        captionContainer.addGestureRecognizer(pillTap)

        view.addSubview(lowResPreviewPill)

        topBarTopConstraint = topBarBackgroundView.topAnchor.constraint(equalTo: view.topAnchor)

        NSLayoutConstraint.activate([
            topBarTopConstraint,
            topBarBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBarBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBarBackgroundView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),

            closeButton.leadingAnchor.constraint(equalTo: topBarBackgroundView.contentView.leadingAnchor, constant: 8),
            closeButton.bottomAnchor.constraint(equalTo: topBarBackgroundView.contentView.bottomAnchor, constant: -2),

            saveButton.trailingAnchor.constraint(equalTo: topBarBackgroundView.contentView.trailingAnchor, constant: -8),
            saveButton.bottomAnchor.constraint(equalTo: topBarBackgroundView.contentView.bottomAnchor, constant: -2),

            shareButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -4),
            shareButton.bottomAnchor.constraint(equalTo: topBarBackgroundView.contentView.bottomAnchor, constant: -2),

            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            // A compact pill centered above the page dots; it stays narrow
            // (the description itself lives in the sheet it opens), but is
            // capped short of the edges so the fixed label never crowds them.
            captionContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captionContainer.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -10),
            captionContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            captionContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            captionStack.topAnchor.constraint(equalTo: captionContainer.contentView.topAnchor, constant: 6),
            captionStack.bottomAnchor.constraint(equalTo: captionContainer.contentView.bottomAnchor, constant: -6),
            captionStack.leadingAnchor.constraint(equalTo: captionContainer.contentView.leadingAnchor, constant: 11),
            captionStack.trailingAnchor.constraint(equalTo: captionContainer.contentView.trailingAnchor, constant: -11),

            // The degraded pill sits just above the alt-text pill (or the page
            // dots when there's no alt text), centred and capped short of the
            // edges so its label never crowds them.
            lowResPreviewPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lowResPreviewPill.bottomAnchor.constraint(equalTo: captionContainer.topAnchor, constant: -10),
            lowResPreviewPill.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            lowResPreviewPill.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
        ])
    }

    /// Reveals the alt-text pill for the current item (or hides it when there's
    /// no description). Called on load and after each page change.
    private func updateCaption() {
        let description = items[currentIndex].altText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let description, !description.isEmpty else {
            currentAltText = nil
            captionContainer.isHidden = true
            captionContainer.isAccessibilityElement = false
            return
        }
        currentAltText = description
        captionContainer.isHidden = false
        captionContainer.isAccessibilityElement = true
        captionContainer.accessibilityTraits = .button
        captionContainer.accessibilityLabel = Self.altPillLabel
        captionContainer.accessibilityHint = NSLocalizedString(
            "Shows the full image description",
            comment: "VoiceOver hint for the media-viewer alt-text pill"
        )
    }

    @objc
    private func captionTapped() {
        guard let currentAltText else { return }
        present(AltTextSheetViewController(altText: currentAltText), animated: true)
    }

    /// Shows or hides the "Showing low-resolution preview" pill for the current
    /// page. Visible when that page's full-resolution image couldn't load while
    /// its preview is on screen. Called when a page degrades and after each page
    /// change so the pill tracks whichever page is on screen.
    private func updateLowResPreviewPill() {
        lowResPreviewPill.isHidden = !(currentPage?.isShowingLowResPreviewOnly ?? false)
    }

    private func setupGestures() {
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        // Don't fight the per-page double-tap-to-zoom recogniser.
        if let doubleTap = currentPage?.zoomableImageView.gestureRecognizers?
            .compactMap({ $0 as? UITapGestureRecognizer })
            .first(where: { $0.numberOfTapsRequired == 2 })
        {
            singleTap.require(toFail: doubleTap)
        }
        singleTap.delegate = self
        singleTapGesture = singleTap
        view.addGestureRecognizer(singleTap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    // MARK: Paging

    private func makePage(at index: Int) -> MediaViewerPageViewController {
        MediaViewerPageViewController(
            item: items[index],
            pageIndex: index,
            imageService: imageService,
            onFullImageUnavailable: { [weak self] page in
                // Only reflect the degraded state if it's the page on screen; a
                // neighbour page UIPageViewController pre-loaded shouldn't flip
                // the pill. A later page change re-evaluates via updateChrome().
                guard let self, page === currentPage else { return }
                updateLowResPreviewPill()
            }
        )
    }

    private var currentPage: MediaViewerPageViewController? {
        pageViewController.viewControllers?.first as? MediaViewerPageViewController
    }

    private func applyPageControlVisibility() {
        pageControl.isHidden = items.count <= 1
    }

    // MARK: Top bar auto-hide

    @objc
    private func handleSingleTap() {
        setBar(hidden: !isBarHidden)
    }

    private func setBar(hidden: Bool, animated: Bool = true) {
        isBarHidden = hidden
        let alpha: CGFloat = hidden ? 0 : 1
        let changes = { [self] in
            topBarBackgroundView.alpha = alpha
            pageControl.alpha = alpha
            captionContainer.alpha = alpha
            lowResPreviewPill.alpha = alpha
        }
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }

    // MARK: Swipe-to-dismiss

    @objc
    private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)
        let velocity = recognizer.velocity(in: view)

        switch recognizer.state {
        case .began:
            barHiddenBeforePan = isBarHidden

        case .changed:
            // Follow the finger; subtle horizontal drift allowed.
            let progress = min(1, max(0, translation.y / (view.bounds.height * 0.5)))
            pageViewController.view.transform = CGAffineTransform(
                translationX: translation.x * 0.5,
                y: translation.y
            )
            backgroundView.alpha = 1 - progress * 0.85
            if !isBarHidden {
                setBar(hidden: true, animated: false)
            }

        case .ended, .cancelled:
            let shouldDismiss = translation.y > dismissThreshold || velocity.y > 800
            if shouldDismiss, recognizer.state == .ended {
                dismissWithFade(velocity: velocity)
            } else {
                springBack()
            }

        default:
            break
        }
    }

    private func dismissWithFade(velocity: CGPoint) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            dismiss(animated: true)
            return
        }
        // Carry the image the rest of the way off-screen, fading the backdrop.
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: .curveEaseOut,
            animations: { [self] in
                let remaining = view.bounds.height - pageViewController.view.transform.ty
                pageViewController.view.transform = CGAffineTransform(
                    translationX: pageViewController.view.transform.tx,
                    y: pageViewController.view.transform.ty + remaining
                )
                backgroundView.alpha = 0
            },
            completion: { [weak self] _ in
                self?.dismiss(animated: false)
            }
        )
    }

    private func springBack() {
        let animated = !UIAccessibility.isReduceMotionEnabled
        let changes = { [self] in
            pageViewController.view.transform = .identity
            backgroundView.alpha = 1
        }
        let finish = { [self] in setBar(hidden: barHiddenBeforePan) }
        guard animated else {
            changes()
            finish()
            return
        }
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: changes,
            completion: { _ in finish() }
        )
    }

    // MARK: Actions

    @objc
    private func closeTapped() {
        dismiss(animated: true)
    }

    @objc
    private func shareTapped() {
        let item = items[currentIndex]

        // For an animated GIF, share the original bytes (written to a temp .gif)
        // so the recipient gets the animation, not a flattened frame.
        if item.isAnimated {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data = await imageService.animatedImageData(item.imageUrl),
                   let fileURL = Self.writeTemporaryGIF(data, for: item.imageUrl)
                {
                    presentActivity(items: [fileURL])
                } else if let image = currentPage?.zoomableImageView.image {
                    presentActivity(items: [image])
                } else {
                    presentActivity(items: [item.imageUrl])
                }
            }
            return
        }

        guard let image = currentPage?.zoomableImageView.image else {
            // Nothing loaded yet — share the URL instead.
            presentActivity(items: [item.imageUrl])
            return
        }
        presentActivity(items: [image])
    }

    private func presentActivity(items: [Any]) {
        // Shares the sheet anchored to the share button (its original behavior);
        // the shared helper fires no haptic, so this path stays haptic-free.
        presentShareSheet(items: items, sourceView: shareButton)
    }

    /// What `saveToPhotos` should write: a still frame, or the original GIF
    /// bytes (so an animated post saves as an animated GIF, not a flat photo).
    private enum SavePayload {
        case still(UIImage)
        case animatedGIF(Data)
    }

    @objc
    private func saveTapped() {
        let item = items[currentIndex]

        if item.isAnimated {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data = await imageService.animatedImageData(item.imageUrl) {
                    saveToPhotos(.animatedGIF(data))
                } else if let image = currentPage?.zoomableImageView.image {
                    saveToPhotos(.still(image))
                } else {
                    Haptics.warning()
                }
            }
            return
        }

        guard let image = currentPage?.zoomableImageView.image else {
            Haptics.warning()
            return
        }
        saveToPhotos(.still(image))
    }

    private func saveToPhotos(_ payload: SavePayload) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            performSave(payload)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if newStatus == .authorized || newStatus == .limited {
                        performSave(payload)
                    } else {
                        handleSaveDenied()
                    }
                }
            }
        case .denied, .restricted:
            handleSaveDenied()
        @unknown default:
            handleSaveDenied()
        }
    }

    private func performSave(_ payload: SavePayload) {
        PHPhotoLibrary.shared().performChanges {
            switch payload {
            case let .still(image):
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            case let .animatedGIF(data):
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        } completionHandler: { success, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if success {
                    Haptics.success()
                } else {
                    if let error {
                        logger.error("Failed to save image to Photos: \(String(describing: error), privacy: .public)")
                    }
                    Haptics.warning()
                    presentSaveError()
                }
            }
        }
    }

    private func handleSaveDenied() {
        Haptics.warning()
        let alert = UIAlertController(
            title: NSLocalizedString("Photos Access Needed", comment: "Title of alert when Photos add permission is denied"),
            message: NSLocalizedString(
                "Allow photo library access in Settings to save images.",
                comment: "Body of alert when Photos add permission is denied"
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Open Settings", comment: "Open Settings action"),
            style: .default,
            handler: { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        ))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "Cancel action"),
            style: .cancel
        ))
        present(alert, animated: true)
    }

    private func presentSaveError() {
        let alert = UIAlertController(
            title: NSLocalizedString("Couldn't Save Image", comment: "Title of alert when saving an image failed"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Dismiss the save-failed alert"),
            style: .default
        ))
        present(alert, animated: true)
    }

    /// Filename for a temporary shared GIF, derived from the source URL and
    /// guaranteed to carry a `.gif` extension so the share sheet treats the
    /// file as an animated image. Pure (no IO) so it can be unit-tested.
    nonisolated static func temporaryGIFFilename(for url: URL) -> String {
        let base = url.lastPathComponent
        if base.isEmpty {
            return "image.gif"
        }
        return base.lowercased().hasSuffix(".gif") ? base : base + ".gif"
    }

    /// Persist GIF bytes to a temporary `.gif` file for sharing. Sharing the
    /// decoded `UIImage` would flatten the animation; sharing a real `.gif`
    /// file preserves it. Returns nil if the write fails.
    nonisolated static func writeTemporaryGIF(_ data: Data, for url: URL) -> URL? {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(temporaryGIFFilename(for: url))
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            logger.error("Failed to write temporary GIF for sharing: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

// MARK: - UIPageViewControllerDataSource

extension MediaViewerViewController: UIPageViewControllerDataSource {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard
            let page = viewController as? MediaViewerPageViewController,
            page.pageIndex > 0
        else { return nil }
        return makePage(at: page.pageIndex - 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard
            let page = viewController as? MediaViewerPageViewController,
            page.pageIndex < items.count - 1
        else { return nil }
        return makePage(at: page.pageIndex + 1)
    }
}

// MARK: - UIPageViewControllerDelegate

extension MediaViewerViewController: UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed, let page = currentPage else { return }
        currentIndex = page.pageIndex
        pageControl.currentPage = currentIndex
        updateCaption()
        updateLowResPreviewPill()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MediaViewerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // A tap on the alt-text pill opens its sheet; don't also toggle the
        // chrome out from under it.
        if gestureRecognizer === singleTapGesture,
           let touchView = touch.view,
           touchView.isDescendant(of: captionContainer)
        {
            return false
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        // Only claim a downward, mostly-vertical drag, and only when the
        // current image isn't zoomed (so panning a zoomed image still works).
        if currentPage?.zoomableImageView.isZoomed == true {
            return false
        }
        let velocity = pan.velocity(in: view)
        return velocity.y > 0 && abs(velocity.y) > abs(velocity.x)
    }
}

// MARK: - UIViewControllerTransitioningDelegate

extension MediaViewerViewController: UIViewControllerTransitioningDelegate {
    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        MediaViewerTransition(direction: .present)
    }

    func animationController(
        forDismissed dismissed: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        MediaViewerTransition(direction: .dismiss)
    }
}
