//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SwiftUI

// MARK: - Logs host

/// Settings → About → Logs screen.
///
/// Hosts two tabs via a segmented `Picker`:
/// - **Event Log** (structured `DiagnosticEventRecord` rows drawn from GRDB) —
///   shown only when `diagnostics` and `appDatabase` are non-nil; hidden in previews.
/// - **System Log** (raw OSLog tail for this process, fixed formatting) — always available.
///
/// This replaces the old `PreferencesLogsView` which had several bugs: no
/// separator between entries, an empty `catch {}` (blank screen on error), editable
/// text, and a hard-coded 1-hour window.
private struct LogsHostView: View {
    let diagnostics: DiagnosticLogging?
    let appDatabase: AppDatabase?

    private enum Tab: Hashable {
        case eventLog
        case systemLog
    }

    @State private var selectedTab: Tab = .eventLog

    var body: some View {
        VStack(spacing: 0) {
            if diagnostics != nil, appDatabase != nil {
                // Both tabs are available — show the segmented picker.
                Picker("Log type", selection: $selectedTab) {
                    Text("Event Log").tag(Tab.eventLog)
                    Text("System Log").tag(Tab.systemLog)
                }
                .pickerStyle(.segmented)
                .padding()
                Divider()
                tabContent
            } else {
                // Preview or missing dependencies: only the System Log tab is usable.
                SystemLogView()
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .eventLog:
            if let diagnostics, let appDatabase {
                // DiagnosticLogView sets its own navigation title ("Event Log") in
                // its toolbar; suppress the host's title override in that tab so the
                // two titles don't stack.
                DiagnosticLogView(diagnostics: diagnostics, appDatabase: appDatabase)
                    .navigationTitle("Event Log")
            }
        case .systemLog:
            SystemLogView()
        }
    }
}

// MARK: - About view

struct PreferencesAboutView: View {
    let viewModel: PreferencesViewModel

    var body: some View {
        Form {
            VStack {
                HStack(alignment: .center) {
                    Text("Hello world :o)")
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .background(Color(UIColor.systemGroupedBackground))

            Section {
                NavigationLink {
                    PreferencesAcknowledgementsView()
                } label: {
                    Label("Acknowledgements", systemImage: "heart.text.square")
                        .labelStyle(.titleOnly)
                }
            }

            Section {
                NavigationLink {
                    LogsHostView(
                        diagnostics: viewModel.diagnostics,
                        appDatabase: viewModel.logsAppDatabase
                    )
                } label: {
                    Text("Logs")
                }
            }

            Section {
                HStack {
                    Text("Size")
                    Spacer()
                    Text(viewModel.storageSize)
                }

                if #available(iOS 16.0, *) {
                    ShareLink("Export Backup", item: viewModel.storageFileUrl)
                        .labelStyle(.titleOnly)
                }

            } header: {
                Text("Storage")
            }
        }
        .navigationTitle("About")
    }
}

#Preview {
    NavigationView {
        PreferencesAboutView(viewModel: PreferencesViewModel())
    }
}
