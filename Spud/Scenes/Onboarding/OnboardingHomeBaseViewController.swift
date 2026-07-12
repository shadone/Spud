//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

/// "Pick your home base" — the onboarding instance picker shown after Welcome's
/// "Get started". De-jargons federation: the instance is "where your account
/// lives", with a strong recommended default and a promise it never fences the
/// user in.
///
/// Recreated in UIKit from the Spud Design `onboarding.jsx` `HomePick` mockup.
/// The top three Explorer instances (by `.recommended` sort) render as cards;
/// the #1 is flagged RECOMMENDED with an accent border. Tapping a card — or the
/// "Continue" CTA, which proceeds with the recommended instance — pushes the
/// existing `InstanceDetailViewController`. "Browse all servers" pushes the full
/// `SiteListViewController`.
///
/// The design's `FlowTop` step indicator ("1 of 3") and "Skip" are intentionally
/// omitted: the interests / suggestions steps they advertise are deferred and do
/// not exist, so showing them would mislead. Only a back chevron remains.
final class OnboardingHomeBaseViewController: UIViewController {
    typealias OwnDependencies =
        HasAppDatabase &
        HasImageService
    typealias NestedDependencies =
        InstanceDetailViewController.Dependencies &
        SiteListViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    private var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    /// The recommended instance rows, highest Explorer score first. The first,
    /// when present, is the RECOMMENDED default the "Continue" CTA proceeds with.
    private let rows: [SiteListRow]

    /// How many recommended cards to show.
    private static let maxCards = 3

    private let scrollView = UIScrollView()
    private var imageTasks: [Task<Void, Never>] = []

    /// The recommended (#1) card, retained so its accent border can be refreshed
    /// when the trait collection or tint color changes (CGColors don't
    /// re-resolve automatically).
    private weak var recommendedCard: UIControl?

    // MARK: Init

