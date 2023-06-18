//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import SafariServices
import UIKit
import os.log

class PostDetailViewController: UIViewController {
    typealias Dependencies =
        HasDataStore &
        HasAccountService
    let dependencies: Dependencies

    // MARK: - Public

    var post: LemmyPost {
        viewModel.outputs.post
    }

    // MARK: UI Properties

    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension

        tableView.dataSource = self

        tableView.register(PostDetailHeaderCell.self, forCellReuseIdentifier: PostDetailHeaderCell.reuseIdentifier)

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
            accountService: dependencies.accountService
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
            os_log("Failed to fetch comments: %{public}@",
                   log: .app, type: .error,
                   String(describing: error))
        }

        viewModel.inputs.didPrepareFetchController(numberOfFetchedComments: numberOfComments)
    }

    private func bindViewModel() {
    }

    @objc private func openInBrowser() {
        let safariVC = SFSafariViewController(url: post.localLemmyUiUrl)
        present(safariVC, animated: true)
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
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            // Section 0: header
            return 1
        } else if section == 1 {
            // Section 1: comments
            return 0
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

            let viewModel = PostDetailHeaderViewModel(post: post)
            cell.configure(with: viewModel)

            return cell
        } else if indexPath.section == 1 {
            // Section 1: comments
            fatalError()
        } else {
            fatalError()
        }
    }
}

// MARK: - Core Data

extension PostDetailViewController: NSFetchedResultsControllerDelegate {
}
