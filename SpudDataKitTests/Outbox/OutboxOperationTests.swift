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
}
