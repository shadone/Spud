import LemmyKit
import Testing
@testable import SpudDataKit

struct OutboxOperationTests {
    @Test
    func voteEncodingRoundTrips() {
        for status in [LikeStatus.liked, .disliked, .neutral] {
            let state = OutboxDesiredState.vote(status)
            #expect(state.kind == .vote)
            let decoded = OutboxDesiredState.decode(kind: .vote, raw: state.encoded)
            #expect(decoded == state)
        }
    }

    @Test
    func saveAndHideEncodingRoundTrips() {
        for value in [true, false] {
            let save = OutboxDesiredState.save(value)
            #expect(OutboxDesiredState.decode(kind: .save, raw: save.encoded) == save)
            let hide = OutboxDesiredState.hide(value)
            #expect(OutboxDesiredState.decode(kind: .hide, raw: hide.encoded) == hide)
        }
    }

    @Test
    func operationDerivesKindFromDesiredState() {
        let op = OutboxOperation(entityType: .post, entityServerId: 7, desiredState: .save(true))
        #expect(op.kind == .save)
    }

    @Test
    func subscribeEncodingRoundTrips() {
        for value in [true, false] {
            let sub = OutboxDesiredState.subscribe(value)
            #expect(sub.kind == .subscribe)
            #expect(OutboxDesiredState.decode(kind: .subscribe, raw: sub.encoded) == sub)
        }
    }

    @Test
    func subscribeOperationTargetsCommunityEntity() {
        let op = OutboxOperation(entityType: .community, entityServerId: 3, desiredState: .subscribe(true))
        #expect(op.kind == .subscribe)
        #expect(op.entityType == .community)
    }

    /// The subscribe baseline is a `CommunitySubscribedState` (rollback must be
    /// able to restore an in-flight request, not just on/off), so it uses a
    /// dedicated codec distinct from the 2-valued desired-state encoding.
    /// Documented raw mapping: 0 = notSubscribed, 1 = subscribed, 2 = pending,
    /// 3 = approvalRequired, 4 = denied.
    @Test
    func subscribeBaselineCodecRoundTripsAllStates() {
        #expect(CommunitySubscribedState.notSubscribed.outboxBaseline == 0)
        #expect(CommunitySubscribedState.subscribed.outboxBaseline == 1)
        #expect(CommunitySubscribedState.pending.outboxBaseline == 2)
        #expect(CommunitySubscribedState.approvalRequired.outboxBaseline == 3)
        #expect(CommunitySubscribedState.denied.outboxBaseline == 4)
        for state in [
            CommunitySubscribedState.notSubscribed, .subscribed, .pending, .approvalRequired, .denied,
        ] {
            #expect(CommunitySubscribedState(outboxBaseline: state.outboxBaseline) == state)
        }
        // A missing baseline (nil) and any unknown value decode to notSubscribed.
        #expect(CommunitySubscribedState(outboxBaseline: nil) == .notSubscribed)
        #expect(CommunitySubscribedState(outboxBaseline: 99) == .notSubscribed)
    }

    /// Backward-compat: baselines persisted by the original 3-state codec only
    /// ever hold 0/1/2, and those raw codes must still decode to exactly the same
    /// states after the codec was widened (widening only ADDED codes 3/4).
    @Test
    func subscribeBaselineCodecDecodesLegacyCodes() {
        #expect(CommunitySubscribedState(outboxBaseline: 0) == .notSubscribed)
        #expect(CommunitySubscribedState(outboxBaseline: 1) == .subscribed)
        #expect(CommunitySubscribedState(outboxBaseline: 2) == .pending)
    }
}
