//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import SpudDataKit
import SpudUIKit
import UIKit

private let logger = Logger.app

/// A search-driven community picker presented from the new-post composer. The
/// user types a query and taps a result; the selection is reported back via
/// `onSelect`. Reuses `LemmyService.search` with `.Communities`.
final class CommunityPickerViewController: UITableViewController {
    typealias Dependencies =
        HasAccountService &
        HasAlertService &
        HasPreferencesService
    private let dependencies: Dependencies

    private let accountKeychainId: String

    /// Called when the user picks a community. The presenter dismisses.
    var onSelect: ((NewPostCommunity) -> Void)?

    private var results: [NewPostCommunity] = []
    private var searchTask: Task<Void, Never>?

    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchBar.placeholder = NSLocalizedString(
            "Search communities",
            comment: "Placeholder in the new-post community search bar"
        )
        controller.searchResultsUpdater = self
        return controller
    }()

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    init(accountKeychainId: String, dependencies: Dependencies) {
        self.accountKeychainId = accountKeychainId
        self.dependencies = dependencies
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        searchTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = NSLocalizedString("Community", comment: "Title of the new-post community picker screen")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchController.searchBar.becomeFirstResponder()
    }

    @objc
    private func cancelTapped() {
        dismiss(animated: true)
    }

    private func runSearch(query: String) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            tableView.reloadData()
            return
        }

        let accountKeychainId = accountKeychainId
        searchTask = Task { [weak self] in
            guard let self else { return }
            // Small debounce so we don't fire a request per keystroke.
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }

            let service = dependencies.accountService.scope(forAccountKeychainId: accountKeychainId).lemmyService
            do {
                let response = try await service.search(
                    query: trimmed,
                    type: .Communities,
                    sort: .TopAll,
                    listingType: .All,
                    page: 1
                )
                if Task.isCancelled { return }
                let showNsfw = dependencies.preferencesService.showNsfw
                results = response.communities
                    .filter { showNsfw || !$0.community.nsfw }
                    .map { view in
                        NewPostCommunity(
                            id: Lemmy.CommunityID(view.community.id),
                            qualifiedName: Self.qualifiedName(for: view.community),
                            title: view.community.title ?? view.community.name
                        )
                    }
                tableView.reloadData()
            } catch {
                if Task.isCancelled { return }
                alertService.handle(error, for: .search)
            }
        }
    }

    /// Builds `name@instance` from a community's actor id (falling back to the
    /// bare name when the host can't be parsed).
    private static func qualifiedName(for community: Lemmy.Community) -> String {
        guard
            let url = URL(string: community.apId),
            let host = url.host
        else {
            return community.name
        }
        return "\(community.name)@\(host)"
    }

    // MARK: UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let community = results[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = community.title
        content.secondaryText = community.qualifiedName
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Haptics.tap()
        let community = results[indexPath.row]
        onSelect?(community)
        dismiss(animated: true)
    }
}

// MARK: - UISearchResultsUpdating

extension CommunityPickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        runSearch(query: searchController.searchBar.text ?? "")
    }
}
