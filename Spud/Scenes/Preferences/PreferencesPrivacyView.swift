//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import SwiftUI

/// Per-category controls for the outbound URL hygiene pipeline, plus a list of
/// privacy front-ends with editable hosts. Pushed from the General > Links
/// section. Reuses the same `PreferencesViewModel` as the rest of settings.
struct PreferencesPrivacyView: View {
    let viewModel: PreferencesViewModel

    private func toggle(_ value: Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        .init { value } set: { set($0) }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Clean Outgoing Links", isOn: toggle(viewModel.urlSanitizerConfig.isEnabled) {
                    viewModel.updateSanitizerEnabled($0)
                })
            } footer: {
                Text("Clean links before opening them. Removes tracking, unwraps redirects, upgrades to HTTPS, and can route links through privacy front-ends.")
            }

            Section {
                Toggle("Strip Tracking Parameters", isOn: toggle(viewModel.urlSanitizerConfig.stripTrackingParams) {
                    viewModel.updateStripTrackingParams($0)
                })
                Toggle("Unwrap Redirectors", isOn: toggle(viewModel.urlSanitizerConfig.unwrapRedirectors) {
                    viewModel.updateUnwrapRedirectors($0)
                })
                Toggle("Upgrade to HTTPS", isOn: toggle(viewModel.urlSanitizerConfig.upgradeToHTTPS) {
                    viewModel.updateUpgradeToHTTPS($0)
                })
                Toggle("De-AMP", isOn: toggle(viewModel.urlSanitizerConfig.deAMP) {
                    viewModel.updateDeAMP($0)
                })
            } header: {
                Text("Cleaning")
            }
            .disabled(!viewModel.urlSanitizerConfig.isEnabled)

            Section {
                Toggle("Redirect to Front-ends", isOn: toggle(viewModel.urlSanitizerConfig.redirectToFrontEnds) {
                    viewModel.updateRedirectToFrontEnds($0)
                })
                ForEach(FrontEndService.allCases, id: \.self) { service in
                    NavigationLink {
                        FrontEndEditView(viewModel: viewModel, service: service)
                    } label: {
                        let setting = viewModel.urlSanitizerConfig.setting(for: service)
                        HStack {
                            Text(FrontEndCatalog.entry(for: service).displayName)
                            Spacer()
                            Text(setting.isEnabled ? setting.host : "Off")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Front-ends")
            } footer: {
                Text("Public front-end instances change often. If one stops working, edit its host or turn it off.")
            }
            .disabled(!viewModel.urlSanitizerConfig.isEnabled)
        }
        .navigationTitle("Privacy")
    }
}

#Preview {
    NavigationStack {
        PreferencesPrivacyView(viewModel: PreferencesViewModel())
    }
}
