//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SwiftUI

/// The Community Data settings screen. Shows when the bundled community/instance
/// directory was last refreshed from data.lemmyverse.net, lets the user refresh
/// it on demand, and configures the automatic refresh (on/off + frequency).
/// Writes flow through ``PreferencesViewModel`` to ``PreferencesService``; the
/// manual refresh drives ``ExplorerServiceType/refreshAll()``.
struct PreferencesCommunityDataView: View {
    @Bindable var viewModel: PreferencesViewModel

    private var autoRefresh: Binding<Bool> {
        .init { viewModel.explorerAutoRefresh } set: { viewModel.updateExplorerAutoRefresh($0) }
    }

    private var refreshInterval: Binding<Preferences.ExplorerRefreshInterval> {
        .init { viewModel.explorerRefreshInterval } set: { viewModel.updateExplorerRefreshInterval($0) }
    }

    private var lastUpdatedText: String {
        guard let date = viewModel.communityDataLastUpdated else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Last Updated")
                    Spacer()
                    Text(lastUpdatedText)
                        .foregroundStyle(.secondary)
                }

                Button {
                    viewModel.refreshCommunityDataNow()
                } label: {
                    HStack {
                        Text("Update Now")
                        Spacer()
                        if viewModel.isRefreshingCommunityData {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isRefreshingCommunityData)
            } footer: {
                if viewModel.communityDataRefreshFailed {
                    Text("Update failed. Check your connection and try again.")
                        .foregroundStyle(.red)
                } else {
                    Text("The community and instance directory ships with the app and refreshes from data.lemmyverse.net.")
                }
            }

            Section {
                Toggle("Automatic Updates", isOn: autoRefresh)

                if viewModel.explorerAutoRefresh {
                    Picker("Frequency", selection: refreshInterval) {
                        ForEach(viewModel.allExplorerRefreshIntervals) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                }
            } header: {
                Text("Automatic Updates")
            } footer: {
                if viewModel.explorerAutoRefresh {
                    Text("Refreshed in the background when you open the app, at most once \(viewModel.explorerRefreshInterval.title.lowercased()).")
                } else {
                    Text("The directory updates only when you tap Update Now.")
                }
            }
        }
        .navigationTitle("Community Data")
    }
}

#Preview {
    NavigationStack {
        PreferencesCommunityDataView(viewModel: PreferencesViewModel())
    }
}
