//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import os.log
import SafariServices
import SpudDataKit
import UIKit

private let logger = Logger(.app)

class PostDetailViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasAppService &
        HasAppearanceService &
        HasDataStore
    typealias NestedDependencies =
        PostDetailViewModel.Dependencies &
        PostDetailHeaderViewModel.Dependencies &
        PostDetailCommentViewModel.Dependencies &
        PersonOrLoadingViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var dataStore: DataStoreType { dependencies.own.dataStore }
    var appearanceService: AppearanceServiceType { dependencies.own.appearanceService }
    var appService: AppServiceType { dependencies.own.appService }
    var accountService: AccountServiceType { dependencies.own.accountService }
    var alertService: AlertServiceType { dependencies.own.alertService }

    // MARK: - Public

    var postInfo: LemmyPostInfo {
        viewModel.outputs.postInfo
    }

    func setPostInfo(_ postInfo: LemmyPostInfo) {
        disposables.removeAll()

        viewModel = PostDetailViewModel(
            postInfo: postInfo,
            dependencies: dependencies.nested
        )

        bindViewModel()
        setupFRC()

//        tableView.reloadData()
//        tableView.contentOffset = .zero

        execFRC()
    }

    // MARK: UI Properties

    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension

        tableView.delegate = self
        tableView.dataSource = self

        tableView.refreshControl = refreshControl

        tableView.register(PostDetailHeaderCell.self, forCellReuseIdentifier: PostDetailHeaderCell.reuseIdentifier)
        tableView.register(PostDetailCommentCell.self, forCellReuseIdentifier: PostDetailCommentCell.reuseIdentifier)

        return tableView
    }()

    lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(reloadData), for: .valueChanged)
        return refreshControl
    }()

    // MARK: - Private

    private var viewModel: PostDetailViewModelType
    private var disposables = Set<AnyCancellable>()

    private var commentsFRC: NSFetchedResultsController<LemmyCommentElement>?

    /// Tracks if viewWillAppear has been called before.
    private var isFirstAppearance: Bool = true

    // MARK: Functions

    init(postInfo: LemmyPostInfo, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        viewModel = PostDetailViewModel(
            postInfo: postInfo,
            dependencies: dependencies
        )

        super.init(nibName: nil, bundle: nil)

        setup()
        setupFRC()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        view.backgroundColor = .systemBackground

        let openInBrowser = UIBarButtonItem(
            image: UIImage(systemName: "safari")!,
            style: .plain,
            target: self,
            action: #selector(openInBrowser)
        )
        navigationItem.rightBarButtonItem = openInBrowser

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if isFirstAppearance {
            execFRC()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if isFirstAppearance {
            accountService
                .lemmyService(for: postInfo.post.account)
                .markAsRead(postId: postInfo.post.objectID)
                .sink(
                    receiveCompletion: alertService.errorHandler(for: .markAsRead),
                    receiveValue: { _ in }
                )
                .store(in: &disposables)
        }

        isFirstAppearance = false
    }

    private func setupFRC() {
        // reset the old FRC in case we are reusing the same VC for a new post.
        commentsFRC?.delegate = nil

        let postObjectId = viewModel.outputs.postInfo.post.objectID
        let sortTypeRawValue = viewModel.outputs.commentSortType.value.rawValue

        let request = LemmyCommentElement.fetchRequest() as NSFetchRequest<LemmyCommentElement>
        request.predicate = NSPredicate(
            format: "post == %@ && sortTypeRawValue == %@",
            postObjectId,
            sortTypeRawValue
        )
        request.fetchBatchSize = 100
        request.relationshipKeyPathsForPrefetching = ["comment"]
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LemmyCommentElement.index, ascending: true),
        ]

        commentsFRC = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: dataStore.mainContext,
            sectionNameKeyPath: nil, cacheName: nil
        )
        commentsFRC?.delegate = self
    }

    private func execFRC() {
        do {
            try commentsFRC?.performFetch()
        } catch {
            logger.error("Failed to fetch comments: \(String(describing: error), privacy: .public)")
        }

        viewModel.inputs.didPrepareFetchController(numberOfFetchedComments: numberOfComments)
    }

    private func bindViewModel() { }

    @objc
    private func reloadData() {
        accountService
            .lemmyService(for: postInfo.post.account)
            .fetchComments(
                postId: postInfo.post.objectID,
                sortType: viewModel.outputs.commentSortType.value
            )
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.refreshControl.endRefreshing()
                    self?.alertService.errorHandler(for: .fetchComments)(completion)
                },
                receiveValue: { _ in }
            )
            .store(in: &disposables)
    }

    @objc
    private func openInBrowser() {
        Task {
            await appService.openInBrowser(post: postInfo.post, on: self)
        }
    }

    private func linkTapped(_ url: URL) {
        switch url.spud {
        case let .person(personId, instance):
            let vc = PersonOrLoadingViewController(
                personId: personId,
                instance: instance,
                account: postInfo.post.account,
                dependencies: dependencies.nested
            )
            navigationController?.pushViewController(vc, animated: true)

        case .post:
            // TODO: push a new post detail
            assertionFailure("unimplemented")

        case .none:
            Task {
                await appService.open(url: url, on: self)
            }
        }
    }

    private func linkTappedFromPreview(_ safariVC: SFSafariViewController) {
        present(safariVC, animated: true)
    }

    private func vote(_ commentElement: LemmyCommentElement, _ action: VoteStatus.Action) {
        guard let comment = commentElement.comment else {
            assertionFailure("Vote on more element?")
            return
        }

        accountService
            .lemmyService(for: postInfo.post.account)
            .vote(commentId: comment.objectID, vote: action)
            .sink(
                receiveCompletion: alertService.errorHandler(for: .vote),
                receiveValue: { _ in }
            )
            .store(in: &disposables)

        // Trigger haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func vote(commentAtIndex index: Int, _ action: VoteStatus.Action) {
        let commentElement = commentElement(at: index)
        vote(commentElement, action)
    }
}

