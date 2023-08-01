//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import UIKit
import os.log

private let logger = Logger(.app)

class PostDetailViewController: UIViewController {
    typealias Dependencies =
        HasDataStore &
        HasAppearanceService &
        HasAppService &
        PostDetailViewModel.Dependencies &
        PostDetailHeaderViewModel.Dependencies &
        PostDetailCommentViewModel.Dependencies
    private let dependencies: Dependencies

    // MARK: - Public

    var post: LemmyPost {
        viewModel.outputs.post
    }

    func setPost(_ post: LemmyPost) {
        disposables.removeAll()
        viewModel = PostDetailViewModel(
            post: post,
            dependencies: dependencies
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

        tableView.dataSource = self

        tableView.register(PostDetailHeaderCell.self, forCellReuseIdentifier: PostDetailHeaderCell.reuseIdentifier)
        tableView.register(PostDetailCommentCell.self, forCellReuseIdentifier: PostDetailCommentCell.reuseIdentifier)

        return tableView
    }()

    // MARK: - Private

    private var viewModel: PostDetailViewModelType
    private var disposables = Set<AnyCancellable>()

    private var commentsFRC: NSFetchedResultsController<LemmyCommentElement>?

    // MARK: Functions

    init(post: LemmyPost, dependencies: Dependencies) {
        self.dependencies = dependencies

        viewModel = PostDetailViewModel(
            post: post,
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
        view.backgroundColor = .white

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

        execFRC()
    }

    private func setupFRC() {
        // reset the old FRC in case we are reusing the same VC for a new post.
        commentsFRC?.delegate = nil

        let postObjectId = viewModel.outputs.post.objectID
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
            managedObjectContext: dependencies.dataStore.mainContext,
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

    private func bindViewModel() {
    }

    @objc private func openInBrowser() {
        dependencies.appService.openInBrowser(post: post, on: self)
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

            cell.isBeingConfigured = true
            cell.configure(with: viewModel.outputs.headerViewModel)
            cell.linkTapped = { [weak self] url in
                self?.linkTapped(url)
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
                dependencies: dependencies
            )
            cell.configure(with: viewModel)
            cell.linkTapped = { [weak self] url in
                self?.linkTapped(url)
            }

            return cell
        } else {
            fatalError()
        }
    }

    private func linkTapped(_ url: URL) {
        switch url.spud {
        case let .person(personId, instance):
            let context = dependencies.dataStore.mainContext
            let request = LemmyPerson.fetchRequest(personId: personId, instanceUrl: instance)
            let results = try! context.fetch(request)
            let person = results.first!
            let vc = PersonOrLoadingViewController(
                person: person,
                account: post.account,
                dependencies: AppDelegate.shared.dependencies
            )
            navigationController?.pushViewController(vc, animated: true)

        case .none:
            dependencies.appService.open(url: url, on: self)
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
