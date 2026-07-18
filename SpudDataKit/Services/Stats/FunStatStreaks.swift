import Foundation

/// Pure streak math over sorted-unique "yyyy-MM-dd" day strings.
enum FunStatStreaks {
    /// - Parameters:
    ///   - activeDays: distinct days with any recorded activity, ascending.
    ///   - today: the current local day, same format.
    /// - Returns: `current` counts the run ending today or yesterday (no
    ///   activity yet today does not read as broken); `longest` is the best
    ///   run anywhere in history.
    static func compute(activeDays: [String], today: String) -> (current: Int, longest: Int) {
        let dayNumbers = activeDays.compactMap(dayNumber(of:))
        guard !dayNumbers.isEmpty, let todayNumber = dayNumber(of: today) else {
            return (0, 0)
        }

        var longest = 1
        var run = 1
        for (previous, next) in zip(dayNumbers, dayNumbers.dropFirst()) {
            run = (next == previous + 1) ? run + 1 : 1
            longest = max(longest, run)
        }

        // The trailing run is "current" only if it reaches today or yesterday.
        let last = dayNumbers[dayNumbers.count - 1]
        let current = (todayNumber - last) <= 1 ? run : 0
        return (current, longest)
    }

    /// Days since the epoch, parsed in UTC. Day strings are already local
    /// calendar days, so a fixed-zone parse keeps consecutive-ness exact.
    private static func dayNumber(of day: String) -> Int? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day) else { return nil }
        return Int((date.timeIntervalSince1970 / 86400).rounded(.down))
    }
}
