//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUIKit
import UIKit

/// Read-only quick-switch drawer. Lists the standard feeds (All / Local /
/// Subscribed / Saved) and a link into the Communities tab, sliding in from the
/// leading edge when the user taps the feed title. Navigation only — no
/// subscription management lives here (that is the Communities tab's job), per
/// the Scout navigation direction.
final class QuickSwitchDrawerViewController: UIViewController {
    /// Invoked with the chosen feed type. The presenter switches the Posts feed.
    var onSelectFeedType: ((FeedType) -> Void)?

    /// Invoked when the user taps "Browse all communities".
    var onBrowseAllCommunities: (() -> Void)?

    private struct Row {
        let title: String
        let symbolName: String
        /// nil marks the "Browse all communities" row.
        let feedType: FeedType?
    }

    private let activeFeedType: FeedType
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

    init(activeFeedType: FeedType, defaultSortType: Components.Schemas.SortType) {
        self.activeFeedType = activeFeedType
        sections = [
            [
                Row(
                    title: NSLocalizedString("All", comment: "Quick-switch feed: all federated content"),
                    symbolName: "globe",
                    feedType: .frontpage(listingType: .All, sortType: defaultSortType)
                ),
                Row(
                    title: NSLocalizedString("Local", comment: "Quick-switch feed: this instance only"),
                    symbolName: "house",
                    feedType: .frontpage(listingType: .Local, sortType: defaultSortType)
                ),
                Row(
                    title: NSLocalizedString("Subscribed", comment: "Quick-switch feed: subscribed communities"),
                    symbolName: "star",
                    feedType: .frontpage(listingType: .Subscribed, sortType: defaultSortType)
                ),
                Row(
                    title: NSLocalizedString("Saved", comment: "Quick-switch feed: saved posts"),
                    symbolName: "bookmark",
                    feedType: .saved(sortType: defaultSortType)
                ),
            ],
            [
                Row(
                    title: NSLocalizedString("Browse all communities", comment: "Quick-switch row opening the Communities tab"),
                    symbolName: "person.3",
                    feedType: nil
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

        title = NSLocalizedString("Switch feed", comment: "Quick-switch drawer title")
        navigationItem.largeTitleDisplayMode = .never

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Whether a feeds row matches the currently displayed feed (so it gets a
    /// checkmark). Compared by kind, ignoring sort, since the drawer always
    /// offers feeds at the default sort.
    private func isActive(_ row: Row) -> Bool {
        guard let rowFeed = row.feedType else { return false }
        switch (rowFeed, activeFeedType) {
        case let (.frontpage(lhs, _), .frontpage(rhs, _)):
            return lhs == rhs
        case (.saved, .saved):
            return true
        default:
            return false
        }
    }
}

extension QuickSwitchDrawerViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? NSLocalizedString("Feeds", comment: "Quick-switch drawer section header") : nil
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

        if row.feedType == nil {
            cell.accessoryType = .disclosureIndicator
        } else {
            cell.accessoryType = isActive(row) ? .checkmark : .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Haptics.tap()

        let row = sections[indexPath.section][indexPath.row]
        // Capture the callbacks strongly so they fire even after this drawer is
        // torn down by the dismissal.
        let onSelectFeedType = onSelectFeedType
        let onBrowseAllCommunities = onBrowseAllCommunities

        dismiss(animated: true) {
            if let feedType = row.feedType {
                onSelectFeedType?(feedType)
            } else {
                onBrowseAllCommunities?()
            }
        }
    }
}
