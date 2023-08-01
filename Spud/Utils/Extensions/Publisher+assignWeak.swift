//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

extension Publisher where Failure == Never {
    /// This fixes reference cycle with assigned to key paths e.g. `assign(to: \.myKey on: self)`
    ///
    /// The fix is to make a special generic overload for classes (`AnyObject`) and capture the root object weakly.
    ///
    /// The following code in MainWindowController was causing retain cycles:
    ///
    /// ```swift
    ///   viewModel.outputs.searchResults
    ///       .assign(to: \.currentSearchResults, on: self)
    ///       .store(in: &disposables)
    /// ```
    ///
    /// https://forums.swift.org/t/does-assign-to-produce-memory-leaks/29546/9
    /// Code by stefanomondino (https://forums.swift.org/u/stefanomondino)
    func assign<Root: AnyObject>(
        to keyPath: ReferenceWritableKeyPath<Root, Output>,
        on root: Root
    ) -> AnyCancellable {
        sink { [weak root] in
            root?[keyPath: keyPath] = $0
        }
    }
}
