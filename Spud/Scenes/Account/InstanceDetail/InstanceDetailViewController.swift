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

/// "Before you commit" instance detail (Explorer feature #4). Shown between the
/// instance picker and the login form: banner + identity, a colour-coded health
/// band (score ring + trust + pills), a stat grid, a details list, and sticky
/// actions. Health signals degrade to "—"/unknown on missing data.
/// Recreated in UIKit from the Spud Design "Spud Instance Detail" mockup
/// (Concept A), using SpudUIKit theme tokens + the app accent.
final class InstanceDetailViewController: UIViewController {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase &
        HasImageService &
        HasMetaCommunityService &
        HasNodeInfoService
    typealias NestedDependencies =
        LoginViewController.Dependencies &
        RegisterViewController.Dependencies
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    private var imageService: ImageServiceType {
        dependencies.own.imageService
    }

    private var accountService: AccountServiceType {
        dependencies.own.accountService
    }

    private var appDatabase: AppDatabase {
        dependencies.own.appDatabase
    }

    private var nodeInfoService: NodeInfoServiceType {
        dependencies.own.nodeInfoService
    }

    private var metaCommunityService: MetaCommunityServiceType {
        dependencies.own.metaCommunityService
    }

    private let record: ExplorerInstanceRecord
    private let row: SiteListRow?
    private let showsActions: Bool

    private let scrollView = UIScrollView()
    private let bannerImageView = UIImageView()
    private let iconImageView = UIImageView()
    private let iconLetterLabel = UILabel()
    /// Detected software identity (e.g. "PieFed" or "Lemmy 0.19.11"), populated
    /// by a live NodeInfo metadata probe on appear.
    private let softwareBadgeLabel = UILabel()
    /// The "Signups" details-row value label, captured so a live NodeInfo
    /// `openRegistrations` probe can override the Explorer-directory value.
    private weak var signupsValueLabel: UILabel?
    /// The "Software" details-row value label, captured so a live NodeInfo
    /// version probe can override the Explorer-directory version — keeping the
    /// details card in step with the header badge (which already shows live).
    private weak var softwareValueLabel: UILabel?
    private var imageTasks: [Task<Void, Never>] = []
    private var observationTasks: [Task<Void, Never>] = []

    /// The "Browse only" button, captured so `browseTapped()` can disable it
    /// and swap in an activity indicator while its `detect(host:)` await is in
    /// flight.
    private weak var browseButton: UIButton?
    /// Guards `browseTapped()` against re-entry while a previous tap's
    /// `detect(host:)` await is still in flight. Checked synchronously at the
    /// top of `browseTapped()` -- disabling `browseButton` alone isn't enough,
    /// since a second tap already queued on the run loop before `isEnabled`
    /// takes effect would otherwise still fire.
    private var isBrowseInFlight = false

    private var adminsView: InstanceAdminsView!
    /// "About this instance" section: the viewed instance's classified "meta"
    /// communities for the signed-in default account, live from
    /// `AppDatabase.observeMetaCommunities`. Hidden (no empty state) until the
    /// observation yields at least one item. `metaItems` is exposed so a
    /// future long-press context menu (Task 3) can resolve the item behind a
    /// given row.
    private var metaContainer: UIStackView!
    private(set) var metaItems: [MetaCommunityListItem] = []
    private var communitiesContainer: UIStackView!

    /// The notice banner and its tint, kept so dynamic `CGColor` borders can be
    /// re-resolved on a light/dark trait change (see `refreshDynamicBorders`).
    private weak var noticeBannerContainer: UIView?
    private var noticeBannerColor: UIColor?

    private var accent: UIColor {
        ThemeManager.currentAccentColor
    }

    // MARK: Init

    init(record: ExplorerInstanceRecord, showsActions: Bool = true, dependencies: Dependencies) {
        self.record = record
        self.showsActions = showsActions
        row = SiteListRow(explorerInstance: record)
        self.dependencies = (own: dependencies, nested: dependencies)
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        imageTasks.forEach { $0.cancel() }
        observationTasks.forEach { $0.cancel() }
    }

    // MARK: Test support

    /// The height of the scroll view's content after layout. Used by snapshot tests to
    /// size the snapshot tall enough to capture admins and communities below the fold.
    var snapshotContentHeight: CGFloat {
        view.layoutIfNeeded()
        return scrollView.contentSize.height
    }

