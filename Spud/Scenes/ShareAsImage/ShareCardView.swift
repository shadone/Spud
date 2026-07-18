//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The post share card: a fixed-width (372 pt), fixed-palette, theme- and
/// Dynamic-Type-independent designed artifact that renders identically
/// off-screen so it can be exported to a PNG (Task 4) and reconfigured live in
/// the editor (Task 5). Height comes from Auto Layout — build the view, add a
/// 372-pt width constraint, and read `systemLayoutSizeFitting`.
///
/// The major sections are exposed as internal subviews with stable names
/// (`headerView`, `titleLabel`, `mediaView`, `bodyView`, `statsView`,
/// `footerView`) because the editor reconfigures via ``apply(options:)`` and
/// maps its direct-manipulation tap targets to these subviews' frames.
///
/// Guardrails baked into the layout (not options): the ``footerView`` permalink
/// and the ``statsView`` timestamp render in EVERY configuration — no option
/// can remove them. Only the "via Spud" mark toggles. NSFW media is spoilered
/// with a real Core-Image blur (see ``ShareCardMediaView``), never a live
/// visual-effect view.
final class ShareCardView: UIView {
    /// The card's fixed design width.
    static let designWidth = ShareCardMetrics.width

    let headerView = ShareCardHeaderView()
    let titleLabel = UILabel()
    let mediaView = ShareCardMediaView()
    let bodyView = ShareCardBodyView()
    let statsView = ShareCardStatsView()
    let footerView = ShareCardFooterView()

    /// Loads the post's media on demand. Wired by the editor (Task 5) to
    /// `ImageServiceType.fetch`; left `nil` by snapshot tests, which inject a
    /// solid-color image via ``setMediaImage(_:)`` instead — so the card never
    /// has a network dependency in a test.
    var imageLoader: (@MainActor (URL) async -> UIImage?)?

    /// Fired after the card relays out (option change or async media arrival),
    /// so the editor can re-center / re-measure the live preview.
    var onLayoutChange: (() -> Void)?

