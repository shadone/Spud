//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

/// In-app instance browse screen. Reached after the user taps an instance in the
/// Discover feed (or elsewhere in the app). Shows banner + description + sidebar +
/// stats + health + admins + community list. No sticky action bar.
final class InstanceExploreViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppDatabase &
        HasImageService
    typealias NestedDependencies =
        InstanceDetailViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    private var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    private var alertService: AlertServiceType {
        dependencies.own.alertService
    }

    private let record: ExplorerInstanceRecord
    private let viewModel: InstanceExploreViewModel

    private let scrollView = UIScrollView()
    private let bannerHeader: InstanceBannerHeaderView
    private let aboutServerView = InstanceAboutServerView()
    private let adminsView = InstanceAdminsView()

    private var communitiesContainer: UIStackView!
    private var observationTasks: [Task<Void, Never>] = []

    private var accent: UIColor {
        ThemeManager.currentAccentColor
    }

    // MARK: Init

    init(
        record: ExplorerInstanceRecord,
        accountKeychainId: String,
        dependencies: Dependencies,
        initialJoinedCommunityUrls: Set<String> = []
    ) {
        self.record = record
        self.dependencies = (own: dependencies, nested: dependencies)
        bannerHeader = InstanceBannerHeaderView(name: record.name, host: record.baseurl)
        viewModel = InstanceExploreViewModel(
            record: record,
            accountKeychainId: accountKeychainId,
            accountService: dependencies.accountService,
            appDatabase: dependencies.appDatabase,
            alertService: dependencies.alertService,
            initialJoinedCommunityUrls: initialJoinedCommunityUrls
        )
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        observationTasks.forEach { $0.cancel() }
    }

    // MARK: Test support

    /// The height of the scroll view's content after layout. Used by snapshot tests to
    /// size the snapshot tall enough to capture admins and communities below the fold.
    var snapshotContentHeight: CGFloat {
        view.layoutIfNeeded()
        return scrollView.contentSize.height
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        bannerHeader.loadImages(
            iconUrl: record.iconUrl,
            bannerUrl: record.bannerUrl,
            imageService: imageService
        )
        viewModel.load()
        // Apply the synchronous cache-first state from the VM before binding
        // async observation streams — snapshot tests capture this initial layout.
        applyCachedViewModelState()
        bindViewModel()
    }

    // MARK: Cache-first initial render

    private func applyCachedViewModelState() {
        adminsView.update(viewModel.adminsState)
        renderCommunities()
        if let sidebar = viewModel.sidebar, !sidebar.isEmpty {
            aboutServerView.configure(sidebar: sidebar, imageService: imageService)
            aboutServerView.isHidden = false
        }
    }

    // MARK: Setup

    private func setup() {
        view.backgroundColor = Theme.groupedBackground
        navigationItem.title = record.baseurl
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: UIAction { [weak self] _ in self?.shareTapped() },
            menu: nil
        )

        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide

        bannerHeader.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(bannerHeader)

        let body = makeBody()
        body.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(body)

        NSLayoutConstraint.activate([
            bannerHeader.topAnchor.constraint(equalTo: content.topAnchor),
            bannerHeader.leadingAnchor.constraint(equalTo: frame.leadingAnchor),
            bannerHeader.trailingAnchor.constraint(equalTo: frame.trailingAnchor),

            body.topAnchor.constraint(equalTo: bannerHeader.bottomAnchor, constant: 4),
            body.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: 16),
            body.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -16),
            body.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    // MARK: Body

    private func makeBody() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14

        // Description
        let descLabel = UILabel()
        descLabel.text = record.descriptionText?.isEmpty == false
            ? record.descriptionText
            : "No description provided by this server."
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0
        stack.addArrangedSubview(descLabel)
        stack.setCustomSpacing(15, after: descLabel)

        // About / Sidebar
        aboutServerView.isHidden = true
        aboutServerView.onHeightChange = { [weak self] in
            self?.view.layoutIfNeeded()
        }
        stack.addArrangedSubview(aboutServerView)

        // Stat grid
        stack.addArrangedSubview(makeStatGrid())

        // Health cross-link card
        stack.addArrangedSubview(makeHealthCard())

        // Admins
        adminsView.update(.loading)
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(adminsView)

        // Communities
        communitiesContainer = UIStackView()
        communitiesContainer.axis = .vertical
        communitiesContainer.spacing = 8
        stack.addArrangedSubview(communitiesContainer)

        return stack
    }

    private func makeStatGrid() -> UIView {
        let card = makeCard()
        let items: [(String, String)] = [
            (InstanceHealthStyle.formatCount(record.usersTotal), "Members"),
            (InstanceHealthStyle.formatCount(record.usersActiveMonth), "Active /mo"),
            (InstanceHealthStyle.formatCount(record.numberOfCommunities), "Communities"),
            (InstanceHealthStyle.formatCount(record.numberOfPosts), "Posts"),
        ]
        let top = makeGridRow(items[0], items[1])
        let bottom = makeGridRow(items[2], items[3])
        let grid = UIStackView(arrangedSubviews: [top, hairline(vertical: false), bottom])
        grid.axis = .vertical
        grid.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(grid)
        pinToCard(grid, card, inset: 0)
        return card
    }

    private func makeGridRow(_ a: (String, String), _ b: (String, String)) -> UIView {
        let left = statTile(a.0, a.1)
        let right = statTile(b.0, b.1)
        let line = hairline(vertical: true)
        let r = UIStackView(arrangedSubviews: [left, line, right])
        r.axis = .horizontal
        r.alignment = .fill
        left.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        return r
    }

    private func statTile(_ value: String, _ label: String) -> UIView {
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 19, weight: .heavy)
        valueLabel.textColor = value == "—" ? .tertiaryLabel : .label
        let captionLabel = UILabel()
        captionLabel.text = label.uppercased()
        captionLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        captionLabel.textColor = .tertiaryLabel
        let s = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        s.axis = .vertical
        s.spacing = 3
        s.alignment = .leading
        s.isLayoutMarginsRelativeArrangement = true
        s.layoutMargins = .init(top: 11, left: 12, bottom: 11, right: 12)
        return s
    }

    private func makeHealthCard() -> UIView {
        let card = makeCard()
        let trust = ExplorerInstanceHealth.trust(score100: score100(), suspicious: record.isSuspicious)
        let ring = InstanceScoreRingView()
        ring.configure(score100: score100(), color: InstanceHealthStyle.color(for: trust.level))
        ring.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 40),
            ring.heightAnchor.constraint(equalToConstant: 40),
        ])

        let trustLabel = UILabel()
        trustLabel.text = trust.label
        trustLabel.font = .systemFont(ofSize: 14, weight: .bold)
        trustLabel.textColor = InstanceHealthStyle.color(for: trust.level)

        let uptimeSignal = ExplorerInstanceHealth.uptime(record.uptimeAllTime)
        let uptimeText: String
        if uptimeSignal.level == .unknown {
            uptimeText = "uptime · since —"
        } else {
            uptimeText = "\(uptimeSignal.short) · since —"
        }
        let detailLabel = UILabel()
        detailLabel.text = uptimeText
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabel

        let textStack = UIStackView(arrangedSubviews: [trustLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 3

        let healthLabel = UILabel()
        healthLabel.text = "Health"
        healthLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        healthLabel.textColor = accent
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([chevron.widthAnchor.constraint(equalToConstant: 12)])
        let healthRow = UIStackView(arrangedSubviews: [healthLabel, chevron])
        healthRow.axis = .horizontal
        healthRow.spacing = 4
        healthRow.alignment = .center
        healthRow.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [ring, textStack, UIView(), healthRow])
        row.axis = .horizontal
        row.spacing = 14
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = .init(top: 12, left: 14, bottom: 12, right: 13)
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        pinToCard(row, card, inset: 0)

        let tap = UITapGestureRecognizer(target: self, action: #selector(healthCardTapped))
        card.addGestureRecognizer(tap)
        card.isUserInteractionEnabled = true

        return card
    }

    // MARK: Communities

    private func renderCommunities() {
        communitiesContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let countValue: Int? = record.numberOfCommunities > 0 ? Int(record.numberOfCommunities) : nil
        let header = InstanceSectionHeader()
        header.configure(title: "Communities", count: countValue)
        communitiesContainer.addArrangedSubview(header)

        let comms = viewModel.communities
        guard !comms.isEmpty else {
            let unavailableCard = makeCard()
            let label = UILabel()
            label.text = "Community list unavailable."
            label.font = .systemFont(ofSize: 13.5)
            label.textColor = .tertiaryLabel
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            unavailableCard.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: unavailableCard.topAnchor, constant: 14),
                label.leadingAnchor.constraint(equalTo: unavailableCard.leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: unavailableCard.trailingAnchor, constant: -14),
                label.bottomAnchor.constraint(equalTo: unavailableCard.bottomAnchor, constant: -14),
            ])
            communitiesContainer.addArrangedSubview(unavailableCard)
            return
        }

        let card = makeCard()
        let cardStack = UIStackView()
        cardStack.axis = .vertical
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        pinToCard(cardStack, card, inset: 0)

        let top3 = Array(comms.prefix(3))
        for (index, row) in top3.enumerated() {
            let joined = viewModel.joinedCommunityUrls.contains(row.communityUrl)
            let rowView = InstanceCommunityRowView(row: row, action: .join, joined: joined, accent: accent)
            rowView.onJoinTapped = { [weak self, weak rowView] in
                guard let self, let rowView else { return }
                handleJoin(row, rowView: rowView)
            }
            cardStack.addArrangedSubview(rowView)
            if index < top3.count - 1 {
                let line = UIView()
                line.backgroundColor = .separator
                line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                let insetLine = UIStackView(arrangedSubviews: [line])
                insetLine.isLayoutMarginsRelativeArrangement = true
                insetLine.layoutMargins = .init(top: 0, left: 13, bottom: 0, right: 0)
                cardStack.addArrangedSubview(insetLine)
            }
        }

        // "Browse all N communities" footer — display only, no tap handler.
        let footerLine = UIView()
        footerLine.backgroundColor = .separator
        footerLine.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        let insetFooterLine = UIStackView(arrangedSubviews: [footerLine])
        insetFooterLine.isLayoutMarginsRelativeArrangement = true
        insetFooterLine.layoutMargins = .init(top: 0, left: 13, bottom: 0, right: 0)
        cardStack.addArrangedSubview(insetFooterLine)

        let browseLabel = UILabel()
        let totalCount: Int? = record.numberOfCommunities > 0 ? Int(record.numberOfCommunities) : nil
        if let total = totalCount {
            browseLabel.text = "Browse all \(total) communities"
        } else {
            browseLabel.text = "Browse all communities"
        }
        browseLabel.font = .systemFont(ofSize: 14.5)
        browseLabel.textColor = .secondaryLabel
        let footerRow = UIStackView(arrangedSubviews: [browseLabel])
        footerRow.axis = .horizontal
        footerRow.alignment = .center
        footerRow.isLayoutMarginsRelativeArrangement = true
        footerRow.layoutMargins = .init(top: 11, left: 14, bottom: 11, right: 14)
        cardStack.addArrangedSubview(footerRow)

        communitiesContainer.addArrangedSubview(card)
    }

    // MARK: Join

    private func handleJoin(_ row: CommunityListRow, rowView: InstanceCommunityRowView) {
        guard !viewModel.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString(
                    "Sign in to join",
                    comment: "Sign-in gate when a signed-out user taps Join on a community"
                )
            )
            return
        }
        Haptics.tap()
        let optimistic = !viewModel.joinedCommunityUrls.contains(row.communityUrl)
        rowView.setJoined(optimistic)
        Task {
            do {
                let settled = try await viewModel.toggleJoin(row)
                rowView.setJoined(settled)
            } catch {
                rowView.setJoined(!optimistic)
                alertService.handle(error, for: .setSubscribed)
            }
        }
    }

    // MARK: Actions

    @objc
    private func healthCardTapped() {
        let vc = InstanceDetailViewController(
            record: record,
            showsActions: false,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func shareTapped() {
        guard let url = URL(string: "https://\(record.baseurl)") else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activity, animated: true)
    }

    // MARK: View model binding

    private func bindViewModel() {
        let viewModel = viewModel

        observationTasks.append(Task { @MainActor [weak self] in
            for await sidebar in ObservationStream.values(of: { viewModel.sidebar }) {
                if Task.isCancelled { break }
                guard let self else { break }
                guard let sidebar, !sidebar.isEmpty else { continue }
                if aboutServerView.isHidden {
                    aboutServerView.configure(sidebar: sidebar, imageService: imageService)
                    aboutServerView.isHidden = false
                }
            }
        })

        observationTasks.append(Task { @MainActor [weak self] in
            for await adminsState in ObservationStream.values(of: { viewModel.adminsState }) {
                if Task.isCancelled { break }
                guard let self else { break }
                adminsView.update(adminsState)
            }
        })

        observationTasks.append(Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: { viewModel.communities.count }) {
                if Task.isCancelled { break }
                guard let self else { break }
                renderCommunities()
            }
        })
    }

    // MARK: Helpers

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.secondaryGroupedBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        return card
    }

    private func pinToCard(_ subview: UIView, _ card: UIView, inset: CGFloat) {
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            subview.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
            subview.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
            subview.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset),
        ])
    }

    private func hairline(vertical: Bool) -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        if vertical {
            line.widthAnchor.constraint(equalToConstant: 0.5).isActive = true
        } else {
            line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        }
        return line
    }

    private func score100() -> Double? {
        guard record.score > 0 else { return nil }
        return min(100, max(0, record.score * 100))
    }
}