    /// The software badge's visible text, or `nil` while it is hidden. Snapshot
    /// tests poll this to await the async live-metadata probe before capturing.
    var snapshotSoftwareBadgeText: String? {
        softwareBadgeLabel.isHidden ? nil : softwareBadgeLabel.text
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        loadImages()
        loadSecondaryData()
        // The icon ring and notice banner use CALayer borders (CGColor), which
        // don't re-resolve on their own; refresh them on a light/dark switch.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: InstanceDetailViewController, _: UITraitCollection) in
            vc.refreshDynamicBorders()
        }
        observationTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            guard let metadata = await nodeInfoService.metadata(host: record.baseurl) else { return }
            applyLiveMetadata(metadata)
        })
    }

    /// Applies live NodeInfo metadata to the header software badge (name +
    /// version), the details-card Software row, and the details-card Signups
    /// row. Fail-open: overrides only the fields the probe actually reported —
    /// a nil field keeps the current Explorer-directory value, and an
    /// overall-nil metadata (probe failed / unknown software) leaves the screen
    /// exactly as first rendered.
    private func applyLiveMetadata(_ metadata: InstanceMetadata) {
        let profile = PlatformProfile.profile(for: metadata.software, version: metadata.version)
        if let version = metadata.version, !version.isEmpty {
            // e.g. "Lemmy 0.19.11" — the software's display name plus the live version.
            softwareBadgeLabel.text = "\(profile.displayName) \(version)"

            // Unify the details-card "Software" row on the same live version. The
            // Explorer directory seeds that row from `record.version`; the live probe
            // is more current, so leaving the row on the directory value shows two
            // different numbers for one instance (header badge vs details row) exactly
            // when the feature works. Reusing `ExplorerInstanceHealth.version` reproduces
            // the row's existing "v<number>" formatting and freshness color verbatim, so
            // only the number differs when live and directory disagree — never the style.
            //
            // Plan point 4 ("don't mix live/directory numbers in one grid") targets
            // incomparable COUNT SCALES (per-instance local counts vs directory
            // aggregates); a version STRING has no scale problem, so unifying it is in
            // that plan point's spirit rather than against it. Fail-open: a nil/empty
            // live version leaves the Explorer Software row untouched.
            let liveVersion = ExplorerInstanceHealth.version(version)
            softwareValueLabel?.text = liveVersion.short
            softwareValueLabel?.textColor = InstanceHealthStyle.color(for: liveVersion.level)
        } else {
            softwareBadgeLabel.text = profile.displayName
        }
        softwareBadgeLabel.isHidden = false

        // Prefer the live open-registrations signal over the Explorer directory's
        // `regMode`. `openRegistrations == nil` means "not probed" (never "closed"),
        // so we fall open to the Explorer value already shown in the row. The copy
        // matches `ExplorerInstanceHealth.registration(_:)`'s long-form wording
        // verbatim ("Open signups" / "Signups closed") — the row's text must never
        // change between the synchronous Explorer fallback and the async live
        // override, only the value (and therefore only the color) may differ when
        // the live probe disagrees with the directory.
        if let openRegistrations = metadata.openRegistrations {
            signupsValueLabel?.text = openRegistrations ? "Open signups" : "Signups closed"
            signupsValueLabel?.textColor = InstanceHealthStyle.color(for: openRegistrations ? .good : .bad)
        }
    }

    private func refreshDynamicBorders() {
        iconImageView.layer.borderColor = Theme.groupedBackground.cgColor
        noticeBannerContainer?.layer.borderColor = noticeBannerColor?.withAlphaComponent(0.26).cgColor
    }

    // MARK: Setup

    private func setup() {
        view.backgroundColor = Theme.groupedBackground
        navigationItem.title = record.baseurl
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: UIAction { [weak self] _ in self?.shareTapped() },
            menu: nil
        )

        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        if showsActions {
            let actionBar = makeActionBar()
            view.addSubview(actionBar)
            actionBar.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: view.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: actionBar.topAnchor),

                actionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                actionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                actionBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: view.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide

        let header = makeHeader()
        let body = makeBody()
        scrollView.addSubview(header)
        scrollView.addSubview(body)
        header.translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor),
            header.leadingAnchor.constraint(equalTo: frame.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: frame.trailingAnchor),

            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            body.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: 16),
            body.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -16),
            body.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    // MARK: Header (banner + icon + identity)

    private func makeHeader() -> UIView {
        let container = UIView()

        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.clipsToBounds = true
        bannerImageView.backgroundColor = placeholderColor(saturation: 0.5, brightness: 0.5)
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bannerImageView)

        iconImageView.contentMode = .scaleAspectFill
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = 16
        iconImageView.layer.cornerCurve = .continuous
        iconImageView.layer.borderWidth = 3
        iconImageView.layer.borderColor = Theme.groupedBackground.cgColor
        iconImageView.backgroundColor = placeholderColor(saturation: 0.45, brightness: 0.55)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconLetterLabel.text = String(record.name.prefix(1)).uppercased()
        iconLetterLabel.font = .systemFont(ofSize: 26, weight: .heavy)
        iconLetterLabel.textColor = .white
        iconLetterLabel.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.addSubview(iconLetterLabel)
        container.addSubview(iconImageView)

        let nameLabel = UILabel()
        nameLabel.text = record.name
        nameLabel.font = .systemFont(ofSize: 20, weight: .heavy)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 2

        let hostLabel = UILabel()
        hostLabel.text = record.baseurl
        hostLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        hostLabel.textColor = .secondaryLabel

        softwareBadgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        softwareBadgeLabel.textColor = .secondaryLabel
        softwareBadgeLabel.isHidden = true

        let identity = UIStackView(arrangedSubviews: [nameLabel, hostLabel, softwareBadgeLabel])
        identity.axis = .vertical
        identity.spacing = 3
        identity.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(identity)

        NSLayoutConstraint.activate([
            bannerImageView.topAnchor.constraint(equalTo: container.topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: 158),

            iconImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            iconImageView.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: -30),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),
            iconLetterLabel.centerXAnchor.constraint(equalTo: iconImageView.centerXAnchor),
            iconLetterLabel.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor),

            identity.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 13),
            identity.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            identity.bottomAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: -2),

            container.bottomAnchor.constraint(equalTo: iconImageView.bottomAnchor),
        ])
        return container
    }

    // MARK: Body

    private func makeBody() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14

        if let description = descriptionText() {
            let label = UILabel()
            label.text = description
            label.font = .systemFont(ofSize: 14)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
            stack.setCustomSpacing(15, after: label)
        }

        stack.addArrangedSubview(makeHealthBand())
        stack.addArrangedSubview(makeStatGrid())
        stack.addArrangedSubview(makeDetailsHeader())
        stack.setCustomSpacing(7, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(makeDetailsCard())

        let tags = record.tagList
        if !tags.isEmpty {
            let wrap = InstanceWrapView()
            wrap.setItems(tags.map { makeChip($0) })
            stack.addArrangedSubview(wrap)
        }

        adminsView = InstanceAdminsView()
        adminsView.update(.loading)
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(adminsView)

        metaContainer = UIStackView()
        metaContainer.axis = .vertical
        metaContainer.spacing = 8
        metaContainer.isHidden = true
        stack.addArrangedSubview(metaContainer)

        communitiesContainer = UIStackView()
        communitiesContainer.axis = .vertical
        communitiesContainer.spacing = 8
        stack.addArrangedSubview(communitiesContainer)

        return stack
    }

    private func makeHealthBand() -> UIView {
        let card = makeCard()

        let trust = ExplorerInstanceHealth.trust(score100: score100(), suspicious: record.isSuspicious)
        let ring = InstanceScoreRingView()
        ring.configure(score100: score100(), color: InstanceHealthStyle.color(for: trust.level))
        ring.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 56),
            ring.heightAnchor.constraint(equalToConstant: 56),
        ])

        let trustIcon = UIImageView(image: UIImage(systemName: InstanceHealthStyle.trustSymbol(trust.level)))
        trustIcon.tintColor = InstanceHealthStyle.color(for: trust.level)
        trustIcon.contentMode = .scaleAspectFit
        trustIcon.setContentHuggingPriority(.required, for: .horizontal)
        let trustLabel = UILabel()
        trustLabel.text = trust.label
        trustLabel.font = .systemFont(ofSize: 14, weight: .bold)
        trustLabel.textColor = InstanceHealthStyle.color(for: trust.level)
        let trustRow = UIStackView(arrangedSubviews: [trustIcon, trustLabel, UIView()])
        trustRow.axis = .horizontal
        trustRow.spacing = 7
        trustRow.alignment = .center
        NSLayoutConstraint.activate([
            trustIcon.widthAnchor.constraint(equalToConstant: 16),
            trustIcon.heightAnchor.constraint(equalToConstant: 16),
        ])

        let uptime = ExplorerInstanceHealth.uptime(record.uptimeAllTime)
        let version = ExplorerInstanceHealth.version(record.version)
        let registration = ExplorerInstanceHealth.registration(record.registrationMode)
        var pills: [UIView] = [
            InstanceHealthPillView(symbol: "waveform.path.ecg", text: "\(uptime.short) up", color: InstanceHealthStyle.color(for: uptime.level)),
            InstanceHealthPillView(symbol: "tag", text: version.short, color: InstanceHealthStyle.color(for: version.level)),
            InstanceHealthPillView(symbol: InstanceHealthStyle.registrationSymbol(record.registrationMode), text: InstanceHealthStyle.registrationShort(record.registrationMode), color: InstanceHealthStyle.color(for: registration.level)),
        ]
        if record.isNsfw {
            pills.append(InstanceHealthPillView(symbol: "eye", text: "NSFW", color: InstanceHealthStyle.color(for: .unknown)))
        }
        let pillWrap = InstanceWrapView()
        pillWrap.hSpacing = 6
        pillWrap.vSpacing = 6
        pillWrap.setItems(pills)

        let rightColumn = UIStackView(arrangedSubviews: [trustRow, pillWrap])
        rightColumn.axis = .vertical
        rightColumn.spacing = 9

        let band = UIStackView(arrangedSubviews: [ring, rightColumn])
        band.axis = .horizontal
        band.spacing = 14
        band.alignment = .center
        band.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(band)
        pinToCard(band, card, inset: 14)
        return card
    }

    private func makeStatGrid() -> UIView {
        let card = makeCard()
        let items: [(String, String?)] = [
            (InstanceHealthStyle.formatCount(record.usersTotal), "Members"),
            (InstanceHealthStyle.formatCount(record.usersActiveMonth), "Active /mo"),
            (InstanceHealthStyle.formatCount(record.numberOfPosts), "Posts"),
            (InstanceHealthStyle.formatCount(record.numberOfCommunities), "Communities"),
        ]
        let top = makeGridRow(items[0], items[1])
        let bottom = makeGridRow(items[2], items[3])
        let grid = UIStackView(arrangedSubviews: [top, hairline(vertical: false), bottom])
        grid.axis = .vertical
        grid.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(grid)
        pinToCard(grid, card, inset: 0)
        return card
    }

    private func makeGridRow(_ a: (String, String?), _ b: (String, String?)) -> UIView {
        let left = statTile(a.0, a.1 ?? "")
        let right = statTile(b.0, b.1 ?? "")
        let line = hairline(vertical: true)
        let r = UIStackView(arrangedSubviews: [left, line, right])
        r.axis = .horizontal
        r.alignment = .fill
        left.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        return r
    }

    private func statTile(_ value: String, _ label: String) -> UIView {
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 19, weight: .heavy)
        valueLabel.textColor = value == "—" ? .tertiaryLabel : .label
        let captionLabel = UILabel()
        captionLabel.text = label.uppercased()
        captionLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        captionLabel.textColor = .tertiaryLabel
        let s = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        s.axis = .vertical
        s.spacing = 3
        s.alignment = .leading
        s.isLayoutMarginsRelativeArrangement = true
        s.layoutMargins = .init(top: 11, left: 12, bottom: 11, right: 12)
        return s
    }

    private func makeDetailsHeader() -> UIView {
        let label = UILabel()
        label.text = "DETAILS"
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .tertiaryLabel
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])
        return container
    }

    private func makeDetailsCard() -> UIView {
        let card = makeCard()
        let uptime = ExplorerInstanceHealth.uptime(record.uptimeAllTime)
        let version = ExplorerInstanceHealth.version(record.version)
        let registration = ExplorerInstanceHealth.registration(record.registrationMode)

        let uptimeValue: String = {
            guard uptime.level != .unknown, let v = record.uptimeAllTime else { return "Unknown" }
            let base = uptime.short
            if let latency = record.latency { return "\(base) · \(Int(latency))ms" }
            _ = v
            return base
        }()
        let federation: String = {
            guard let incoming = record.blocksIncoming, let outgoing = record.blocksOutgoing else { return "—" }
            return "\(incoming) in · \(outgoing) out"
        }()
        let languages = record.languageCodes.isEmpty ? "—" : record.languageCodes.map { $0.uppercased() }.joined(separator: ", ")

        let rows = [
            metaRow(
                symbol: InstanceHealthStyle.registrationSymbol(record.registrationMode),
                label: "Signups",
                value: registration.label,
                valueColor: InstanceHealthStyle.color(for: registration.level),
                captureValueLabel: { [weak self] in self?.signupsValueLabel = $0 }
            ),
            metaRow(symbol: "waveform.path.ecg", label: "Uptime", value: uptimeValue, valueColor: InstanceHealthStyle.color(for: uptime.level)),
            metaRow(
                symbol: "tag",
                label: "Software",
                value: version.short,
                valueColor: InstanceHealthStyle.color(for: version.level),
                captureValueLabel: { [weak self] in self?.softwareValueLabel = $0 }
            ),
            metaRow(symbol: "character.bubble", label: "Languages", value: languages, valueColor: .label),
            metaRow(symbol: "arrow.triangle.branch", label: "Federation", value: federation, valueColor: .label),
        ]
        let stack = UIStackView()
        stack.axis = .vertical
        for (index, row) in rows.enumerated() {
            stack.addArrangedSubview(row)
            if index < rows.count - 1 {
                let line = hairline(vertical: false)
                let inset = UIStackView(arrangedSubviews: [line])
                inset.isLayoutMarginsRelativeArrangement = true
                inset.layoutMargins = .init(top: 0, left: 14, bottom: 0, right: 0)
                stack.addArrangedSubview(inset)
            }
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        pinToCard(stack, card, inset: 0)
        return card
    }

    /// - Parameter captureValueLabel: Optional sink handed the row's value
    ///   `UILabel` so a later async probe (e.g. live Signups) can update it.
    private func metaRow(symbol: String, label: String, value: String, valueColor: UIColor, captureValueLabel: ((UILabel) -> Void)? = nil) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let labelView = UILabel()
        labelView.text = label
        labelView.font = .systemFont(ofSize: 14)
        labelView.textColor = .secondaryLabel
        labelView.setContentHuggingPriority(.required, for: .horizontal)
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        valueLabel.textColor = valueColor
        valueLabel.textAlignment = .right
        valueLabel.numberOfLines = 1
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        captureValueLabel?(valueLabel)
        let stack = UIStackView(arrangedSubviews: [icon, labelView, valueLabel])
        stack.axis = .horizontal
        stack.spacing = 11
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = .init(top: 11, left: 14, bottom: 11, right: 14)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
        ])
        return stack
    }

    private func makeChip(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12.5, weight: .semibold)
        label.textColor = .secondaryLabel
        let container = UIView()
        container.backgroundColor = Theme.secondaryBackground
        container.layer.cornerRadius = 9
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 11),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -11),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),
        ])
        return container
    }

    // MARK: Action bar (sticky)

    private func makeActionBar() -> UIView {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        let hairlineView = UIView()
        hairlineView.backgroundColor = .separator
        hairlineView.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(hairlineView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)

        if let notice = makeNoticeBanner() {
            stack.addArrangedSubview(notice)
        }

        let createSpec = createButtonSpec()
        let primary = makePrimaryButton(title: createSpec.title, enabled: createSpec.enabled)
        if createSpec.enabled {
            primary.addAction(UIAction { [weak self] _ in self?.createTapped() }, for: .touchUpInside)
        }
        stack.addArrangedSubview(primary)

        let signIn = makeSecondaryButton(title: "Sign in", accent: true)
        signIn.addAction(UIAction { [weak self] _ in self?.signInTapped() }, for: .touchUpInside)
        let browse = makeSecondaryButton(title: "Browse only", accent: false)
        browse.addAction(UIAction { [weak self] _ in self?.browseTapped() }, for: .touchUpInside)
        browseButton = browse
        let secondary = UIStackView(arrangedSubviews: [signIn, browse])
        secondary.axis = .horizontal
        secondary.spacing = 10
        secondary.distribution = .fillEqually
        stack.addArrangedSubview(secondary)

        NSLayoutConstraint.activate([
            hairlineView.topAnchor.constraint(equalTo: blur.contentView.topAnchor),
            hairlineView.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor),
            hairlineView.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor),
            hairlineView.heightAnchor.constraint(equalToConstant: 0.5),

            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        return blur
    }

    private func makeNoticeBanner() -> UIView? {
        guard let notice = noticeFor() else { return nil }
        let color = notice.color
        let container = UIView()
        container.backgroundColor = color.withAlphaComponent(0.13)
        container.layer.cornerRadius = 12
        container.layer.borderWidth = 1
        container.layer.borderColor = color.withAlphaComponent(0.26).cgColor
        noticeBannerContainer = container
        noticeBannerColor = color

        let icon = UIImageView(image: UIImage(systemName: notice.symbol))
        icon.tintColor = color
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = notice.title
        title.font = .systemFont(ofSize: 13, weight: .bold)
        title.textColor = color
        title.numberOfLines = 0
        let body = UILabel()
        body.text = notice.body
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabel
        body.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [title, body])
        text.axis = .vertical
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(text)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            text.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            text.topAnchor.constraint(equalTo: container.topAnchor, constant: 11),
            text.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -11),
        ])
        return container
    }

    private func makePrimaryButton(title: String, enabled: Bool) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = enabled ? accent : Theme.secondaryBackground
        config.baseForegroundColor = enabled ? .white : .tertiaryLabel
        config.cornerStyle = .large
        config.contentInsets = .init(top: 14, leading: 16, bottom: 14, trailing: 16)
        let button = UIButton(configuration: config)
        button.isEnabled = enabled
        button.titleLabel?.font = .systemFont(ofSize: 16.5, weight: .bold)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
    }

    private func makeSecondaryButton(title: String, accent useAccent: Bool) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = useAccent ? accent : .label
        config.background.strokeColor = .separator
        config.background.strokeWidth = 1.5
        config.background.cornerRadius = 13
        let button = UIButton(configuration: config)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        return button
    }

    // MARK: Actions

    private func createTapped() {
        guard let row else { return }
        let viewController = RegisterViewController(row: row, dependencies: dependencies.nested)
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func signInTapped() {
        guard let row else { return }
        let viewController = LoginViewController(row: row, dependencies: dependencies.nested)
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func browseTapped() {
        // Re-entry guard: a fast double-tap while `detect(host:)` is still in
        // flight would otherwise kick off a second signed-out account
        // resolution + dismiss race. Checked before disabling the button
        // (below) because a tap already queued on the run loop this turn would
        // still land even if `isEnabled` were set first.
        guard !isBrowseInFlight, let instance = row?.instance else { return }
        isBrowseInFlight = true
        setBrowseButtonBusy(true)

        let nodeInfoService = nodeInfoService
        let accountService = accountService
        Task { @MainActor [weak self] in
            // `AccountService.resolvedApiVersion` reads the NodeInfo cache
            // SYNCHRONOUSLY when the browse account's `LemmyService` is later
            // built, so this host's software must already be resolved by then.
            // `viewDidLoad`'s metadata probe is best-effort and gets cancelled
            // (via `deinit`) by the `dismiss` below if the user taps through
            // before it lands, so await detection explicitly here too — the
            // common case is an instant cache hit from that same probe, with
            // no extra network fetch (`detect`/`metadata` share one host-keyed
            // cache row and TTL).
            _ = await nodeInfoService.detect(host: instance.host)
            accountService.signInAsSignedOut(atInstance: instance)
            guard let self else { return }
            isBrowseInFlight = false
            setBrowseButtonBusy(false)
            dismiss(animated: true)
        }
    }

    /// Toggles the "Browse only" button's activity indicator + enabled state
    /// for the duration of `browseTapped()`'s NodeInfo detect await. Uses
    /// `UIButton.Configuration`'s built-in `showsActivityIndicator` (keeps the
    /// title, adds a spinner in the image slot) rather than a separate overlay
    /// view.
    private func setBrowseButtonBusy(_ busy: Bool) {
        guard var config = browseButton?.configuration else { return }
        config.showsActivityIndicator = busy
        browseButton?.configuration = config
        browseButton?.isEnabled = !busy
    }

    private func shareTapped() {
        guard let url = URL(string: "https://\(record.baseurl)") else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activity, animated: true)
    }

    // MARK: Images

    private func loadImages() {
        if let iconUrl = (record.iconUrl).flatMap(URL.init(string:)) {
            iconLetterLabel.isHidden = true
            fetch(iconUrl, into: iconImageView, fallbackLetter: true)
        }
        if let bannerUrl = (record.bannerUrl).flatMap(URL.init(string:)) {
            fetch(bannerUrl, into: bannerImageView, fallbackLetter: false)
        }
    }

    // MARK: Secondary data (admins + communities)

    private func loadSecondaryData() {
        guard let instance = InstanceActorId(from: record.url ?? "https://\(record.baseurl)") else {
            adminsView.update(.unavailable)
            return
        }

        let allRows = appDatabase.explorerCommunityListRowsSync()
        let comms = ExplorerCommunityDirectory.communities(onInstance: record.baseurl, in: allRows, sort: .members)
        renderCommunities(into: communitiesContainer, comms: comms)

        // Synchronous cache-first render so the initial layout shows seeded data
        // without waiting for the async network refresh.
        let cachedAdmins = appDatabase.siteAdminsSync(forInstanceActorId: instance)
        adminsView.update(Self.adminsState(cachedAdmins, isSuspicious: record.isSuspicious))

        let keychainId = accountService.accountForSignedOut(forInstance: instance, isServiceAccount: true)
        let service = accountService.scope(forAccountKeychainId: keychainId).lemmyService
        let appDatabase = appDatabase
        let isSuspicious = record.isSuspicious
        observationTasks.append(Task { @MainActor [weak self] in
            try? await service.fetchSiteInfo()
            for await admins in appDatabase.observeSiteAdmins(forInstanceActorId: instance) {
                if Task.isCancelled { break }
                guard let self else { break }
                adminsView.update(Self.adminsState(admins, isSuspicious: isSuspicious))
            }
        })

        // "About this instance" meta-community section: only exists when a
        // default (non-service) account is signed in — the acting account for
        // both the refresh and the observation below. No account -> no
        // section, and no refresh is ever triggered.
        if let userKeychainId = appDatabase.defaultAccountKeychainIdSync(),
           let accountId = appDatabase.accountRowIdSync(forKeychainId: userKeychainId)
        {
            let metaService = metaCommunityService
            let host = record.baseurl
            let siteName: String? = record.name
            observationTasks.append(Task { @MainActor in
                // Fire-and-forget: the observation below renders whatever the
                // refresh (or a previous day's cache) yields; a miss just
                // leaves the section absent.
                await metaService.refreshInstance(host: host, siteName: siteName, forAccountKeychainId: userKeychainId)
            })
            observationTasks.append(Task { @MainActor [weak self] in
                for await items in appDatabase.observeMetaCommunities(forAccountId: accountId, instanceHost: host) {
                    if Task.isCancelled { break }
                    guard let self else { break }
                    renderMetaCommunities(items)
                }
            })
        }
    }

    /// Renders the "About this instance" card from the live meta-community
    /// observation: hidden while `items` is empty (no empty state — the
    /// section simply doesn't exist until there's something to show), else an
    /// `InstanceSectionHeader` plus a card of `InstanceMetaCommunityRowView`
    /// rows separated by the same 0.5pt inset hairlines `renderCommunities`
    /// uses, each opening its community on tap.
    private func renderMetaCommunities(_ items: [MetaCommunityListItem]) {
        metaItems = items
        metaContainer.isHidden = items.isEmpty
        metaContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !items.isEmpty else { return }

        let header = InstanceSectionHeader()
        header.configure(title: "About this instance", count: items.count)
        metaContainer.addArrangedSubview(header)

        let card = makeCard()
        let cardStack = UIStackView()
        cardStack.axis = .vertical
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        pinToCard(cardStack, card, inset: 0)

        for (index, item) in items.enumerated() {
            let rowView = InstanceMetaCommunityRowView(item: item, accent: accent) { [weak self] in
                self?.openMetaCommunity(item)
            }
            cardStack.addArrangedSubview(rowView)
            if index < items.count - 1 {
                let line = UIView()
                line.backgroundColor = .separator
                line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                let insetLine = UIStackView(arrangedSubviews: [line])
                insetLine.isLayoutMarginsRelativeArrangement = true
                insetLine.layoutMargins = .init(top: 0, left: 13, bottom: 0, right: 0)
                cardStack.addArrangedSubview(insetLine)
            }
        }

        metaContainer.addArrangedSubview(card)
    }

    /// Opens a meta community's own screen. The host is derived from the
    /// ITEM's own `communityActorId` URL rather than `record.baseurl` — a meta
    /// community is by definition local to the viewed instance, but resolving
    /// the link from the actorId means it can never disagree with the row that
    /// was actually rendered. `InstanceActorId.init(from:)` accepts an empty
    /// host, so `isValid` must be checked explicitly (mirrors
    /// `InboxViewController.openReminder`'s community branch).
    private func openMetaCommunity(_ item: MetaCommunityListItem) {
        guard
            let window = view.window as? MainWindow,
            let itemHost = URL(string: item.communityActorId)?.host,
            let instance = InstanceActorId(from: "https://\(itemHost)"), instance.isValid
        else { return }
        AppCoordinator.shared.open(URL.SpudInternalLink.community(name: item.name, instance: instance).url, in: window)
    }

    private static func adminsState(_ admins: [SiteAdminRecord], isSuspicious: Bool) -> InstanceAdminsState {
        admins.isEmpty ? (isSuspicious ? .anonymous : .unavailable) : .admins(admins)
    }

    private func renderCommunities(into container: UIStackView, comms: [CommunityListRow]) {
        container.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let countValue: Int? = record.numberOfCommunities > 0 ? Int(record.numberOfCommunities) : nil
        let header = InstanceSectionHeader()
        header.configure(title: "Communities", count: countValue)
        container.addArrangedSubview(header)

        guard !comms.isEmpty else {
            let unavailableCard = makeCard()
            let label = UILabel()
            label.text = "Community list unavailable."
            label.font = .systemFont(ofSize: 13.5)
            label.textColor = .tertiaryLabel
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            unavailableCard.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: unavailableCard.topAnchor, constant: 14),
                label.leadingAnchor.constraint(equalTo: unavailableCard.leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: unavailableCard.trailingAnchor, constant: -14),
                label.bottomAnchor.constraint(equalTo: unavailableCard.bottomAnchor, constant: -14),
            ])
            container.addArrangedSubview(unavailableCard)
            return
        }

        let card = makeCard()
        let cardStack = UIStackView()
        cardStack.axis = .vertical
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        pinToCard(cardStack, card, inset: 0)

        let top3 = Array(comms.prefix(3))
        for (index, row) in top3.enumerated() {
            let rowView = InstanceCommunityRowView(row: row, action: .chevron, joined: false, accent: accent)
            cardStack.addArrangedSubview(rowView)
            if index < top3.count - 1 {
                let line = UIView()
                line.backgroundColor = .separator
                line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                let insetLine = UIStackView(arrangedSubviews: [line])
                insetLine.isLayoutMarginsRelativeArrangement = true
                insetLine.layoutMargins = .init(top: 0, left: 13, bottom: 0, right: 0)
                cardStack.addArrangedSubview(insetLine)
            }
        }

        let footerLine = UIView()
        footerLine.backgroundColor = .separator
        footerLine.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        let insetFooterLine = UIStackView(arrangedSubviews: [footerLine])
        insetFooterLine.isLayoutMarginsRelativeArrangement = true
        insetFooterLine.layoutMargins = .init(top: 0, left: 13, bottom: 0, right: 0)
        cardStack.addArrangedSubview(insetFooterLine)

        let browseLabel = UILabel()
        let totalCount: Int? = record.numberOfCommunities > 0 ? Int(record.numberOfCommunities) : nil
        if let total = totalCount {
            browseLabel.text = "Browse all \(total) communities"
        } else {
            browseLabel.text = "Browse all communities"
        }
        browseLabel.font = .systemFont(ofSize: 14.5)
        browseLabel.textColor = .secondaryLabel
        let footerRow = UIStackView(arrangedSubviews: [browseLabel])
        footerRow.axis = .horizontal
        footerRow.alignment = .center
        footerRow.isLayoutMarginsRelativeArrangement = true
        footerRow.layoutMargins = .init(top: 11, left: 14, bottom: 11, right: 14)
        cardStack.addArrangedSubview(footerRow)

        container.addArrangedSubview(card)
    }

    private func fetch(_ url: URL, into imageView: UIImageView, fallbackLetter: Bool) {
        let stream = imageService.fetch(url)
        let task = Task { [weak self] in
            for await state in stream {
                guard self != nil else { return }
                switch state {
                case .loading:
                    break
                case let .ready(image):
                    imageView.image = image
                    if fallbackLetter { self?.iconLetterLabel.isHidden = true }
                case .failure:
                    if fallbackLetter { self?.iconLetterLabel.isHidden = false }
                }
            }
        }
        imageTasks.append(task)
    }

    // MARK: Notice / action specs

    private struct Notice {
        let color: UIColor
        let symbol: String
        let title: String
        let body: String
    }

    private func noticeFor() -> Notice? {
        if record.isSuspicious {
            let blocked = record.blocksIncoming.map { "\($0) servers" } ?? "many servers"
            return Notice(
                color: .systemRed,
                symbol: "exclamationmark.triangle.fill",
                title: "Blocked by \(blocked) · low trust",
                body: "Most of the network refuses content from this server, and it was registered recently. We don't recommend creating your main account here."
            )
        }
        if record.registrationMode == .closed {
            return Notice(
                color: .secondaryLabel,
                symbol: "lock.fill",
                title: "Signups are closed",
                body: "This server isn't taking new members right now. You can still sign in or browse without an account."
            )
        }
        if record.isNsfw {
            return Notice(
                color: .systemPurple,
                symbol: "eye",
                title: "Adults only · 18+",
                body: "This server hosts NSFW communities. You'll need NSFW content enabled to take part."
            )
        }
        if record.registrationMode == .requireApplication {
            return Notice(
                color: .systemOrange,
                symbol: "doc.text",
                title: "Application required",
                body: "Joining needs a short application the admins review by hand — approval can take a day or two."
            )
        }
        return nil
    }

    private func createButtonSpec() -> (title: String, enabled: Bool) {
        switch record.registrationMode {
        case .closed: ("Signups closed", false)
        case .unknown: ("Create account", false)
        case .requireApplication: ("Apply to join", true)
        case .open: ("Create account", true)
        }
    }

    // MARK: Helpers

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.secondaryGroupedBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        return card
    }

    private func pinToCard(_ subview: UIView, _ card: UIView, inset: CGFloat) {
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            subview.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
            subview.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
            subview.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset),
        ])
    }

    private func hairline(vertical: Bool) -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        if vertical {
            line.widthAnchor.constraint(equalToConstant: 0.5).isActive = true
        } else {
            line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        }
        return line
    }

    private func descriptionText() -> String? {
        if let text = record.descriptionText, !text.isEmpty { return text }
        return "No description provided by this server."
    }

    private func score100() -> Double? {
        guard record.score > 0 else { return nil }
        return min(100, max(0, record.score * 100))
    }

    private func placeholderColor(saturation: CGFloat, brightness: CGFloat) -> UIColor {
        UIColor(hue: hue(for: record.baseurl), saturation: saturation, brightness: brightness, alpha: 1)
    }

    private func hue(for string: String) -> CGFloat {
        let sum = string.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return CGFloat(sum % 360) / 360
    }
}
