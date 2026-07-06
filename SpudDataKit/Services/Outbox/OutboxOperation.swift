import Foundation
import LemmyKit

public enum OutboxEntityType: String, Codable, Sendable {
    case post
    case comment
    /// A Lemmy community. Only the `subscribe` kind targets this entity type.
    case community
}

public enum OutboxKind: String, Codable, Sendable {
    case vote
    case save
    case hide
    /// Delete or restore the user's OWN comment. Toggles the comment's
    /// `isDeleted` state, mirroring `hide`. Idempotent: re-sending the same
    /// `deleted` value is safe.
    case delete
    /// Subscribe to or unsubscribe from a community. Targets the `community`
    /// entity. Idempotent: re-sending the same `follow` value is safe. Its
    /// optimistic projection is 3-valued (see the subscribe baseline codec on
    /// ``CommunitySubscribedState``) even though the desired state is a Bool.
    case subscribe
}

/// The absolute desired state to send to the server. Idempotent: re-sending the
/// same value is safe, which is what lets the outbox retry freely.
public enum OutboxDesiredState: Sendable, Equatable {
    case vote(LikeStatus)
    case save(Bool)
    case hide(Bool)
    /// Desired `deleted` state of the user's own comment (true = deleted).
    case delete(Bool)
    /// Desired subscription state of a community (true = subscribe). The stored
    /// `desiredState` is a Bool; the PRIOR 3-valued state a rollback must restore
    /// lives in the `baseline` column via ``CommunitySubscribedState/outboxBaseline``.
    case subscribe(Bool)

    public var kind: OutboxKind {
        switch self {
        case .vote: .vote
        case .save: .save
        case .hide: .hide
        case .delete: .delete
        case .subscribe: .subscribe
        }
    }

    /// Compact integer encoding for the `desiredState` column. `kind` (stored in
    /// its own column) disambiguates decoding.
    public var encoded: Int64 {
        switch self {
        case let .vote(status): Int64(status.rawValue)
        case let .save(value), let .hide(value), let .delete(value), let .subscribe(value): value ? 1 : 0
        }
    }

    public static func decode(kind: OutboxKind, raw: Int64) -> OutboxDesiredState {
        switch kind {
        case .vote: .vote(LikeStatus(rawValue: Int32(raw)) ?? .neutral)
        case .save: .save(raw != 0)
        case .hide: .hide(raw != 0)
        case .delete: .delete(raw != 0)
        case .subscribe: .subscribe(raw != 0)
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
