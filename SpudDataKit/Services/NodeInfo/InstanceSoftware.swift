import Foundation

/// The federated-social software a host runs, as reported by its NodeInfo
/// `software.name`. Recognition is a strong hint, not gospel: forks report
/// their own name and surface as `.other(name)`, which is a first-class,
/// handled outcome — not an error.
public enum InstanceSoftware: Sendable, Equatable {
    case lemmy, piefed, mbin, kbin, mastodon, misskey, pleroma, peertube, friendica, gotosocial
    /// Recognized NodeInfo but an unmodelled software name, preserved verbatim.
    case other(String)

    /// Maps a raw NodeInfo `software.name` (case-insensitive) to a known case,
    /// falling through to `.other` with the original string.
    public init(softwareName: String) {
        switch softwareName.lowercased() {
        case "lemmy": self = .lemmy
        case "piefed": self = .piefed
        case "mbin": self = .mbin
        case "kbin": self = .kbin
        case "mastodon": self = .mastodon
        case "misskey": self = .misskey
        case "pleroma": self = .pleroma
        case "peertube": self = .peertube
        case "friendica": self = .friendica
        case "gotosocial": self = .gotosocial
        default: self = .other(softwareName)
        }
    }
}
