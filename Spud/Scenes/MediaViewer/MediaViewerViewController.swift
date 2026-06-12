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

    /// Distance the user must drag down (after the gesture resolves to a
    /// dismiss) before release commits the dismissal.
    private let dismissThreshold: CGFloat = 120

    private var isBarHidden = false

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

    private var topBarTopConstraint: NSLayoutConstraint!

    // MARK: Functions

    init(items: [MediaItem], startIndex: Int, dependencies: Dependencies) {
        precondition(!items.isEmpty, "MediaViewer requires at least one item")
        self.items = items
        currentIndex = min(max(0, startIndex), items.count - 1)
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
    }

    private func setupTopBar() {
        view.addSubview(topBarBackgroundView)
        topBarBackgroundView.contentView.addSubview(closeButton)
        topBarBackgroundView.contentView.addSubview(shareButton)
        topBarBackgroundView.contentView.addSubview(saveButton)

        view.addSubview(pageControl)

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
        ])
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
            imageService: imageService
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
        let finish = { [self] in setBar(hidden: false) }
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
        guard let image = currentPage?.zoomableImageView.image else {
            // Nothing loaded yet — share the URL instead.
            let url = items[currentIndex].imageUrl
            presentActivity(items: [url])
            return
        }
        presentActivity(items: [image])
    }

    private func presentActivity(items: [Any]) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = shareButton
        activityVC.popoverPresentationController?.sourceRect = shareButton.bounds
        present(activityVC, animated: true)
    }

    @objc
    private func saveTapped() {
        guard let image = currentPage?.zoomableImageView.image else {
            Haptics.warning()
            return
        }
        saveToPhotos(image)
    }

    private func saveToPhotos(_ image: UIImage) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            performSave(image)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if newStatus == .authorized || newStatus == .limited {
                        performSave(image)
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

    private func performSave(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
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
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MediaViewerViewController: UIGestureRecognizerDelegate {
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
