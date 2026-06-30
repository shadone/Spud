//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

/// Displays the account-holder's activity summary: an identity strip, six
/// stat tiles, a contribution heatmap, and three extra insight tiles.
///
/// Pushed from `ActivityViewController` via the "Summary" nav-bar button.
/// Layout uses a `UIScrollView` + vertical `UIStackView` of plain `UIView`
/// card subviews — no nested `UITableViewCell`.
@MainActor
final class SummaryViewController: UIViewController {
    // MARK: Dependencies

    typealias OwnDependencies = HasAppDatabase
    typealias Dependencies = OwnDependencies
    private let dependencies: OwnDependencies

    // MARK: Private

    private let viewModel: SummaryViewModel
    private var observationTask: Task<Void, Never>?

    // MARK: UI

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.alwaysBounceVertical = true
        return sv
    }()

    private lazy var contentStack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .vertical
        s.spacing = 12
        return s
    }()

    private let identityStripView: SummaryIdentityStripView = {
        let v = SummaryIdentityStripView()
        v.backgroundColor = Theme.secondaryGroupedBackground
        v.layer.cornerRadius = 16
        v.layer.masksToBounds = true
        return v
    }()

    private let statTilesView = SummaryStatTilesView()

    private lazy var heatmapCard: SummaryHeatmapCardView = {
        let v = SummaryHeatmapCardView()
        v.onMetricChanged = { [weak self] metric in
            self?.viewModel.selectMetric(metric)
        }
        return v
    }()

    private let extrasView = SummaryExtrasView()

    // MARK: Init

    init(
        accountId: Int64,
        personRowId: Int64?,
        asOf: Date = Date(),
        dependencies: Dependencies
    ) {
        self.dependencies = dependencies
        viewModel = SummaryViewModel(
            appDatabase: dependencies.appDatabase,
            accountId: accountId,
            personRowId: personRowId,
            asOf: asOf
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.groupedBackground
        title = NSLocalizedString("Summary", comment: "Summary screen title")

        setupLayout()
        applyInitialContent()
        startObservation()
        viewModel.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            viewModel.stop()
        }
    }

    // MARK: Private

    private func setupLayout() {
        // Wrap each card so margins are inherited from the card's own
        // layoutMarginsGuide; the stack just sequences them vertically.
        contentStack.addArrangedSubview(identityStripView)
        contentStack.addArrangedSubview(statTilesView)
        contentStack.addArrangedSubview(heatmapCard)
        contentStack.addArrangedSubview(extrasView)

        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)

        let contentGuide = scrollView.contentLayoutGuide
        let frameGuide = scrollView.frameLayoutGuide

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: contentGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor, constant: -16),

            // Width matches the scroll view frame so content doesn't scroll horizontally.
            contentStack.widthAnchor.constraint(
                equalTo: frameGuide.widthAnchor,
                constant: -32
            ),
        ])
    }

    private func applyInitialContent() {
        // Render heatmap + extras from synchronous initial data.
        heatmapCard.configure(series: viewModel.series)
        extrasView.configure(extras: viewModel.extras)
    }

    private func startObservation() {
        observationTask?.cancel()
        let viewModel = viewModel
        observationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: {
                (viewModel.stats, viewModel.series, viewModel.extras, viewModel.selectedMetric)
            }) {
                if Task.isCancelled { break }
                self?.applyViewModel()
            }
        }
    }

    private func applyViewModel() {
        if let stats = viewModel.stats {
            identityStripView.configure(stats: stats)
            statTilesView.configure(stats: stats)
        }
        heatmapCard.configure(series: viewModel.series)
        extrasView.configure(extras: viewModel.extras)
    }
}
