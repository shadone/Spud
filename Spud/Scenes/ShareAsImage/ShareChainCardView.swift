//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The comment-share card: a fixed-width (372pt), fixed-palette, theme- and
/// Dynamic-Type-independent artifact rendering a shared comment together with
/// its ancestor chain, so it can be exported to a PNG (Task 4) and reconfigured
/// live in the editor (Task 5). Like ``ShareCardView`` its height comes from
/// Auto Layout — build the view, add a 372pt width constraint, and read
/// `systemLayoutSizeFitting`.
///
/// Top to bottom: an optional post-context header (``ShareChainPostHeaderView``,
/// gated on `options.includePostInChain` AND a non-nil post summary), then the
/// ancestor lines walking DOWN toward the shared comment (with the middle
/// elided when there are more than four visible ancestors — see
/// ``ShareChainElision``), then a footer identical to the post card's.
///
/// Guardrails baked into the layout (not options): the ``footerView`` permalink
/// is the SHARED COMMENT's and renders in every configuration, and the shared
/// comment's own absolute timestamp renders even when identities are redacted —
/// redaction masks only the person lockups (authors), never the permalink or
/// the destination timestamp. Only the "via Spud" mark toggles.
final class ShareChainCardView: UIView {
    /// The card's fixed design width.
    static let designWidth = ShareCardMetrics.width

    /// The dim applied to a toggled-off section in ``applyForEditor(options:)``.
    static let editorGhostAlpha: CGFloat = 0.3

    let postHeaderView = ShareChainPostHeaderView()
    let footerView = ShareCardFooterView()

    private let content: ShareCardContent
    private var options: ShareCardOptions
    private let locale: Locale
    private let timeZone: TimeZone

    /// The ancestor/destination chain rows, exposed so the editor's tap overlay
    /// can map a tap on the chain to the redact-identities toggle.
    let rowsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [postHeaderView, rowsStack, footerView])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// - Parameters:
    ///   - locale/timeZone: the absolute-timestamp determinism seam, matching
    ///     ``ShareCardView``. Production passes `.current`; snapshot tests pin
    ///     `en_US_POSIX`/`GMT` so a recorded reference never depends on the
    ///     running machine.
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

        // The footer carries its own hairline top border, so it needs a touch
        // more breathing room above it than the chain's inter-line spacing.
        contentStack.setCustomSpacing(20, after: postHeaderView)
        contentStack.setCustomSpacing(20, after: rowsStack)
    }

    /// Reconfigures the whole card for a new options set — the editor's live
    /// path. Rebuilds the palette, shows/hides the post header, re-derives and
    /// rebuilds the chain rows (depth + elision), and re-applies the footer.
    func apply(options: ShareCardOptions) {
        self.options = options
        let palette: ShareCardPalette = options.appearance == .dark ? .dark : .light

        backgroundColor = palette.panel
        layer.borderColor = palette.edge.cgColor

        applyPostHeader(palette: palette)
        rebuildRows(palette: palette)
        applyFooter(palette: palette)

        setNeedsLayout()
    }

    /// The editor's variant of ``apply(options:)``: keeps the post-context
    /// header VISIBLE but dimmed when `includePostInChain` is off, so a tap on
    /// the "ghost" can restore it (direct manipulation would otherwise be
    /// one-way). The export path uses the real ``apply(options:)``.
    func applyForEditor(options: ShareCardOptions) {
        var shown = options
        shown.includePostInChain = true
        apply(options: shown)
        postHeaderView.alpha = options.includePostInChain ? 1 : Self.editorGhostAlpha
    }

    // MARK: - Sections

    private func applyPostHeader(palette: ShareCardPalette) {
        guard options.includePostInChain, let post = content.post else {
            postHeaderView.isHidden = true
            return
        }
        postHeaderView.isHidden = false
        postHeaderView.configure(post: post, palette: palette)
    }

    private func rebuildRows(palette: ShareCardPalette) {
        for view in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let rows = ShareChainElision.visibleRows(chain: content.chain, depth: options.chainDepth)
        for row in rows {
            switch row {
            case let .item(item):
                let rowView = ShareChainRowView()
                rowView.configure(
                    item: item,
                    redactIdentities: options.redactIdentities,
                    palette: palette,
                    locale: locale,
                    timeZone: timeZone
                )
                rowsStack.addArrangedSubview(rowView)
            case let .elision(count):
                rowsStack.addArrangedSubview(makeElisionRow(count: count, palette: palette))
            }
        }
    }

    private func applyFooter(palette: ShareCardPalette) {
        // Guardrail: the footer permalink is the SHARED COMMENT's, and it always
        // renders (no option removes it).
        guard let permalink = content.chain.last(where: \.isDestination)?.permalink else {
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

    /// Builds the "N more replies" divider standing in for the elided middle of
    /// a deep chain. A short faint rail stub (aligned with the ancestor rails)
    /// keeps the thread visually continuous through the gap.
    private func makeElisionRow(count: Int, palette: ShareCardPalette) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let railStub = UIView()
        railStub.translatesAutoresizingMaskIntoConstraints = false
        railStub.backgroundColor = palette.hair
        railStub.layer.cornerRadius = ShareCardMetrics.chainRailWidth / 2
        railStub.layer.cornerCurve = .continuous
        container.addSubview(railStub)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = ShareCardFonts.chainElision
        label.textColor = palette.faint
        label.text = ShareChainElision.elisionLabel(count: count)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            railStub.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            railStub.widthAnchor.constraint(equalToConstant: ShareCardMetrics.chainRailWidth),
            railStub.topAnchor.constraint(equalTo: container.topAnchor),
            railStub.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            label.leadingAnchor.constraint(equalTo: railStub.trailingAnchor, constant: 11),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}