    private let content: ShareCardContent
    private var options: ShareCardOptions
    private let locale: Locale
    private let timeZone: TimeZone
    private var hasMediaImage = false
    private var mediaLoadToken = UUID()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [
            headerView, titleLabel, mediaView, bodyView, statsView, footerView,
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// - Parameters:
    ///   - locale/timeZone: the absolute-timestamp determinism seam. Production
    ///     passes `.current`; snapshot tests pin `en_US_POSIX`/`GMT` so a
    ///     recorded reference never depends on the running machine.
    init(
        content: ShareCardContent,
        options: ShareCardOptions,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        self.content = content
        self.options = options
        self.locale = locale
        self.timeZone = timeZone
        super.init(frame: .zero)
        setUp()
        apply(options: options)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        layer.cornerRadius = ShareCardMetrics.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = ShareCardMetrics.hairline
        clipsToBounds = true

        titleLabel.numberOfLines = 0

        // The card's fixed 26pt padding must stay fixed: without this, UIKit
        // inflates the layout margins by the safe-area inset whenever the card
        // sits under a bar (the editor's full-bleed scroll view, or a snapshot
        // host window), silently growing the top padding by the 54pt status bar.
        insetsLayoutMarginsFromSafeArea = false
        directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: ShareCardMetrics.padding,
            leading: ShareCardMetrics.padding,
            bottom: ShareCardMetrics.padding,
            trailing: ShareCardMetrics.padding
        )
        addSubview(contentStack)
        let margins = layoutMarginsGuide
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: margins.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
        ])

        // The footer carries its own hairline top border + inset, so it needs
        // less stack spacing above it than the other sections.
        contentStack.setCustomSpacing(20, after: headerView)
        contentStack.setCustomSpacing(18, after: statsView)
    }

    /// The dim applied to a toggled-off section in ``applyForEditor(options:)``
    /// so it reads as a "ghost" the editor's tap overlay can restore.
    static let editorGhostAlpha: CGFloat = 0.3

    /// Injects a media image directly (bypassing ``imageLoader``). The test
    /// seam; the editor also uses it once its async fetch resolves.
    func setMediaImage(_ image: UIImage?) {
        hasMediaImage = image != nil
        mediaView.setMediaImage(image)
    }

    /// The editor's variant of ``apply(options:)``: it keeps the hide-toggleable
    /// sections (community/creator header, media, and — when the body treatment
    /// is `.titleOnly` — the body) VISIBLE but dimmed, so a tap on the dimmed
    /// "ghost" can toggle the section back on. Direct manipulation would
    /// otherwise be one-way: once a section collapses there is nothing left on
    /// the card to tap. The export path uses the real ``apply(options:)`` (true
    /// hiding), never this — a hidden section is genuinely absent from the PNG.
    func applyForEditor(options: ShareCardOptions) {
        var shown = options
        shown.showCommunityAndCreator = true
        shown.showMedia = true
        let bodyGhosted = options.bodyTreatment == .titleOnly
        if bodyGhosted {
            // Render a dimmed truncated preview as the restore affordance rather
            // than an empty gap where the title-only body would be.
            shown.bodyTreatment = .truncate
        }
        apply(options: shown)

        headerView.alpha = options.showCommunityAndCreator ? 1 : Self.editorGhostAlpha
        mediaView.alpha = options.showMedia ? 1 : Self.editorGhostAlpha
        bodyView.alpha = bodyGhosted ? Self.editorGhostAlpha : 1
    }

    /// Reconfigures the whole card for a new options set — the editor's live
    /// path. Rebuilds the palette, shows/hides sections, and re-applies every
    /// subview, then fires ``onLayoutChange``.
    func apply(options: ShareCardOptions) {
        self.options = options
        let palette: ShareCardPalette = options.appearance == .dark ? .dark : .light

        backgroundColor = palette.panel
        layer.borderColor = palette.edge.cgColor

        applyTitle(palette: palette)
        applyHeader(palette: palette)
        applyMedia(palette: palette)
        applyBody(palette: palette)
        applyStats(palette: palette)
        applyFooter(palette: palette)

        loadMediaIfNeeded()

        setNeedsLayout()
        onLayoutChange?()
    }

    // MARK: - Section application

    private func applyTitle(palette: ShareCardPalette) {
        guard let post = content.post else {
            titleLabel.isHidden = true
            return
        }
        titleLabel.isHidden = false
        titleLabel.attributedText = NSAttributedString(
            string: post.title,
            attributes: [
                .font: ShareCardFonts.title,
                .foregroundColor: palette.ink,
                .paragraphStyle: ShareCardStyle.paragraphStyle(lineHeightMultiple: 1.18),
            ]
        )
    }

    private func applyHeader(palette: ShareCardPalette) {
        guard let post = content.post else {
            headerView.isHidden = true
            return
        }
        headerView.configure(post: post, redactIdentities: options.redactIdentities, palette: palette)
        headerView.isHidden = !options.showCommunityAndCreator
    }

    private func applyMedia(palette: ShareCardPalette) {
        guard let post = content.post, post.mediaUrl != nil, options.showMedia else {
            mediaView.isHidden = true
            return
        }
        mediaView.isHidden = false
        mediaView.configure(
            mediaAspectIsWide: post.mediaAspectIsWide,
            isNsfw: post.isNsfw,
            nsfwRevealed: options.nsfwRevealed,
            palette: palette
        )
    }

    private func applyBody(palette: ShareCardPalette) {
        let hasBody = bodyView.configure(
            bodyPlain: content.post?.bodyPlain,
            treatment: options.bodyTreatment,
            palette: palette
        )
        bodyView.isHidden = !hasBody
    }

    private func applyStats(palette: ShareCardPalette) {
        guard let post = content.post else {
            statsView.isHidden = true
            return
        }
        // Never hidden: the timestamp is a guardrail element (see the
        // type-level note). Only the score/comment cluster toggles, inside the
        // stats view itself.
        statsView.isHidden = false
        statsView.configure(
            post: post,
            showStats: options.showStats,
            palette: palette,
            locale: locale,
            timeZone: timeZone
        )
    }

    private func applyFooter(palette: ShareCardPalette) {
        // Never hidden: the permalink is a guardrail element.
        let permalink = content.post?.permalink
            ?? content.chain.last(where: \.isDestination)?.permalink
        guard let permalink else {
            footerView.isHidden = true
            return
        }
        footerView.isHidden = false
        footerView.configure(
            permalink: permalink,
            showViaSpudMark: options.showViaSpudMark,
            palette: palette
        )
    }

    // MARK: - Media loading

    private func loadMediaIfNeeded() {
        guard let imageLoader,
              !hasMediaImage,
              options.showMedia,
              let url = content.post?.mediaUrl
        else { return }

        let token = UUID()
        mediaLoadToken = token
        Task { [weak self] in
            let image = await imageLoader(url)
            guard let self, mediaLoadToken == token, image != nil else { return }
            hasMediaImage = true
            mediaView.setMediaImage(image)
            onLayoutChange?()
        }
    }
}
