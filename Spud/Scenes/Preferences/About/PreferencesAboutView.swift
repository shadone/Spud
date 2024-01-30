//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import SwiftUI

struct PreferencesLogsView: View {
    @State var text: String = ""

    var body: some View {
        TextEditor(text: $text)
            .ignoresSafeArea()
            .task {
                do {
                    let store = try OSLogStore(scope: .currentProcessIdentifier)
                    let date = Date.now.addingTimeInterval(-1 * 3600)
                    let position = store.position(date: date)

                    text = try store
                        .getEntries(at: position)
                        .compactMap { $0 as? OSLogEntryLog }
                        .filter { $0.subsystem == Bundle.main.bundleIdentifier! }
                        .reduce(into: String()) { partialResult, entry in
                            let date = entry.date.formatted(date: .numeric, time: .standard)
                            let message = "\(date) [\(entry.category)] \(entry.composedMessage)"
                            partialResult += message
                        }
                } catch { }
            }
    }
}

struct PreferencesAboutView: View {
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
                    PreferencesLogsView()
                } label: {
                    Text("Logs")
                }
            }
        }
        .navigationTitle("About")
    }
}

#Preview {
    NavigationView {
        PreferencesAboutView()
    }
}
