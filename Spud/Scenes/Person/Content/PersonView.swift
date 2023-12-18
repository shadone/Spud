//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SwiftUI

struct PersonNavigationButton: View {
    let action: () -> Void
    let title: String
    let badge: String
    let systemImageName: String

    var body: some View {
        Button(action: { }, label: {
            HStack {
                Label(
                    title: {
                        Text(title)
                            .foregroundColor(Color(uiColor: .label))
                    },
                    icon: {
                        Image(systemName: systemImageName)
                    }
                )

                Spacer()

                Text(badge)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    .background(
                        Capsule(style: .continuous)
                            .foregroundStyle(Color(uiColor: .secondarySystemBackground))
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
        })
    }
}

struct PersonView<ViewModel>: View
    where ViewModel: PersonViewModelType
{
    @StateObject var viewModel: ViewModel

    @State var name: String = ""
    @State var homeInstance: String = ""
    @State var displayName: String?

    @State var numberOfPosts: String = ""

    @State var numberOfComments: String = ""

    @State var accountAge: String = ""

    var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .stroke(Color(uiColor: .secondarySystemFill))
                .frame(width: 64, height: 64)
            Image(systemName: "person")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.tertiary)
                .frame(width: 32, height: 32)
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    avatarPlaceholder

                    VStack(alignment: .leading) {
                        if let displayName {
                            Text(displayName)
                        }
                        Text(name)
                        Text(homeInstance)
                            .font(.footnote)
                    }
                }
            }
            .listRowBackground(EmptyView())

            Section {
                HStack(spacing: 16) {
                    VStack(alignment: .center) {
                        Text(accountAge)
                            .font(.title3)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color(uiColor: .label))
                            .frame(maxWidth: .infinity)
                        Text("Account\nAge")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .textCase(.none)
            }
            .listRowBackground(EmptyView())

            Section {
                PersonNavigationButton(
                    action: { },
                    title: "Posts",
                    badge: numberOfPosts,
                    systemImageName: "doc.richtext"
                )

                PersonNavigationButton(
                    action: { },
                    title: "Comments",
                    badge: numberOfComments,
                    systemImageName: "text.bubble"
                )
            }
        }
        .listStyle(.insetGrouped)
        .onReceive(viewModel.outputs.name) { name = $0 }
        .onReceive(viewModel.outputs.homeInstance) { homeInstance = $0 }
        .onReceive(viewModel.outputs.displayName) { displayName = $0 }
        .onReceive(viewModel.outputs.numberOfPosts) { numberOfPosts = $0 }
        .onReceive(viewModel.outputs.numberOfComments) { numberOfComments = $0 }
        .onReceive(viewModel.outputs.accountAge) { accountAge = $0 }
    }
}

struct PersonView_Preview: PreviewProvider {
    static var previews: some View {
        PersonView(viewModel: PersonViewModelForPreview())
    }
}
