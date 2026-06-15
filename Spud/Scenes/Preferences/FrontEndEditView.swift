//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import SwiftUI

/// Enable/disable and host editing for a single privacy front-end.
struct FrontEndEditView: View {
    let viewModel: PreferencesViewModel
    let service: FrontEndService

    @State private var host: String = ""

    private var setting: FrontEndConfig {
        viewModel.urlSanitizerConfig.setting(for: service)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: .init {
                    setting.isEnabled
                } set: {
                    viewModel.updateFrontEndEnabled(service, $0)
                })
            }

            Section {
                TextField("Host", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit { viewModel.updateFrontEndHost(service, host) }
                Button("Reset to Default") {
                    viewModel.resetFrontEndHost(service)
                    host = setting.host
                }
            } header: {
                Text("Front-end Host")
            } footer: {
                Text("Links to \(sourceDomainsText) will be rewritten to this host.")
            }
        }
        .navigationTitle(FrontEndCatalog.entry(for: service).displayName)
        .onAppear { host = setting.host }
        .onDisappear { viewModel.updateFrontEndHost(service, host) }
    }

    private var sourceDomainsText: String {
        FrontEndCatalog.entry(for: service).sourceDomains.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        FrontEndEditView(viewModel: PreferencesViewModel(), service: .twitter)
    }
}
