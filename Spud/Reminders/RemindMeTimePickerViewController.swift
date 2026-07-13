//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The "Pick a time…" sheet for a custom reminder time: a single
/// `UIDatePicker` (date + time) with Cancel / Set navigation-bar buttons.
/// Presented as a form sheet (works identically on iPhone and iPad) by the
/// caller (`PostReminderDispatching.presentRemindMeTimePicker(for:)`), which
/// also validates the picked date is strictly in the future
/// (`validCustomReminderDate`) before acting on it.
final class RemindMeTimePickerViewController: UIViewController {
    private let onPick: (Date) -> Void

    private lazy var datePicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .inline
        // A custom reminder is inherently future-facing; hide every past
        // minute from the wheel/inline picker instead of relying solely on
        // post-pick validation to reject a stale selection.
        picker.minimumDate = Date()
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
    }()

    /// - Parameter onPick: called with the user's chosen date when they tap
    ///   "Set". Not called on Cancel. The caller is responsible for
    ///   validating/using the date (this sheet only dismisses itself).
    init(onPick: @escaping (Date) -> Void) {
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("Pick a time", comment: "Title of the custom reminder time-picker sheet")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Cancel", comment: "Dismisses the custom reminder time-picker sheet without setting a reminder"),
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Set", comment: "Confirms the custom reminder time and sets the reminder"),
            style: .done,
            target: self,
            action: #selector(setTapped)
        )

        view.addSubview(datePicker)
        NSLayoutConstraint.activate([
            datePicker.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            datePicker.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            datePicker.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            datePicker.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    @objc
    private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc
    private func setTapped() {
        let picked = datePicker.date
        dismiss(animated: true) { [onPick] in
            onPick(picked)
        }
    }
}
