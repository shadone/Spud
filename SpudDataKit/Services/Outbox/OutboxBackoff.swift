import Foundation

/// Shared retry back-off curve for BOTH durable outboxes (`OutboxService` /
/// `ComposerOutboxService`): exponential doubling from 2s, capped at 300s.
/// The two outboxes intentionally share failure classification
/// (`OutboxFailureClass`) and pacing — tune the curve HERE so they cannot
/// silently diverge.
public enum OutboxBackoff {
    public static func delay(attempts: Int64) -> Double {
        min(2.0 * pow(2.0, Double(max(0, attempts - 1))), 300)
    }
}
