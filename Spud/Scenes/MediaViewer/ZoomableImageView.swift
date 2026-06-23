//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// A zoomable, pannable host for a single image.
///
/// Wraps a `UIScrollView` whose only subview is a `UIImageView`. Supports
/// pinch-zoom, double-tap-to-toggle-zoom and pan when zoomed. Loads its image
/// through `ImageService` (thumbnail first, then full resolution) and shows a
/// spinner / broken-image state while doing so.
final class ZoomableImageView: UIView {
    // MARK: Public

    /// Whether the image is currently zoomed past its minimum scale. The
    /// container uses this to decide whether a downward pan should dismiss or
    /// be left to the scroll view for panning.
    var isZoomed: Bool {
        scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
    }

    /// Forwarded so the container can recentre the image after layout passes.
    var image: UIImage? {
        imageView.image
    }

    // MARK: Test seams

    /// Whether the loading spinner is currently animating. Test seam.
    var isLoadingIndicatorVisible: Bool {
        activityIndicator.isAnimating
    }

    /// Whether the broken-image icon is hidden. Test seam.
    var isErrorIconHiddenForTesting: Bool {
        errorImageView.isHidden
    }

    /// Awaits the in-flight load so tests can assert the terminal `.ready` /
    /// `.failure` state deterministically. Test seam.
    func awaitLoadForTesting() async {
        await loadTask?.value
    }

