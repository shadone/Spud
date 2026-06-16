//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Pure dwell bookkeeping for "seen on screen" capture. The view controller
/// reports appear/disappear events and periodic flushes; the tracker decides
/// which posts have been continuously visible past `threshold`, and reports
/// each post at most once.
struct SeenDwellTracker {
    let threshold: TimeInterval
    private var appearedAt: [Int64: Date] = [:]
    private var alreadySeen: Set<Int64> = []

    init(threshold: TimeInterval) {
        self.threshold = threshold
    }

    mutating func didAppear(serverPostId: Int64, at now: Date) {
        if appearedAt[serverPostId] == nil {
            appearedAt[serverPostId] = now
        }
    }

    /// Records a disappearance. Returns the post id if it dwelled past the
    /// threshold and hasn't been reported yet, else nil.
    mutating func didDisappear(serverPostId: Int64, at now: Date) -> Int64? {
        guard let start = appearedAt.removeValue(forKey: serverPostId) else { return nil }
        guard !alreadySeen.contains(serverPostId) else { return nil }
        if now.timeIntervalSince(start) >= threshold {
            alreadySeen.insert(serverPostId)
            return serverPostId
        }
        return nil
    }

    /// Returns posts currently on screen that have dwelled past the threshold
    /// and haven't been reported yet (marking them reported). Call periodically
    /// while the feed is stationary.
    mutating func flushSeen(at now: Date) -> [Int64] {
        var result: [Int64] = []
        for (postId, start) in appearedAt where !alreadySeen.contains(postId) {
            if now.timeIntervalSince(start) >= threshold {
                alreadySeen.insert(postId)
                result.append(postId)
            }
        }
        return result
    }
}
