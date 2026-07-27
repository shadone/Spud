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
        case frontpage(Lemmy.ListingType)
        case saved
        case downloaded
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
    private let defaultSortType: @MainActor () -> Lemmy.SortType

    /// Count of posts saved for offline reading. The "Downloaded" row is shown
    /// only when this is > 0. Re-evaluated in `viewWillAppear` (the switcher is
    /// long-lived), so a fresh download makes the row appear — and clearing the
    /// downloads makes it disappear — without rebuilding the controller.
    private let downloadedCount: @MainActor () -> Int

    /// The rendered sections. Rebuilt in `viewWillAppear` from the live
    /// `downloadedCount`, so the Downloaded row's presence tracks the count.
    private var sections: [[Row]] = []

    /// Distinguishes this instance's two presentation contexts: the transient
    /// popover (regular width, presented from the post-list navbar title by
    /// `MainWindowSplitViewController.onPresentFeedSwitcher`) versus the
    /// long-lived instance pushed beneath the post list in compact width. The
    /// caller sets `modalPresentationStyle = .popover` right after constructing
    /// the popover instance and before `present(_:animated:)`, which is always
    /// before `viewDidLoad` runs (that only happens once the presentation
    /// transition actually loads the view) -- so this reads correctly by the
    /// time `viewDidLoad`/the lazy `tableView` consult it. The pushed instance
    /// never touches `modalPresentationStyle`, so it stays at the
    /// `UIViewController` default (never `.popover`).
    private var isPopover: Bool {
        modalPresentationStyle == .popover
    }

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        // `.insetGrouped` tables carry an opaque `.systemGroupedBackground` fill
        // of their own even when never explicitly assigned, so the popover usage
        // needs an explicit `.clear` override (not just skipping the assignment)
        // to let the popover's own glass material show through. The pushed
        // (compact) usage is a real screen and keeps the opaque fill.
        tableView.backgroundColor = isPopover ? .clear : .systemGroupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        return tableView
    }()

    init(
        currentFeedType: @escaping @MainActor () -> FeedType?,
        defaultSortType: @escaping @MainActor () -> Lemmy.SortType,
        downloadedCount: @escaping @MainActor () -> Int
    ) {
        self.currentFeedType = currentFeedType
        self.defaultSortType = defaultSortType
        self.downloadedCount = downloadedCount
        super.init(nibName: nil, bundle: nil)
        sections = makeSections()
    }

    /// Builds the switcher rows. The Downloaded row is appended after Saved only
    /// when there are downloaded posts to read (`downloadedCount() > 0`), so an
    /// empty state never advertises an empty feed.
    private func makeSections() -> [[Row]] {
        var feeds: [Row] = [
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
        ]
        if downloadedCount() > 0 {
            feeds.append(
                Row(
                    title: NSLocalizedString("Downloaded", comment: "Feed switcher: posts saved for offline reading"),
                    symbolName: "arrow.down.circle",
                    kind: .downloaded
                )
            )
        }
        return [
            feeds,
            [
                Row(
                    title: NSLocalizedString("Browse all communities", comment: "Feed switcher row opening the Communities tab"),
                    symbolName: "person.3",
                    kind: .browseCommunities
                ),
            ],
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Only fill an opaque background for the compact, beneath-the-list
        // usage -- a real pushed screen that needs one. The popover usage
        // (regular width, presented from the post-list navbar title) is a
        // floating panel; leave its background transparent so the system's own
        // popover glass material shows through instead of a flat, hand-picked
        // color underneath it.
        if !isPopover {
            view.backgroundColor = .systemGroupedBackground
        }

        title = NSLocalizedString("Feeds", comment: "Feed switcher label")
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
        // Rebuild the rows so the Downloaded row appears/disappears with the live
        // download count, and refresh so the checkmark lands on the current feed
        // (both may have changed since the switcher was last shown).
        sections = makeSections()
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
        case (.downloaded, .downloaded):
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
        section == 0 ? NSLocalizedString("Feeds", comment: "Feed switcher label") : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let row = sections[indexPath.section][indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = row.title
        content.image = UIImage(systemName: row.symbolName)
        content.imageProperties.tintColor = view.tintColor
        cell.contentConfiguration = content
        // Cells are opaque by default (even after the view/table clear above),
        // so the popover usage needs the same explicit `.clear` override --
        // otherwise every row paints a flat `.secondarySystemGroupedBackground`
        // pill on top of the popover's own glass material, defeating it exactly
        // where the user actually looks (inside the rows). The pushed (compact)
        // usage is a real screen and keeps the opaque fill.
        cell.backgroundColor = isPopover ? .clear : .secondarySystemGroupedBackground

        switch row.kind {
        case .browseCommunities:
            cell.accessoryType = .disclosureIndicator
        case .frontpage, .saved, .downloaded:
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
        case .downloaded:
            onSelectFeedType?(.downloaded(sortType: defaultSortType()))
        case .browseCommunities:
            onBrowseAllCommunities?()
        }
    }
}
