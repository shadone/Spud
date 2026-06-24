//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import SpudDataKit
import SpudMarkdownKit
import SpudUIKit
import UIKit

private let logger = Logger.app

/// The optimistic "pending post" screen shown the moment a new post is durably
/// enqueued (the composer dismisses straight to here). It renders the post from
/// its outbound row — title, optional URL, markdown body — under a status banner
/// that reflects the outbox lifecycle:
///
/// - queued / sending  -> spinner + "Sending…"
/// - failed            -> "Couldn't post" + Retry / Discard
///
/// On a successful send the outbox emits a `ComposerOutboxSuccess` carrying the
/// real `serverPostId`; this controller fires `onResolvedPost` so the presenter
/// can swap this screen in place for the real post detail. The outbound row also
/// vanishes on success (a send deletes it), but the row stream alone can't carry
/// the new id, so the success-event subscription is the authoritative resolver.
final class PendingPostViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase &
        HasImageService
    typealias Dependencies = OwnDependencies
    private let dependencies: OwnDependencies

    /// Invoked once the queued post has been accepted by the server, carrying the
    /// real post id so the presenter can replace this pending screen with the
    /// real post detail.
    var onResolvedPost: ((Components.Schemas.PostID) -> Void)?

    private let clientToken: String
    private let accountKeychainId: String

    private var observationTasks: [Task<Void, Never>] = []

    /// Set once a row has been rendered so a later re-render only updates the
    /// fields that changed (avoids rebuilding the markdown body needlessly).
    private var lastRenderedRow: OutboundContentRecord?
    /// Set once the success event has fired so a trailing row-vanished update
    /// doesn't flip the banner back to "Sending…".
    private var resolved = false

    // MARK: UI

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
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

    // MARK: Status banner

    private lazy var bannerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 10
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var bannerSpinner: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var bannerIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.isHidden = true
        return imageView
    }()

    private lazy var bannerLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }()

    private lazy var retryButton: UIButton = {
        var config = UIButton.Configuration.borderedProminent()
        config.title = NSLocalizedString("Retry", comment: "Retry a failed pending post send")
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var discardButton: UIButton = {
        var config = UIButton.Configuration.bordered()
        config.title = NSLocalizedString("Discard", comment: "Discard a failed pending post")
        config.baseForegroundColor = .systemRed
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(discardTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var failedActionsRow: UIStackView = {
        let row = UIStackView(arrangedSubviews: [retryButton, discardButton, UIView()])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.isHidden = true
        return row
    }()

    // MARK: Post content

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }()

    private lazy var urlButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "link")
        config.imagePadding = 6
        config.contentInsets = .zero
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.addTarget(self, action: #selector(urlTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var bodyView: MarkdownBodyView = {
        let context = MarkdownContext(kind: .post)
        let view = MarkdownBodyView(context: context)
        view.imageLoader = { [imageService = dependencies.imageService] url in
            for await state in imageService.fetch(url) {
                if case let .ready(image) = state { return image }
            }
            return nil
        }
        view.isHidden = true
        return view
    }()

    private var renderedUrl: URL?

    // MARK: Functions

    init(
        clientToken: String,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.clientToken = clientToken
        self.accountKeychainId = accountKeychainId
        self.dependencies = dependencies
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
        startObservations()
    }

    private func setup() {
        view.backgroundColor = Theme.background
        navigationItem.title = NSLocalizedString("Posting", comment: "Title of the pending-post screen")

        let bannerContent = UIStackView(arrangedSubviews: [bannerSpinner, bannerIcon, bannerLabel])
        bannerContent.axis = .horizontal
        bannerContent.spacing = 10
        bannerContent.alignment = .center
        bannerContent.translatesAutoresizingMaskIntoConstraints = false
        bannerView.addSubview(bannerContent)
        NSLayoutConstraint.activate([
            bannerContent.topAnchor.constraint(equalTo: bannerView.topAnchor, constant: 12),
            bannerContent.bottomAnchor.constraint(equalTo: bannerView.bottomAnchor, constant: -12),
            bannerContent.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor, constant: 14),
            bannerContent.trailingAnchor.constraint(equalTo: bannerView.trailingAnchor, constant: -14),
        ])

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        stackView.addArrangedSubview(bannerView)
        stackView.addArrangedSubview(failedActionsRow)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(urlButton)
        stackView.addArrangedSubview(bodyView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        // Default state until the first row lands: assume it's on its way out.
        applyBanner(status: .queued)
    }

    private func startObservations() {
        // Render the queued post from its outbound row, and follow status changes.
        observationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            for await rows in dependencies.appDatabase.observeOutboundContent(accountKeychainId: accountKeychainId) {
                if Task.isCancelled { break }
                guard let row = rows.first(where: { $0.clientToken == clientToken }) else {
                    // The row vanished: a successful send deleted it. The success
                    // event (below) carries the real id and drives the swap; do
                    // nothing here so we don't flip the banner back to "Sending…".
                    continue
                }
                render(row)
            }
        })

        // Swap to the real post on a matching success event. Started in
        // viewDidLoad (at push time) so a fast send isn't missed.
        observationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            let scope = dependencies.accountService.scope(forAccountKeychainId: accountKeychainId)
            for await success in await scope.composerSuccessEvents() {
                if Task.isCancelled { break }
                guard success.clientToken == clientToken else { continue }
                guard let serverPostId = success.serverPostId else { continue }
                resolved = true
                onResolvedPost?(Components.Schemas.PostID(serverPostId))
                break
            }
        })
    }

    // MARK: Rendering

    private func render(_ row: OutboundContentRecord) {
        guard !resolved else { return }

        let status = OutboundStatus(rawValue: row.status) ?? .queued
        applyBanner(status: status)

        // Only rebuild content fields when they actually change.
        guard lastRenderedRow?.title != row.title
            || lastRenderedRow?.url != row.url
            || lastRenderedRow?.body != row.body
            || lastRenderedRow == nil
        else {
            lastRenderedRow = row
            return
        }
        lastRenderedRow = row

        let title = row.title ?? ""
        titleLabel.text = title
        titleLabel.isHidden = title.isEmpty

        if let urlString = row.url, !urlString.isEmpty {
            renderedUrl = URL(string: urlString)
            urlButton.setTitle(urlString, for: .normal)
            urlButton.isHidden = false
        } else {
            renderedUrl = nil
            urlButton.isHidden = true
        }

        let body = row.body
        if body.isEmpty {
            bodyView.isHidden = true
            bodyView.setBlocks([])
        } else {
            bodyView.isHidden = false
            // Parse off-main, then render the blocks back on main.
            Task { @MainActor [weak self] in
                await MarkdownBlockCache.shared.prewarm(body)
                guard let self, lastRenderedRow?.body == body else { return }
                bodyView.setBlocks(MarkdownBlockCache.shared.blocks(for: body))
            }
        }
    }

    private func applyBanner(status: OutboundStatus) {
        switch status {
        case .draft, .queued, .sending:
            bannerView.backgroundColor = Theme.secondaryGroupedBackground
            bannerSpinner.startAnimating()
            bannerIcon.isHidden = true
            bannerLabel.textColor = .secondaryLabel
            bannerLabel.text = NSLocalizedString("Sending…", comment: "Status banner while a queued post is being sent")
            failedActionsRow.isHidden = true

        case .failed:
            bannerView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.12)
            bannerSpinner.stopAnimating()
            bannerIcon.image = UIImage(systemName: "exclamationmark.triangle.fill")
            bannerIcon.tintColor = .systemRed
            bannerIcon.isHidden = false
            bannerLabel.textColor = .systemRed
            bannerLabel.text = NSLocalizedString("Couldn't post", comment: "Status banner when a queued post permanently failed")
            retryButton.isHidden = false
            discardButton.isHidden = false
            failedActionsRow.isHidden = false
        }
    }

    // MARK: Actions

    @objc
    private func retryTapped() {
        Haptics.tap()
        // Optimistically flip back to sending so the UI feels responsive; the
        // row observation will reconcile the real status.
        applyBanner(status: .queued)
        let scope = dependencies.accountService.scope(forAccountKeychainId: accountKeychainId)
        let clientToken = clientToken
        Task { await scope.lemmyService.retryComposition(clientToken: clientToken) }
    }

    @objc
    private func discardTapped() {
        Haptics.tap()
        let scope = dependencies.accountService.scope(forAccountKeychainId: accountKeychainId)
        let clientToken = clientToken
        Task { @MainActor [weak self] in
            await scope.lemmyService.discardComposition(clientToken: clientToken)
            // The post is gone; pop back to where the user came from.
            self?.navigationController?.popViewController(animated: true)
        }
    }

    @objc
    private func urlTapped() {
        guard let renderedUrl else { return }
        UIApplication.shared.open(renderedUrl)
    }
}
