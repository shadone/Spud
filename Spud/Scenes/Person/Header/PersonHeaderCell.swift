//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

class PersonHeaderCell: UITableViewCellBase {
    static let reuseIdentifier = "PersonHeaderCell"

    // MARK: UI Properties

    lazy var mainStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.distribution = .fillEqually
        stackView.spacing = 8
        stackView.accessibilityIdentifier = "mainStackView"

        [
            commentKarmaStatView,
            postKarmaStatView,
            accountAgeStatView,
        ].forEach(stackView.addArrangedSubview)

        return stackView
    }()

    lazy var commentKarmaStatView: PersonHeaderStatView = {
        let view = PersonHeaderStatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "commentKarmaStatView"
        view.text = "Comment\nKarma"
        return view
    }()

    lazy var postKarmaStatView: PersonHeaderStatView = {
        let view = PersonHeaderStatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "postKarmaStatView"
        view.text = "Post\nKarma"
        return view
    }()

    lazy var accountAgeStatView: PersonHeaderStatView = {
        let view = PersonHeaderStatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "accountAgeStatView"
        view.text = "Account\nAge"
        return view
    }()

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    private var postImageContainerHeightConstraint: NSLayoutConstraint!

    // MARK: Functions

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        backgroundColor = .systemGroupedBackground

        contentView.addSubview(mainStackView)

        NSLayoutConstraint.activate([
            mainStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        prepareForReuse()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        disposables.removeAll()
    }

    func configure(with viewModel: PersonHeaderViewModel) {
        viewModel.commentKarma
            .wrapInOptional()
            .assign(to: \.value, on: commentKarmaStatView)
            .store(in: &disposables)

        viewModel.postKarma
            .wrapInOptional()
            .assign(to: \.value, on: postKarmaStatView)
            .store(in: &disposables)

        viewModel.accountAge
            .wrapInOptional()
            .assign(to: \.value, on: accountAgeStatView)
            .store(in: &disposables)
    }
}
