//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SwiftUI

struct PreferencesView: View {
    let viewModel: PreferencesViewModel

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink {
                        PreferencesGeneralView(viewModel: viewModel)
                    } label: {
                        Label("General", systemImage: "gear")
                    }

                    NavigationLink { } label: {
                        Label("Appearance", systemImage: "paintpalette")
                    }

                    NavigationLink { } label: {
                        Label("Accounts", systemImage: "person")
                    }
                }

                Section {
                    NavigationLink {
                        PreferencesAboutView(viewModel: viewModel)
                    } label: {
                        Label("About", systemImage: "a")
                    }
                }
            }
        }
    }
}

#Preview {
    PreferencesView(viewModel: PreferencesViewModel())
}
