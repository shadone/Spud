//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

class PersonViewController: UIViewController {
    typealias OwnDependencies =
        HasVoid
    typealias NestedDependencies =
        PersonViewModel.Dependencies
    typealias Dependencies = OwnDependencies & NestedDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    // MARK: - UI Properties

    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension

        tableView.dataSource = self

        tableView.register(PersonHeaderCell.self, forCellReuseIdentifier: PersonHeaderCell.reuseIdentifier)

        return tableView
    }()

    // MARK: - Private

    private var viewModel: PersonViewModelType

    // MARK: - Functions

    init(personInfo: LemmyPersonInfo, dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        viewModel = PersonViewModel(
            personInfo: personInfo,
            dependencies: self.dependencies.nested
        )
        super.init(nibName: nil, bundle: nil)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
}

// MARK: - UITableView DataSource

extension PersonViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            // Section 0: header
            return 1
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
                withIdentifier: PersonHeaderCell.reuseIdentifier,
                for: indexPath
            ) as! PersonHeaderCell

            cell.tableView = tableView

            cell.isBeingConfigured = true
            cell.configure(with: viewModel.outputs.headerViewModel)
            cell.isBeingConfigured = false

            return cell
        } else {
            fatalError()
        }
    }
}
