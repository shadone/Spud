//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import SpudDataKit
import SpudUIKit
import UIKit

private let logger = Logger.app

/// Displays every draft, in-flight, and failed composition for the current
/// account, grouped into three sections: Failed (top), Sending, Drafts (bottom).
///
/// Each row offers a Retry swipe action (failed only) and a Discard swipe
/// action (all rows). Editing (reopening the composer) is deferred to a later
/// task: the existing per-target draft-restore flow lets users pick up a draft
/// by reopening the relevant composer; no list-level "Edit" navigation is
/// implemented here.
@MainActor
final class OutboundContentListViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase
    typealias Dependencies = OwnDependencies

    private let dependencies: OwnDependencies
    private let viewModel: OutboundContentListViewModel

    @ObservationIgnored
    private var sectionObservationTask: Task<Void, Never>?
    @ObservationIgnored
    private var loadedObservationTask: Task<Void, Never>?

    // MARK: - Table view types

    enum Section: Int {
        case failed
        case sending
        case draft

        var headerTitle: String {
            switch self {
            case .failed: NSLocalizedString("Failed", comment: "Drafts & Outbox section: failed items")
            case .sending: NSLocalizedString("Sending", comment: "Drafts & Outbox section: in-flight items")
            case .draft: NSLocalizedString("Drafts", comment: "Drafts & Outbox section: unsent drafts")
            }
        }
    }

    enum Item: Hashable {
        case record(clientToken: String)
    }

    // MARK: - Data source

    /// A `UITableViewDiffableDataSource` subclass that supplies section header
    /// titles, which the base class does not override from the delegate.
    private final class OutboundDataSource: UITableViewDiffableDataSource<Section, Item> {
        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            sectionIdentifier(for: section)?.headerTitle
        }
    }

    // MARK: - UI

    private var dataSource: OutboundDataSource!

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.delegate = self
        tableView.register(
            UITableViewCell.self,
            forCellReuseIdentifier: "OutboundCell"
        )
        return tableView
    }()

    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString("No drafts", comment: "Drafts & Outbox empty state")
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.isHidden = true
        return label
    }()

    // MARK: - Cached rows

    /// Flat lookup of every record indexed by clientToken, used for swipe actions.
    private var recordsByToken: [String: OutboundContentRecord] = [:]

    // MARK: - Init

    init(accountKeychainId: String, dependencies: Dependencies) {
        self.dependencies = dependencies
        viewModel = OutboundContentListViewModel(
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        sectionObservationTask?.cancel()
        loadedObservationTask?.cancel()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = NSLocalizedString(
            "Drafts & Outbox",
            comment: "Title of the Drafts & Outbox screen"
        )
        view.backgroundColor = Theme.groupedBackground

        setupTableView()
        startObservations()
    }

    // MARK: - Setup

    private func setupTableView() {
        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        dataSource = OutboundDataSource(
            tableView: tableView
        ) { [weak self] tableView, indexPath, item in
            guard let self else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: "OutboundCell", for: indexPath)
            if case let .record(clientToken) = item, let record = recordsByToken[clientToken] {
                configure(cell: cell, record: record)
            }
            return cell
        }
        dataSource.defaultRowAnimation = .fade
    }

    // MARK: - Observations

    private func startObservations() {
        sectionObservationTask = Task { @MainActor [weak self] in
            for await sections in ObservationStream.values(of: { [weak self] in self?.viewModel.sections ?? [] }) {
                guard let self else { break }
                if Task.isCancelled { break }
                apply(sections: sections)
            }
        }

        loadedObservationTask = Task { @MainActor [weak self] in
            for await isLoaded in ObservationStream.values(of: { [weak self] in self?.viewModel.isLoaded ?? false }) {
                guard let self else { break }
                if Task.isCancelled { break }
                updateEmptyState(isLoaded: isLoaded, sections: viewModel.sections)
            }
        }
    }

    // MARK: - Rendering

    private func apply(sections: [OutboundSection]) {
        // Rebuild the flat lookup.
        var newByToken: [String: OutboundContentRecord] = [:]
        for section in sections {
            for row in section.rows {
                newByToken[row.clientToken] = row
            }
        }
        recordsByToken = newByToken

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        for section in sections {
            let tableSection: Section
            switch section.kind {
            case .failed: tableSection = .failed
            case .sending: tableSection = .sending
            case .draft: tableSection = .draft
            }
            snapshot.appendSections([tableSection])
            snapshot.appendItems(section.rows.map { .record(clientToken: $0.clientToken) })
        }
        dataSource.apply(snapshot, animatingDifferences: true)
        updateEmptyState(isLoaded: viewModel.isLoaded, sections: sections)
    }

    private func updateEmptyState(isLoaded: Bool, sections: [OutboundSection]) {
        let isEmpty = isLoaded && sections.isEmpty
        emptyStateLabel.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    private func configure(cell: UITableViewCell, record: OutboundContentRecord) {
        let kind = OutboundKind(rawValue: record.kind) ?? .comment
        let status = OutboundStatus(rawValue: record.status) ?? .draft

        var config = cell.defaultContentConfiguration()

        // Target line: "Reply to a post" / "Post to a community" + optional title.
        switch kind {
        case .comment:
            config.text = NSLocalizedString(
                "Reply to a post",
                comment: "Drafts & Outbox row: target description for a comment"
            )
        case .post:
            if let title = record.title, !title.isEmpty {
                config.text = title
            } else {
                config.text = NSLocalizedString(
                    "Post to a community",
                    comment: "Drafts & Outbox row: target description for a post with no title"
                )
            }
        }

        // Body snippet.
        let snippet = record.body.isEmpty ? nil : record.body
        config.secondaryText = snippet

        // Accessory status label via image (SF symbol) + trailing secondary text.
        switch status {
        case .draft:
            config.image = UIImage(systemName: "pencil.circle")
            config.imageProperties.tintColor = .secondaryLabel
        case .queued, .sending:
            config.image = UIImage(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            config.imageProperties.tintColor = .secondaryLabel
        case .failed:
            config.image = UIImage(systemName: "exclamationmark.circle.fill")
            config.imageProperties.tintColor = .systemRed
        }

        cell.contentConfiguration = config
        cell.selectionStyle = .none
    }
}

// MARK: - UITableViewDelegate

extension OutboundContentListViewController: UITableViewDelegate {
    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard case let .record(clientToken) = dataSource.itemIdentifier(for: indexPath),
              let record = recordsByToken[clientToken]
        else { return nil }

        var actions: [UIContextualAction] = []

        let status = OutboundStatus(rawValue: record.status) ?? .draft

        // Retry only available for failed rows.
        if status == .failed {
            let retry = UIContextualAction(
                style: .normal,
                title: NSLocalizedString("Retry", comment: "Swipe action: retry a failed outbound item")
            ) { [weak self] _, _, completion in
                self?.viewModel.retry(clientToken: clientToken)
                completion(true)
            }
            retry.backgroundColor = .systemBlue
            retry.image = UIImage(systemName: "arrow.clockwise")
            actions.append(retry)
        }

        // Discard is always available.
        let discard = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("Discard", comment: "Swipe action: discard an outbound item")
        ) { [weak self] _, _, completion in
            self?.viewModel.discard(clientToken: clientToken)
            completion(true)
        }
        discard.image = UIImage(systemName: "trash")
        actions.append(discard)

        return UISwipeActionsConfiguration(actions: actions)
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard case let .record(clientToken) = dataSource.itemIdentifier(for: indexPath),
              let record = recordsByToken[clientToken]
        else { return nil }

        let status = OutboundStatus(rawValue: record.status) ?? .draft

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu(children: []) }
            var children: [UIMenuElement] = []

            if status == .failed {
                let retry = UIAction(
                    title: NSLocalizedString("Retry", comment: "Context menu: retry a failed outbound item"),
                    image: UIImage(systemName: "arrow.clockwise")
                ) { [weak self] _ in
                    self?.viewModel.retry(clientToken: clientToken)
                }
                children.append(retry)
            }

            let discard = UIAction(
                title: NSLocalizedString("Discard", comment: "Context menu: discard an outbound item"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.viewModel.discard(clientToken: clientToken)
            }
            children.append(discard)

            return UIMenu(children: children)
        }
    }
}