    // MARK: UI Properties

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        return scrollView
    }()

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.accessibilityIdentifier = "mediaViewerImage"
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        imageView.accessibilityLabel = NSLocalizedString(
            "Image", comment: "Accessibility label for the full-screen image"
        )
        return imageView
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .large)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.color = .white
        view.hidesWhenStopped = true
        view.isAccessibilityElement = true
        view.accessibilityLabel = NSLocalizedString(
            "Loading full image",
            comment: "Accessibility label for the full-screen image loading spinner"
        )
        return view
    }()

    /// A subtle rounded scrim behind the spinner so it reads over a bright
    /// upscaled thumbnail. Hidden until the spinner is shown, and hidden again
    /// alongside it.
    private lazy var indicatorScrim: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        view.layer.cornerRadius = 14
        view.isHidden = true
        return view
    }()

    private lazy var errorImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.white.withAlphaComponent(0.6)
        imageView.image = UIImage(systemName: "photo.badge.exclamationmark")
        imageView.isHidden = true
        return imageView
    }()

    // MARK: Private

    private let item: MediaItem
    private let imageService: ImageServiceType
    private let gracePeriod: Duration
    private var loadTask: Task<Void, Never>?

    /// Armed by `startLoading()`; after `gracePeriod` it asks
    /// `presentIndicatorIfStillLoading()` to show the spinner. Cancelled on
    /// `.ready` / `.failure` and in `deinit`.
    private var showIndicatorTask: Task<Void, Never>?

    /// Set true once the load resolves, on either `.ready` or `.failure`. The
    /// indicator's visibility depends only on this, not on whether a placeholder
    /// is on screen.
    private var loadDidComplete = false

    private var hasLaidOutImage = false

    /// The bounds size the image was last fitted to. Tracked so a change in
    /// available size (the transient bounds during the present transition
    /// settling to full screen, or a rotation) re-fits the image while it
    /// isn't zoomed in.
    private var lastLaidOutBoundsSize: CGSize = .zero

    // MARK: Functions

    init(
        item: MediaItem,
        imageService: ImageServiceType,
        gracePeriod: Duration = .milliseconds(400)
    ) {
        self.item = item
        self.imageService = imageService
        self.gracePeriod = gracePeriod
        super.init(frame: .zero)

        addSubview(scrollView)
        scrollView.addSubview(imageView)
        // Z-order: scrollView < scrim + spinner < errorImageView. The error icon
        // and the spinner never display simultaneously.
        addSubview(indicatorScrim)
        indicatorScrim.addSubview(activityIndicator)
        addSubview(errorImageView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            indicatorScrim.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicatorScrim.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicatorScrim.widthAnchor.constraint(equalToConstant: 56),
            indicatorScrim.heightAnchor.constraint(equalToConstant: 56),

            activityIndicator.centerXAnchor.constraint(equalTo: indicatorScrim.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: indicatorScrim.centerYAnchor),

            errorImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorImageView.widthAnchor.constraint(equalToConstant: 64),
            errorImageView.heightAnchor.constraint(equalToConstant: 64),
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)

        // Instant first frame from a preloaded image, if any.
        if let preloaded = item.preloadedImage {
            setImage(preloaded, isFinal: false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        showIndicatorTask?.cancel()
    }

    /// Kick off (or restart) the image load. Idempotent enough to call from
    /// the page VC's `viewDidLoad`.
    func startLoading() {
        guard loadTask == nil else { return }

        // Show the spinner only after a short grace delay, and only if the final
        // image hasn't arrived yet — a memory-cache hit / fast load resolves to
        // `.ready` and cancels this task well before it fires, so it never
        // flashes. Visibility depends only on whether the final image has
        // arrived, never on whether a placeholder is showing.
        showIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: self?.gracePeriod ?? .zero)
            guard !Task.isCancelled else { return }
            self?.presentIndicatorIfStillLoading()
        }

        // Animated assets (GIF) are decoded through the animated path so the
        // viewer plays them; a static image set on a UIImageView would not.
        let stream = item.isAnimated
            ? imageService.fetchAnimatedImage(item.imageUrl)
            : imageService.fetch(item.imageUrl, thumbnail: item.thumbnailUrl)

        loadTask = Task { [weak self] in
            guard let self else { return }
            for await state in stream {
                if Task.isCancelled { return }
                switch state {
                case let .loading(thumbnailImage):
                    if let thumbnailImage, image == nil {
                        setImage(thumbnailImage, isFinal: false)
                    }
                case let .ready(image):
                    loadDidComplete = true
                    hideIndicator()
                    errorImageView.isHidden = true
                    setImage(image, isFinal: true)
                case .failure:
                    loadDidComplete = true
                    hideIndicator()
                    if image == nil {
                        errorImageView.isHidden = false
                    }
                }
            }
        }
    }

    /// The single code path that starts the spinner. Shows the spinner + scrim
    /// only while the load is still in flight. Called by the grace task; once the
    /// load has resolved (`.ready` or `.failure`) it is a no-op.
    func presentIndicatorIfStillLoading() {
        guard !loadDidComplete else { return }
        indicatorScrim.isHidden = false
        activityIndicator.startAnimating()
    }

    private func hideIndicator() {
        showIndicatorTask?.cancel()
        activityIndicator.stopAnimating()
        indicatorScrim.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard imageView.image != nil, bounds.width > 0, bounds.height > 0 else { return }

        // Fit on first layout, and re-fit when the available size changes while
        // the user hasn't zoomed in. Otherwise just re-centre: the scroll view
        // would pin sub-screen content to the top-left on a plain layout pass.
        if !hasLaidOutImage || (bounds.size != lastLaidOutBoundsSize && !isZoomed) {
            hasLaidOutImage = true
            lastLaidOutBoundsSize = bounds.size
            configureZoomScales()
        } else {
            centreImage()
        }
    }

    // MARK: Private

    private func setImage(_ image: UIImage, isFinal: Bool) {
        let hadImage = imageView.image != nil
        imageView.image = image

        // Re-fit on the first image, or when swapping a thumbnail for the
        // full-resolution asset while still at minimum zoom.
        if !hadImage || (isFinal && !isZoomed) {
            if bounds.width > 0, bounds.height > 0 {
                hasLaidOutImage = true
                lastLaidOutBoundsSize = bounds.size
                configureZoomScales()
            } else {
                hasLaidOutImage = false
                setNeedsLayout()
            }
        }
    }

    /// Compute min/max zoom so the image fits aspect-fit at min scale and can
    /// be zoomed in to a useful maximum, then centre it.
    private func configureZoomScales() {
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        // Reset to identity zoom BEFORE touching the zoom view's frame. On a
        // reconfigure (thumbnail -> full image) the previous image left larger
        // min/max zoom scales behind; without resetting them first, `zoomScale =
        // 1` would clamp to the old minimum and the new fit would be computed
        // from a corrupted zoom base — leaving the image off-centre until a
        // pinch recomputed it.
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.zoomScale = 1

        imageView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize

        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let minScale = min(widthScale, heightScale)

        scrollView.minimumZoomScale = minScale
        // Allow zooming to at least 3x the fitted size, and never below the
        // image's native resolution.
        scrollView.maximumZoomScale = max(minScale * 3, 1)
        scrollView.zoomScale = minScale

        centreImage()
    }

    /// Centre the image by insetting the scroll view, so content smaller than
    /// the screen sits in the middle instead of pinned to the top-left. Unlike
    /// nudging the image view's frame origin, `contentInset` survives the
    /// scroll view's own layout passes, so the image stays centred after the
    /// present transition and any later re-layout.
    private func centreImage() {
        let contentSize = scrollView.contentSize
        let boundsSize = scrollView.bounds.size
        let horizontalInset = max(0, (boundsSize.width - contentSize.width) / 2)
        let verticalInset = max(0, (boundsSize.height - contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    @objc
    private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if isZoomed {
            let animated = !UIAccessibility.isReduceMotionEnabled
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
        } else {
            let point = recognizer.location(in: imageView)
            let targetScale = min(scrollView.maximumZoomScale, scrollView.minimumZoomScale * 3)
            let zoomRect = zoomRect(for: targetScale, centeredOn: point)
            let animated = !UIAccessibility.isReduceMotionEnabled
            if animated {
                scrollView.zoom(to: zoomRect, animated: true)
            } else {
                scrollView.zoomScale = targetScale
                scrollView.scrollRectToVisible(zoomRect, animated: false)
            }
        }
    }

    private func zoomRect(for scale: CGFloat, centeredOn point: CGPoint) -> CGRect {
        let size = CGSize(
            width: scrollView.bounds.width / scale,
            height: scrollView.bounds.height / scale
        )
        return CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

extension ZoomableImageView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centreImage()
    }
}
