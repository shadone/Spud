//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUIKit
import UIKit

/// The feed switcher. Lists the standard feeds (All / Local / Subscribed /
/// Saved) and a link into the Communities tab. It sits beneath the post list in
/// the Posts-tab navigation stack, so swiping in from the left edge (the system
/// back gesture) reveals it. Navigation only — no subscription management lives
/// here (that is the Communities tab's job), per the Scout navigation direction.
final class FeedSwitcherViewController: UIViewController {
    /// Invoked with the chosen feed type. The presenter switches the Posts feed
    /// and re-pushes the post list.
    var onSelectFeedType: ((FeedType) -> Void)?

    /// Invoked when the user taps "Browse all communities".
    var onBrowseAllCommunities: (() -> Void)?

    private enum FeedKind {
        case frontpage(Components.Schemas.ListingType)
        case saved
        case browseCommunities
    }

    private struct Row {
        let title: String
        let symbolName: String
        let kind: FeedKind
    }

    /// Reads the feed currently shown by the post list, so the matching row gets
    /// a checkmark. Evaluated each time the switcher appears (it is long-lived).
    private let currentFeedType: @MainActor () -> FeedType?

    /// Resolves the default sort applied to a freshly chosen feed. Evaluated at
    /// selection time so a changed preference is honoured.
    private let defaultSortType: @MainActor () -> Components.Schemas.SortType

    private let sections: [[Row]]

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.groupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        return tableView
    }()

    init(
        currentFeedType: @escaping @MainActor () -> FeedType?,
        defaultSortType: @escaping @MainActor () -> Components.Schemas.SortType
    ) {
        self.currentFeedType = currentFeedType
        self.defaultSortType = defaultSortType
        sections = [
            [
                Row(
                    title: NSLocalizedString("All", comment: "Feed switcher: all federated content"),
                    symbolName: "globe",
                    kind: .frontpage(.All)
                ),
                Row(
                    title: NSLocalizedString("Local", comment: "Feed switcher: this instance only"),
                    symbolName: "house",
                    kind: .frontpage(.Local)
                ),
                Row(
                    title: NSLocalizedString("Subscribed", comment: "Feed switcher: subscribed communities"),
                    symbolName: "star",
                    kind: .frontpage(.Subscribed)
                ),
                Row(
                    title: NSLocalizedString("Saved", comment: "Feed switcher: saved posts"),
                    symbolName: "bookmark",
                    kind: .saved
                ),
            ],
            [
                Row(
                    title: NSLocalizedString("Browse all communities", comment: "Feed switcher row opening the Communities tab"),
                    symbolName: "person.3",
                    kind: .browseCommunities
                ),
            ],
        ]
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.groupedBackground

        title = NSLocalizedString("Feeds", comment: "Feed switcher screen title")
        navigationItem.largeTitleDisplayMode = .never

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The active feed may have changed since the switcher was last shown;
        // refresh so the checkmark lands on the current feed.
        tableView.reloadData()
    }

    /// Whether a feeds row matches the currently displayed feed (so it gets a
    /// checkmark). Compared by kind, ignoring sort.
    private func isActive(_ row: Row) -> Bool {
        guard let active = currentFeedType() else { return false }
        switch (row.kind, active) {
        case let (.frontpage(lhs), .frontpage(rhs, _)):
            return lhs == rhs
        case (.saved, .saved):
            return true
        default:
            return false
        }
    }
}

extension FeedSwitcherViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? NSLocalizedString("Feeds", comment: "Feed switcher section header") : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let row = sections[indexPath.section][indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = row.title
        content.image = UIImage(systemName: row.symbolName)
        content.imageProperties.tintColor = view.tintColor
        cell.contentConfiguration = content
        cell.backgroundColor = Theme.secondaryGroupedBackground

        switch row.kind {
        case .browseCommunities:
            cell.accessoryType = .disclosureIndicator
        case .frontpage, .saved:
            cell.accessoryType = isActive(row) ? .checkmark : .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Haptics.tap()

        let row = sections[indexPath.section][indexPath.row]
        switch row.kind {
        case let .frontpage(listingType):
            onSelectFeedType?(.frontpage(listingType: listingType, sortType: defaultSortType()))
        case .saved:
            onSelectFeedType?(.saved(sortType: defaultSortType()))
        case .browseCommunities:
            onBrowseAllCommunities?()
        }
    }
}
