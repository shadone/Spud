//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

/// The "New message" recipient picker: a modal screen that searches Lemmy users
/// and starts a new direct-message thread with the chosen person.
///
/// A dedicated, single-purpose picker rather than a reuse of the full
/// `SearchViewController` (which is coupled to URL-parse / instance / multi-scope
/// search). It searches only the `.Users` type, debounced (~300ms, cancelling the
/// in-flight request on each new query) via ``RecipientPickerViewModel``, and
/// reuses `SearchUserResult` for decoding and `SearchUserCell` for the row.
///
/// Designed to be nav-wrapped and presented modally: it shows a "New Message"
/// title and a Cancel button. Tapping a result fires ``onRecipientSelected`` with
/// the chosen person's server id and display name; the caller dismisses the
/// picker and opens the thread.
final class RecipientPickerViewController: UIViewController {
    /// The only dependencies the picker needs: `HasAccountService` to reach the
    /// account's `LemmyService` for the user search, and `HasImageService` to
    /// load avatars in `SearchUserCell`.
    typealias Dependencies = HasAccountService & HasImageService

    /// Invoked when the user taps a result. Carries the chosen person's server
    /// id and display name — exactly what `DMThreadViewController` needs to open
    /// a new thread. The picker dismisses itself before this fires.
    var onRecipientSelected: ((Lemmy.PersonID, String) -> Void)?

    // MARK: Private

    private let imageService: ImageServiceType
    private let viewModel: RecipientPickerViewModel

    private var phaseObservationTask: Task<Void, Never>?
    private var resultsObservationTask: Task<Void, Never>?

    private enum Section: Hashable { case results }

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.keyboardDismissMode = .onDrag
        tableView.delegate = self
        tableView.register(SearchUserCell.self, forCellReuseIdentifier: SearchUserCell.reuseIdentifier)
        return tableView
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Section, SearchUserResult> = makeDataSource()

    private lazy var searchController: UISearchController = {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString(
            "Search for someone",
            comment: "Recipient picker search bar placeholder"
        )
        searchController.searchBar.delegate = self
        searchController.searchBar.autocapitalizationType = .none
        return searchController
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: Functions

    init(
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        imageService = dependencies.imageService
        let scope = dependencies.accountService.scope(forAccountKeychainId: accountKeychainId)
        viewModel = RecipientPickerViewModel(searchUsers: { query in
            let response = try await scope.lemmyService.search(
                query: query,
                type: .Users,
                sort: .TopAll,
                listingType: .All,
                page: 1
            )
            return response.persons.compactMap(SearchUserResult.init)
        })

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        phaseObservationTask?.cancel()
        resultsObservationTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.background
        navigationItem.title = NSLocalizedString(
            "New Message",
            comment: "Recipient picker navigation title"
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in self?.cancelTapped() }
        )
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        view.addSubview(tableView)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        startObservations()
        render()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Drop the keyboard straight into the search field — a recipient picker
        // exists to type a name, so make that the immediate, zero-tap action.
        if !searchController.isActive {
            searchController.searchBar.becomeFirstResponder()
        }
    }

    // MARK: Observation

    private func startObservations() {
        phaseObservationTask?.cancel()
        resultsObservationTask?.cancel()

        let viewModel = viewModel
        phaseObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: { viewModel.phase }) {
                if Task.isCancelled { break }
                self?.render()
            }
        }
        resultsObservationTask = Task { @MainActor [weak self] in
            for await _ in ObservationStream.values(of: { viewModel.results }) {
                if Task.isCancelled { break }
                self?.render()
            }
        }
    }

    // MARK: Rendering

    private func render() {
        switch viewModel.phase {
        case .initial:
            loadingIndicator.stopAnimating()
            applySnapshot([])
            updateContentUnavailable(.initial)
        case .loading:
            loadingIndicator.startAnimating()
            updateContentUnavailable(.none)
        case .loaded:
            loadingIndicator.stopAnimating()
            applySnapshot(viewModel.results)
            updateContentUnavailable(viewModel.results.isEmpty ? .noResults : .none)
        case .error:
            loadingIndicator.stopAnimating()
            applySnapshot([])
            updateContentUnavailable(.error)
        }
    }

    private func applySnapshot(_ items: [SearchUserResult]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, SearchUserResult>()
        snapshot.appendSections([.results])
        snapshot.appendItems(items, toSection: .results)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private enum ContentUnavailable {
        case none
        case initial
        case noResults
        case error
    }

    private func updateContentUnavailable(_ state: ContentUnavailable) {
        switch state {
        case .none:
            contentUnavailableConfiguration = nil
        case .initial:
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "person.crop.circle.badge.questionmark")
            config.text = NSLocalizedString(
                "Search for someone to message",
                comment: "Recipient picker initial empty-state title"
            )
            contentUnavailableConfiguration = config
        case .noResults:
            var config = UIContentUnavailableConfiguration.search()
            config.text = String(
                format: NSLocalizedString(
                    "No people found for \"%@\"",
                    comment: "Recipient picker no-results title, quotes the query"
                ),
                viewModel.lastSearchedQuery
            )
            contentUnavailableConfiguration = config
        case .error:
            var config = UIContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "exclamationmark.triangle")
            config.text = NSLocalizedString(
                "Search failed",
                comment: "Recipient picker error-state title"
            )
            config.secondaryText = NSLocalizedString(
                "Check your connection and try again.",
                comment: "Recipient picker error-state message"
            )
            contentUnavailableConfiguration = config
        }
    }

    // MARK: Data source

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, SearchUserResult> {
        UITableViewDiffableDataSource<Section, SearchUserResult>(
            tableView: tableView
        ) { [weak self] tableView, indexPath, result in
            guard let self else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SearchUserCell.reuseIdentifier,
                for: indexPath
            ) as! SearchUserCell
            cell.configure(with: result, imageService: imageService)
            // This picker is for selection, not navigation: show the selection
            // highlight and drop the disclosure chevron the shared cell carries
            // for the navigational Search screen.
            cell.selectionStyle = .default
            cell.accessoryType = .none
            return cell
        }
    }

    // MARK: Actions

    private func cancelTapped() {
        dismiss(animated: true)
    }
}

// MARK: - UISearchResultsUpdating

extension RecipientPickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.queryChanged(searchController.searchBar.text ?? "")
    }
}

// MARK: - UISearchBarDelegate

extension RecipientPickerViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_: UISearchBar) {
        viewModel.submit()
    }
}

// MARK: - UITableViewDelegate

extension RecipientPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let result = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.tap()
        // Dismiss first, then let the caller push the new thread onto the inbox
        // nav stack (the picker is a modal over that stack).
        let onRecipientSelected = onRecipientSelected
        dismiss(animated: true) {
            onRecipientSelected?(result.serverPersonId, result.name)
        }
    }
}
