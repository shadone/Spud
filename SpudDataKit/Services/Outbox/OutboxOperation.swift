import Foundation
import LemmyKit

public enum OutboxEntityType: String, Codable, Sendable {
    case post
    case comment
}

public enum OutboxKind: String, Codable, Sendable {
    case vote
    case save
    case hide
    /// Delete or restore the user's OWN comment. Toggles the comment's
    /// `isDeleted` state, mirroring `hide`. Idempotent: re-sending the same
    /// `deleted` value is safe.
    case delete
}

/// The absolute desired state to send to the server. Idempotent: re-sending the
/// same value is safe, which is what lets the outbox retry freely.
public enum OutboxDesiredState: Sendable, Equatable {
    case vote(LikeStatus)
    case save(Bool)
    case hide(Bool)
    /// Desired `deleted` state of the user's own comment (true = deleted).
    case delete(Bool)

    public var kind: OutboxKind {
        switch self {
        case .vote: .vote
        case .save: .save
        case .hide: .hide
        case .delete: .delete
        }
    }

    /// Compact integer encoding for the `desiredState` column. `kind` (stored in
    /// its own column) disambiguates decoding.
    public var encoded: Int64 {
        switch self {
        case let .vote(status): Int64(status.rawValue)
        case let .save(value), let .hide(value), let .delete(value): value ? 1 : 0
        }
    }

    public static func decode(kind: OutboxKind, raw: Int64) -> OutboxDesiredState {
        switch kind {
        case .vote: .vote(LikeStatus(rawValue: Int32(raw)) ?? .neutral)
        case .save: .save(raw != 0)
        case .hide: .hide(raw != 0)
        case .delete: .delete(raw != 0)
        }
    }
}

public struct OutboxOperation: Sendable, Equatable {
    public let entityType: OutboxEntityType
    public let entityServerId: Int64
    public let desiredState: OutboxDesiredState

    public var kind: OutboxKind {
        desiredState.kind
    }

    public init(entityType: OutboxEntityType, entityServerId: Int64, desiredState: OutboxDesiredState) {
        self.entityType = entityType
        self.entityServerId = entityServerId
        self.desiredState = desiredState
    }
}