// MARK: - FRC helpers

extension PostDetailViewController {
    var numberOfComments: Int {
        commentsFRC?.sections?[0].numberOfObjects ?? 0
    }

    func commentElement(at index: Int) -> LemmyCommentElement {
        guard
            let commentElement = commentsFRC?.sections?[0].objects?[index] as? LemmyCommentElement
        else {
            fatalError()
        }
        return commentElement
    }
}

// MARK: - UITableView Delegate

extension PostDetailViewController: UITableViewDelegate {
    // MARK: Context Menu

    func tableView(
        _ tableView: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath else { fatalError() }
        guard let cell = tableView.cellForRow(at: indexPath) else { return nil }
        guard let cell = cell as? PostDetailCommentCell else { fatalError() }

        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bounds, cornerRadius: 12)

        return UITargetedPreview(view: cell, parameters: parameters)
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.section == 1 else { return nil }

        let generalAppearance = appearanceService.general
        return UIContextMenuConfiguration(
            identifier: indexPath as NSCopying,
            previewProvider: nil,
            actionProvider: { _ in
                let upvoteAction = UIAction(
                    title: NSLocalizedString("Upvote", comment: ""),
                    image: generalAppearance.upvoteIcon
                ) { [weak self] _ in
                    self?.vote(commentAtIndex: indexPath.row, .upvote)
                }

                let downvoteAction = UIAction(
                    title: NSLocalizedString("Downvote", comment: ""),
                    image: generalAppearance.downvoteIcon
                ) { [weak self] _ in
                    self?.vote(commentAtIndex: indexPath.row, .downvote)
                }

                return UIMenu(title: "", children: [
                    upvoteAction,
                    downvoteAction,
                ])
            }
        )
    }
}

// MARK: - UITableView DataSource

extension PostDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            // Section 0: header
            return 1
        } else if section == 1 {
            // Section 1: comments
            return numberOfComments
        } else {
            fatalError()
        }
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if indexPath.section == 0 {
            // Section 0: header
            let cell = tableView.dequeueReusableCell(
                withIdentifier: PostDetailHeaderCell.reuseIdentifier,
                for: indexPath
            ) as! PostDetailHeaderCell

            cell.tableView = tableView
            cell.appService = appService

            cell.isBeingConfigured = true
            cell.configure(with: viewModel.outputs.headerViewModel)
            cell.linkTapped = { [weak self] url in
                self?.linkTapped(url)
            }
            cell.linkTappedFromPreview = { [weak self] safariVC in
                self?.linkTappedFromPreview(safariVC)
            }
            cell.isBeingConfigured = false

            return cell
        } else if indexPath.section == 1 {
            // Section 1: comments
            let cell = tableView.dequeueReusableCell(
                withIdentifier: PostDetailCommentCell.reuseIdentifier,
                for: indexPath
            ) as! PostDetailCommentCell

            let commentElement = commentElement(at: indexPath.row)
            let viewModel = PostDetailCommentViewModel(
                comment: commentElement,
                dependencies: dependencies.nested
            )
            cell.configure(with: viewModel)

            cell.linkTapped = { [weak self] url in
                self?.linkTapped(url)
            }

            let generalAppearance = appearanceService.general
            cell.swipeActionConfiguration = .init(
                leadingPrimaryAction: .init(
                    image: generalAppearance.upvoteIcon,
                    backgroundColor: generalAppearance.upvoteSwipeActionBackgroundColor
                ),
                leadingSecondaryAction: .init(
                    image: generalAppearance.downvoteIcon,
                    backgroundColor: generalAppearance.downvoteSwipeActionBackgroundColor
                ),
                trailingPrimaryAction: .init(
                    // TODO: make reply action
                    image: UIImage(systemName: "arrowshape.turn.up.backward")!,
                    backgroundColor: UIColor.blue
                ),
                trailingSecondaryAction: .init(
                    // TODO: make save comment action
                    image: UIImage(systemName: "bookmark")!,
                    backgroundColor: UIColor.green
                )
            )

            cell.swipeActionTriggered = { [weak self] action in
                switch action {
                case .leadingPrimary:
                    self?.vote(commentElement, .upvote)

                case .leadingSecondary:
                    self?.vote(commentElement, .downvote)

                case .trailingPrimary, .trailingSecondary:
                    // TODO: will be reply and save actions
                    break
                }
            }

            return cell
        } else {
            fatalError()
        }
    }
}

// MARK: - Core Data

extension PostDetailViewController: NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>
    ) {
        tableView.beginUpdates()
    }

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
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
            guard let newIndexPath else { fatalError() }
            let adjustedIndexPath = IndexPath(row: newIndexPath.row, section: 1)
            tableView.insertRows(at: [adjustedIndexPath], with: .fade)

        case .delete:
            guard let indexPath else { fatalError() }
            let adjustedIndexPath = IndexPath(row: indexPath.row, section: 1)
            tableView.deleteRows(at: [adjustedIndexPath], with: .fade)

        case .update:
            break

        case .move:
            assertionFailure()

        @unknown default:
            assertionFailure()
        }
    }
}
