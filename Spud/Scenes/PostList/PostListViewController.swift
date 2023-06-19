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
        HasImageService &
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

    var sortTypeBarButtonItem: UIBarButtonItem!
    var sortTypeActiveAction: UIAction!
    var sortTypeHotAction: UIAction!
    var sortTypeNewAction: UIAction!
    var sortTypeOldAction: UIAction!
    var sortTypeTopDayAction: UIAction!
    var sortTypeTopWeekAction: UIAction!
    var sortTypeTopMonthAction: UIAction!
    var sortTypeTopYearAction: UIAction!
    var sortTypeTopAllAction: UIAction!
    var sortTypeMostCommentsAction: UIAction!
    var sortTypeNewCommentsAction: UIAction!

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
        bindViewModel()
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

        sortTypeActiveAction = UIAction(title: "Active", image: nil) { [weak self] _ in
            self?.viewModel.inputs.didChangeSortType(.active)
        }
        sortTypeHotAction = UIAction(title: "Hot", image: nil) { [weak self] _ in
            self?.viewModel.inputs.didChangeSortType(.hot)
        }
        sortTypeNewAction = UIAction(title: "New", image: nil) { [weak self] _ in
            self?.viewModel.inputs.didChangeSortType(.new)
        }
        sortTypeOldAction = UIAction(title: "Old", image: nil) { [weak self] _ in
            self?.viewModel.inputs.didChangeSortType(.old)
        }
        sortTypeTopDayAction = UIAction(title: "Top Day", image: nil) { [weak self] _ in
            self?.viewModel.inputs.didChangeSortType(.topDay)
        }
        sortTypeTopWeekAction = UIAction(title: "Top Week", image: nil) { [weak self] _ in
            self?.viewModel.inputs.didChangeSortType(.topWeek)
        }
        sortTypeTopMonthAction = UIAction(title: "Top Month", image: nil) { [weak self] _ in
            self?.viewModel.inputs.didChangeSortType(.topMonth)
        }
        sortTypeTopYearAction = UIAction(title: "Top Year", image: nil) { [weak self] _ in
            self?.viewModel.inputs.didChangeSortType(.topYear)
        }
        sortTypeTopAllAction = UIAction(title: "Top All", image: nil) { [weak self] _ in
            self?.viewModel.inputs.didChangeSortType(.topAll)
        }
        sortTypeMostCommentsAction = UIAction(title: "Most Comments", image: nil) { [weak self] _ in
            self?.viewModel.inputs.didChangeSortType(.mostComments)
        }
        sortTypeNewCommentsAction = UIAction(title: "New Comments", image: nil) { [weak self] _ in
            self?.viewModel.inputs.didChangeSortType(.newComments)
        }

        sortTypeBarButtonItem = UIBarButtonItem(
            title: "Sort type",
            image: UIImage(systemName: "line.horizontal.3.decrease.circle"),
            menu: nil
        )
        navigationItem.rightBarButtonItem = sortTypeBarButtonItem
    }

    private func buildSortTypeMenu() {
        let sortTypeMenu = UIMenu(
            title: "",
            options: .singleSelection,
            children: [
                sortTypeActiveAction,
                sortTypeHotAction,
                sortTypeNewAction,
                sortTypeOldAction,
                sortTypeTopDayAction,
                sortTypeTopWeekAction,
                sortTypeTopMonthAction,
                sortTypeTopYearAction,
                sortTypeTopAllAction,
                sortTypeMostCommentsAction,
                sortTypeNewCommentsAction,
            ]
        )

        sortTypeBarButtonItem.menu = sortTypeMenu
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
                self?.updateSelectedSortTypeMenu()
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

    private func updateSelectedSortTypeMenu() {
        switch viewModel.outputs.feed.value.sortType {
        case .active:
            sortTypeActiveAction.state = .on
        case .hot:
            sortTypeHotAction.state = .on
        case .new:
            sortTypeNewAction.state = .on
        case .old:
            sortTypeOldAction.state = .on
        case .topDay:
            sortTypeTopDayAction.state = .on
        case .topWeek:
            sortTypeTopWeekAction.state = .on
        case .topMonth:
            sortTypeTopMonthAction.state = .on
        case .topYear:
            sortTypeTopYearAction.state = .on
        case .topAll:
            sortTypeTopAllAction.state = .on
        case .mostComments:
            sortTypeMostCommentsAction.state = .on
        case .newComments:
            sortTypeNewCommentsAction.state = .on
        }

        // it seems that setting the state on an action for an existing UIMenu doesn't
        // update the ui. The menu wasn't picking up a new state, it seems like the UIMenu
        // caches the state of the actions/menuitems.
        // Lets rebuild the whole menu.
        buildSortTypeMenu()
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

        viewModel.inputs.didPrepareFetchController(numberOfFetchedPosts: numberOfPosts)
    }

    private func postSelected(_ post: LemmyPost) {
        let postDetailVC = PostDetailViewController(post: post, dependencies: dependencies)
        navigationController?.pushViewController(postDetailVC, animated: true)
    }
}

// MARK: - FRC helpers

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
        let viewModel = PostListPostViewModel(
            post: post,
            imageService: dependencies.imageService
        )
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
            let viewModel = PostListPostViewModel(
                post: post,
                imageService: dependencies.imageService
            )
            cell.configure(with: viewModel)

        case .move:
            assertionFailure()

        @unknown default:
            assertionFailure()
        }
    }
}