    init(dependencies: Dependencies) {
        self.dependencies = (own: dependencies, nested: dependencies)

        // Rank the cached Explorer directory by the recommended sort and take the
        // top few for the cards. A sync read at setup is enough for this screen.
        let allRows = dependencies.appDatabase.explorerSiteListRowsSync()
        let ranked = ExplorerInstanceDirectory.apply(
            to: allRows,
            query: "",
            filter: ExplorerInstanceFilter(),
            sort: .recommended
        )
        rows = Array(ranked.prefix(Self.maxCards))

        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        imageTasks.forEach { $0.cancel() }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    // MARK: Setup

    private func setup() {
        view.backgroundColor = Theme.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            primaryAction: UIAction { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            }
        )
        // The picker is reached via a push; show only the back chevron, no title.
        navigationItem.title = nil

        let continueButton = OnboardingPrimaryButton(
            title: NSLocalizedString("Continue", comment: "Onboarding home base primary CTA")
        )
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        view.addSubview(continueButton)

        let content = makeContentStack()
        scrollView.addSubview(content)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -16),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),

            continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])

        loadIcons()
    }

    private func makeContentStack() -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("Pick your home base", comment: "Onboarding home base title")
        titleLabel.font = .systemFont(ofSize: 27, weight: .heavy)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        let subtitleLabel = UILabel()
        subtitleLabel.text = NSLocalizedString(
            "It is just where your account lives. You will still see and join every community on Spud, wherever it is.",
            comment: "Onboarding home base subtitle"
        )
        subtitleLabel.font = .systemFont(ofSize: 14.5)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(18, after: subtitleLabel)

        for (index, row) in rows.enumerated() {
            stack.addArrangedSubview(makeInstanceCard(row: row, isRecommended: index == 0))
            stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)
        }

        stack.addArrangedSubview(makeBrowseAllRow())
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(makeEnterAddressRow())
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(makeReassuranceNote())

        return stack
    }

    // MARK: Instance card

    /// One avatar in the card, retained so the async icon fetch can reveal it.
    private var cardAvatars: [String: OnboardingInstanceAvatar] = [:]

    private func makeInstanceCard(row: SiteListRow, isRecommended: Bool) -> UIView {
        let card = UIControl()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1.5
        card.layer.borderColor = (isRecommended ? view.tintColor : UIColor.clear).cgColor
        card.addAction(UIAction { [weak self] _ in self?.open(row: row) }, for: .touchUpInside)
        if isRecommended {
            recommendedCard = card
        }

        let avatar = OnboardingInstanceAvatar(seed: row.hostname, size: 42, cornerRadius: 13)
        cardAvatars[row.hostname] = avatar

        let hostLabel = UILabel()
        hostLabel.text = row.hostname
        hostLabel.font = .systemFont(ofSize: 15.5, weight: .bold)
        hostLabel.textColor = .label
        hostLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleRow = UIStackView(arrangedSubviews: [hostLabel])
        titleRow.axis = .horizontal
        titleRow.spacing = 7
        titleRow.alignment = .center
        if isRecommended {
            titleRow.addArrangedSubview(makeRecommendedPill())
        }
        titleRow.addArrangedSubview(UIView())

        let textStack = UIStackView(arrangedSubviews: [titleRow])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.alignment = .fill

        if let blurb = row.descriptionText, !blurb.isEmpty {
            let blurbLabel = UILabel()
            blurbLabel.text = blurb
            blurbLabel.font = .systemFont(ofSize: 12.5)
            blurbLabel.textColor = .secondaryLabel
            blurbLabel.numberOfLines = 2
            textStack.addArrangedSubview(blurbLabel)
        }

        let metaLabel = UILabel()
        metaLabel.text = metaLine(for: row)
        metaLabel.font = .systemFont(ofSize: 11.5)
        metaLabel.textColor = .tertiaryLabel
        metaLabel.numberOfLines = 1
        textStack.addArrangedSubview(metaLabel)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)

        let hStack = UIStackView(arrangedSubviews: [avatar, textStack, chevron])
        hStack.axis = .horizontal
        hStack.spacing = 13
        hStack.alignment = .center
        hStack.isUserInteractionEnabled = false
        hStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(hStack)

        NSLayoutConstraint.activate([
            hStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            hStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            hStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            hStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            chevron.widthAnchor.constraint(equalToConstant: 18),
            chevron.heightAnchor.constraint(equalToConstant: 18),
        ])
        return card
    }

    private func makeRecommendedPill() -> UIView {
        let label = UILabel()
        label.text = NSLocalizedString("RECOMMENDED", comment: "Onboarding recommended instance pill")
        label.font = .systemFont(ofSize: 9, weight: .heavy)
        label.textColor = view.tintColor

        let container = UIView()
        container.backgroundColor = view.tintColor.withAlphaComponent(0.14)
        container.layer.cornerRadius = 5
        container.layer.cornerCurve = .continuous
        container.setContentHuggingPriority(.required, for: .horizontal)
        container.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
        ])
        return container
    }

    // MARK: Browse all / reassurance rows

    private func makeBrowseAllRow() -> UIView {
        makeFooterRow(
            systemImageName: "magnifyingglass",
            title: NSLocalizedString("Browse all servers", comment: "Onboarding browse all servers row")
        ) { [weak self] in self?.browseAllTapped() }
    }

    /// Sibling to "Browse all servers": pushes `CustomInstanceEntryViewController`
    /// directly so a user with a private, non-federated instance reaches the
    /// address field in one tap from first-run onboarding.
    private func makeEnterAddressRow() -> UIView {
        makeFooterRow(
            systemImageName: "plus.circle",
            title: NSLocalizedString("Enter instance address", comment: "Onboarding enter instance address row")
        ) { [weak self] in self?.enterAddressTapped() }
    }

    /// Shared builder for the two footer affordance rows: a secondary-label SF
    /// Symbol, a semibold label, and a trailing chevron, matching in style and
    /// hit-target size.
    private func makeFooterRow(systemImageName: String, title: String, action: @escaping () -> Void) -> UIView {
        let control = UIControl()
        control.addAction(UIAction { _ in action() }, for: .touchUpInside)

        let icon = UIImageView(
            image: UIImage(
                systemName: systemImageName,
                withConfiguration: UIImage.SymbolConfiguration(weight: .semibold)
            )
        )
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .label

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [icon, label, UIView(), chevron])
        stack.axis = .horizontal
        stack.spacing = 9
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: control.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: control.bottomAnchor, constant: -10),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            chevron.widthAnchor.constraint(equalToConstant: 16),
            chevron.heightAnchor.constraint(equalToConstant: 16),
        ])
        return control
    }

    private func makeReassuranceNote() -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 12
        container.layer.cornerCurve = .continuous

        let icon = UIImageView(
            image: UIImage(
                systemName: "globe",
                withConfiguration: UIImage.SymbolConfiguration(weight: .semibold)
            )
        )
        icon.tintColor = view.tintColor
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = NSLocalizedString(
            "New here? Keep the recommendation. You can change it later, and it never limits what you can read or join.",
            comment: "Onboarding home base reassurance note"
        )
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 13),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        return container
    }

    // MARK: Meta line

    /// "<members> members · <Open sign-up | Reviews new accounts>".
    private func metaLine(for row: SiteListRow) -> String {
        let signup = row.isOpenRegistration
            ? NSLocalizedString("Open sign-up", comment: "Instance open registration")
            : NSLocalizedString("Reviews new accounts", comment: "Instance closed/application registration")
        guard let members = row.usersTotal, members > 0 else {
            return signup
        }
        let formatted = CountFormatter.string(members)
        let membersText = String(
            format: NSLocalizedString("%@ members", comment: "Instance member count"),
            formatted
        )
        return "\(membersText) · \(signup)"
    }

    // MARK: Icons

    private func loadIcons() {
        for row in rows {
            guard let iconUrl = row.iconUrl, let avatar = cardAvatars[row.hostname] else { continue }
            let stream = imageService.fetch(iconUrl)
            let task = Task { [weak avatar] in
                for await state in stream {
                    if case let .ready(image) = state {
                        avatar?.setImage(image)
                    }
                }
            }
            imageTasks.append(task)
        }
    }

    // MARK: Navigation

    /// Pushes the instance detail ("before you commit") screen for `row`, the
    /// same surface `SiteListViewController` shows on selection. Falls back to
    /// the full server list when the directory record can't be resolved.
    private func open(row: SiteListRow) {
        if let record = appDatabase.explorerInstanceSync(baseurl: row.hostname) {
            let detail = InstanceDetailViewController(record: record, dependencies: dependencies.nested)
            navigationController?.pushViewController(detail, animated: true)
        } else {
            pushSiteList()
        }
    }

    private func pushSiteList() {
        // Pushed onto the onboarding nav stack, so omit the "Cancel" item and
        // let UIKit show the system back button instead.
        let siteList = SiteListViewController(dependencies: dependencies.nested, showsCancelButton: false)
        navigationController?.pushViewController(siteList, animated: true)
    }

    @objc
    private func continueTapped() {
        // Proceed with the recommended instance; fall back to the full server
        // list when there is no recommendation / no Explorer data.
        if let recommended = rows.first {
            open(row: recommended)
        } else {
            pushSiteList()
        }
    }

    private func browseAllTapped() {
        pushSiteList()
    }

    private func enterAddressTapped() {
        let entry = CustomInstanceEntryViewController(dependencies: dependencies.nested)
        navigationController?.pushViewController(entry, animated: true)
    }

    // MARK: Trait changes

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // CGColor border colors don't re-resolve on trait/tint changes; refresh
        // the recommended card's accent border (the only accent border) on every
        // layout pass so it tracks tint propagation and dark/light switches.
        recommendedCard?.layer.borderColor = view.tintColor.cgColor
    }
}
