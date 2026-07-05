import Foundation

/// Outcome of a NodeInfo probe. `.unknown` means "could not determine" —
/// NEVER "not Lemmy". Callers treat `.unknown` as fail-open.
public enum NodeInfoDetection: Sendable, Equatable {
    case known(InstanceSoftware, version: String?)
    case unknown
}
