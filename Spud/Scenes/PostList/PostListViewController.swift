//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import UIKit
import LemmyKit
import os.log

class PostListViewController: UIViewController {
    typealias Dependencies =
        HasAccountService &
        HasDataStore &
        PostDetailViewController.Dependencies
    let dependencies: Dependencies

    // MARK: Public

    var viewModelSubject: CurrentValueSubject<PostListViewModelType, Never>
    var viewModel: PostListViewModelType {
        viewModelSubject.value
    }

    // MARK: UI Properties

    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension

        tableView.delegate = self
        tableView.dataSource = self

        tableView.register(PostListPostCell.self, forCellReuseIdentifier: PostListPostCell.reuseIdentifier)

        return tableView
    }()

    // MARK: Private

    var disposables = Set<AnyCancellable>()

    var postsResults: NSFetchedResultsController<LemmyPageElement>?

    var isLoadingIndicatorHidden = true

    // MARK: Functions

    init(feed: LemmyFeed, dependencies: Dependencies) {
        self.dependencies = dependencies

        let viewModel = PostListViewModel(
            feed: feed,
            accountService: dependencies.accountService
        )
        viewModelSubject = .init(viewModel)

        super.init(nibName: nil, bundle: nil)

        setup()
    }

    private func setup() {
        view.backgroundColor = .white

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func bindViewModel() {
        viewModel.outputs.selectedPost
            .ignoreNil()
            .sink { [weak self] post in
                self?.postSelected(post)
            }
            .store(in: &disposables)

        viewModel.outputs.feed
            .sink { [weak self] _ in
                self?.feedChanged()
            }
            .store(in: &disposables)

        viewModel.outputs.isFetchingNextPage
            .removeDuplicates()
            .sink { [weak self] isFetchingNextPage in
                self?.isLoadingIndicatorHidden = !isFetchingNextPage
            }
            .store(in: &disposables)

        viewModel.outputs.navigationTitle
            .wrapInOptional()
            .assign(to: \.title, on: navigationItem)
            .store(in: &disposables)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        bindViewModel()
    }

    func feedChanged() {
        let request = LemmyPageElement.fetchRequest() as NSFetchRequest<LemmyPageElement>
        request.predicate = NSPredicate(
            format: "page.feed.id == %@",
            viewModel.outputs.feed.value.id
        )

        let pageIndex = NSSortDescriptor(keyPath: \LemmyPageElement.page.index, ascending: true)
        let postInPageIndex = NSSortDescriptor(keyPath: \LemmyPageElement.index, ascending: true)
        request.sortDescriptors = [
            pageIndex,
            postInPageIndex,
        ]

        postsResults = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: dependencies.dataStore.mainContext,
            sectionNameKeyPath: nil, cacheName: nil
        )
        postsResults?.delegate = self

        do {
            try postsResults?.performFetch()
        } catch {
            os_log("Failed to fetch: %{public}@",
                   log: .app, type: .error,
                   String(describing: error))
        }

        viewModel.inputs.didSelectPost(nil)
        viewModel.inputs.didChangeSelectedPostIndex(nil)

        isLoadingIndicatorHidden = numberOfPosts > 0

        tableView.reloadData()

        if numberOfPosts == 0 {
            viewModel.inputs.didPrepareFetchController()
        }
    }

    private func postSelected(_ post: LemmyPost) {
        let postDetailVC = PostDetailViewController(post: post, dependencies: dependencies)
        navigationController?.pushViewController(postDetailVC, animated: true)
    }
}

// MARK: - Post helpers

extension PostListViewController {
    var numberOfPosts: Int {
        postsResults?.sections?[0].numberOfObjects ?? 0
    }

    func post(at index: Int) -> LemmyPost {
        guard
            let pageElement = postsResults?.sections?[0].objects?[index] as? LemmyPageElement
        else {
            fatalError()
        }
        return pageElement.post
    }
}

// MARK: - UITableView Delegate

extension PostListViewController: UITableViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let position = scrollView.contentOffset.y + scrollView.bounds.height
        let totalHeight = scrollView.contentSize.height
        guard totalHeight > 0 else { return }
        let verticalFraction = position / totalHeight
        if verticalFraction > 0.9 {
            viewModel.inputs.didScrollToBottom()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let post = post(at: indexPath.row)
        viewModel.inputs.didSelectPost(post)
    }
}

// MARK: - UITableView DataSource

extension PostListViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            // Section 0: posts
            return numberOfPosts
        } else if section == 1 {
            // Section 1: loading indicator
            return isLoadingIndicatorHidden ? 0 : 1
        } else {
            fatalError()
        }
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: PostListPostCell.reuseIdentifier,
            for: indexPath
        ) as! PostListPostCell

        let post = post(at: indexPath.row)
        let viewModel = PostListPostViewModel(post: post)
        cell.configure(with: viewModel)

        return cell
    }
}

// MARK: - Core Data

extension PostListViewController: NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>
    ) {
        tableView.beginUpdates()
    }

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        isLoadingIndicatorHidden = true
        tableView.endUpdates()
//        viewModel.inputs.didChangeNumberOfPosts(inserted: tableView.numberOfRows)
    }

    func controller(
        _: NSFetchedResultsController<NSFetchRequestResult>,
        didChange _: Any,
        at indexPath: IndexPath?,
        for type: NSFetchedResultsChangeType,
        newIndexPath: IndexPath?
    ) {
        switch type {
        case .insert:
            guard let newIndexPath = newIndexPath else { fatalError() }
            tableView.insertRows(at: [newIndexPath], with: .fade)

        case .delete:
            guard let indexPath = indexPath else { fatalError() }
            tableView.deleteRows(at: [indexPath], with: .fade)

        case .update:
            guard let indexPath = indexPath else { fatalError() }
            guard let cell = tableView.cellForRow(at: indexPath) else { return }
            guard let cell = cell as? PostListPostCell else { fatalError() }

            let post = post(at: indexPath.row)
            let viewModel = PostListPostViewModel(post: post)
            cell.configure(with: viewModel)

        case .move:
            assertionFailure()

        @unknown default:
            assertionFailure()
        }
    }
}
