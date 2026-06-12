//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SwiftUI

/// Settings → About → Acknowledgements. Lists the third-party dependencies Spud
/// builds on, grouped into shipping vs test-only, each row leading to the full
/// license text.
struct PreferencesAcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                ForEach(Acknowledgements.shipping) { item in
                    AcknowledgementRow(item: item)
                }
            } footer: {
                Text("Spud is grateful to the open-source projects it builds on.")
            }

            if !Acknowledgements.testOnly.isEmpty {
                Section("Development & testing") {
                    ForEach(Acknowledgements.testOnly) { item in
                        AcknowledgementRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A single dependency row: name, summary, and SPDX license badge.
private struct AcknowledgementRow: View {
    let item: Acknowledgement

    var body: some View {
        NavigationLink {
            AcknowledgementDetailView(item: item)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.body)
                    Spacer()
                    Text(item.licenseName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.name), \(item.licenseName)")
            .accessibilityHint(item.summary)
        }
    }
}

#Preview {
    NavigationStack {
        PreferencesAcknowledgementsView()
    }
}
