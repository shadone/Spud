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
    private var loadTask: Task<Void, Never>?
    private var hasLaidOutImage = false

    // MARK: Functions

    init(item: MediaItem, imageService: ImageServiceType) {
        self.item = item
        self.imageService = imageService
        super.init(frame: .zero)

        addSubview(scrollView)
        scrollView.addSubview(imageView)
        addSubview(activityIndicator)
        addSubview(errorImageView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),

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
    }

    /// Kick off (or restart) the image load. Idempotent enough to call from
    /// the page VC's `viewDidLoad`.
    func startLoading() {
        guard loadTask == nil else { return }

        if item.preloadedImage == nil {
            activityIndicator.startAnimating()
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            for await state in imageService.fetch(item.imageUrl, thumbnail: item.thumbnailUrl) {
                if Task.isCancelled { return }
                switch state {
                case let .loading(thumbnailImage):
                    if let thumbnailImage, image == nil {
                        setImage(thumbnailImage, isFinal: false)
                    }
                case let .ready(image):
                    activityIndicator.stopAnimating()
                    errorImageView.isHidden = true
                    setImage(image, isFinal: true)
                case .failure:
                    activityIndicator.stopAnimating()
                    if image == nil {
                        errorImageView.isHidden = false
                    }
                }
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // The very first time we have both a non-zero size and an image, fit
        // it to the bounds and centre it.
        if !hasLaidOutImage, imageView.image != nil, bounds.width > 0 {
            hasLaidOutImage = true
            configureZoomScales()
        }
    }

    // MARK: Private

    private func setImage(_ image: UIImage, isFinal: Bool) {
        let hadImage = imageView.image != nil
        imageView.image = image

        // Re-fit on the first image, or when swapping a thumbnail for the
        // full-resolution asset while still at minimum zoom.
        if !hadImage || (isFinal && !isZoomed) {
            hasLaidOutImage = bounds.width > 0
            if hasLaidOutImage {
                configureZoomScales()
            } else {
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

    private func centreImage() {
        let boundsSize = scrollView.bounds.size
        var frameToCenter = imageView.frame

        if frameToCenter.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }

        if frameToCenter.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }

        imageView.frame = frameToCenter
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
