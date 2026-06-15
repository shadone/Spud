//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

/// Pure state machine for the per-navigation-controller "forward stack" — the
/// view controllers that were popped and can be restored by the right-edge
/// forward gesture.
///
/// Generic over `AnyObject` so it can be unit tested with plain objects, with no
/// UIKit dependency. The driver feeds it the navigation controller's stack before
/// and after each transition.
enum ForwardStackReducer {
    /// Returns the updated forward stack after a navigation transition.
    ///
    /// - `animated == false`: a structural change (e.g. the split-view column
    ///   handoff via `setViewControllers(animated: false)`). Ignored, so it never
    ///   pollutes the forward stack.
    /// - pop (`newStack` is a strict prefix of `lastStack`): the removed suffix is
    ///   prepended (nearest-ahead first), handling single and multi-level pops.
    /// - append push (`lastStack` is a strict prefix of `newStack`): if exactly one
    ///   controller was added and it is `forwardStack.first`, that was our restore
    ///   so it is consumed; otherwise this is genuinely new navigation and the
    ///   stack is cleared (browser semantics).
    /// - identical stacks: unchanged (e.g. a cancelled interactive restore).
    /// - anything else (reshuffle / wholesale replace): cleared.
    static func reduce<Element: AnyObject>(
        forwardStack: [Element],
        lastStack: [Element],
        newStack: [Element],
        animated: Bool
    ) -> [Element] {
        guard animated else { return forwardStack }

        if newStack.count < lastStack.count, isPrefix(newStack, of: lastStack) {
            let removed = Array(lastStack[newStack.count...])
            return removed + forwardStack
        }

        if newStack.count > lastStack.count, isPrefix(lastStack, of: newStack) {
            if newStack.count == lastStack.count + 1,
               let restored = forwardStack.first,
               newStack.last === restored
            {
                return Array(forwardStack.dropFirst())
            }
            return []
        }

        if newStack.count == lastStack.count, isPrefix(newStack, of: lastStack) {
            return forwardStack
        }

        return []
    }

    private static func isPrefix<Element: AnyObject>(_ candidate: [Element], of stack: [Element]) -> Bool {
        guard candidate.count <= stack.count else { return false }
        for index in candidate.indices where candidate[index] !== stack[index] {
            return false
        }
        return true
    }
}
