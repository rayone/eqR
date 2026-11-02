import Foundation
import Testing

/// Tests for RecoveryPolicy governing exponential backoff, event-triggered retries,
/// and ongoing audio render health detection.
struct RecoveryPolicyTests {

    @Test func recoverableFailuresBackOffWithoutGivingUp() throws {
        let attempts = [1, 2, 3, 4, 5, 20, 1_000, Int.max]
        let delays = try attempts.map {
            try #require(RecoveryPolicy.retryDelay(forAttempt: $0, isPermanent: false))
        }
        #expect(delays.allSatisfy { $0 > 0 && $0 <= RecoveryPolicy.maxDelay })
        #expect(delays[1] > delays[0])
        #expect(delays[2] > delays[1])
        #expect(delays[5] == delays[6] && delays[6] == delays[7])
    }

    // MARK: - Permanent Failures

    /// Inherently unrecoverable failures (e.g. aggregate device nesting) do not schedule timer retries.
    @Test func permanentFailuresDoNotScheduleRetries() {
        #expect(RecoveryPolicy.retryDelay(forAttempt: 1, isPermanent: true) == nil)
        #expect(RecoveryPolicy.retryDelay(forAttempt: 2, isPermanent: true) == nil)
        #expect(RecoveryPolicy.retryDelay(forAttempt: 10, isPermanent: true) == nil)
    }

    // MARK: - Health & Stall Detection

    /// When callbacks advance, the audio pipeline is healthy.
    @Test func advancingCallbacksAreHealthy() {
        let verdict = RecoveryPolicy.evaluateHealth(
            isRunning: true,
            isIdle: false,
            isPausedForRecording: false,
            isMidTransition: false,
            isCaptureProven: true,
            lastCallbackCount: 100,
            currentCallbackCount: 150,
            secondsSinceLastProgress: RecoveryPolicy.stallThreshold * 2
        )
        #expect(verdict == .healthy)
    }

    /// If callbacks cease advancing and the elapsed duration reaches the stall threshold, declare stall.
    @Test func stalledCallbacksDeclaredAfterThreshold() {
        let verdict = RecoveryPolicy.evaluateHealth(
            isRunning: true,
            isIdle: false,
            isPausedForRecording: false,
            isMidTransition: false,
            isCaptureProven: true,
            lastCallbackCount: 100,
            currentCallbackCount: 100,
            secondsSinceLastProgress: 4.0
        )
        #expect(verdict == .stalled(secondsSinceProgress: 4.0))
    }

    /// A brief lack of progress below the threshold does not trigger a restart.
    @Test func briefCallbackPauseBelowThresholdIsHealthy() {
        let verdict = RecoveryPolicy.evaluateHealth(
            isRunning: true,
            isIdle: false,
            isPausedForRecording: false,
            isMidTransition: false,
            isCaptureProven: true,
            lastCallbackCount: 100,
            currentCallbackCount: 100,
            secondsSinceLastProgress: 2.0
        )
        #expect(verdict == .healthy)
    }

    /// An idle engine intentionally stops the IO proc; missing callbacks while idle is healthy.
    @Test func idleEngineNeverTriggersStall() {
        let verdict = RecoveryPolicy.evaluateHealth(
            isRunning: true,
            isIdle: true,
            isPausedForRecording: false,
            isMidTransition: false,
            isCaptureProven: true,
            lastCallbackCount: 100,
            currentCallbackCount: 100,
            secondsSinceLastProgress: 60.0
        )
        #expect(verdict == .healthy)
    }

    /// An intentional stop, failed state, or ungranted permission never triggers health stall restarts.
    @Test func nonRunningEngineNeverTriggersStall() {
        let verdict = RecoveryPolicy.evaluateHealth(
            isRunning: false,
            isIdle: false,
            isPausedForRecording: false,
            isMidTransition: false,
            isCaptureProven: true,
            lastCallbackCount: 100,
            currentCallbackCount: 100,
            secondsSinceLastProgress: 10.0
        )
        #expect(verdict == .healthy)
    }

    /// Pausing for system audio recording never triggers health stall restarts.
    @Test func recordingPauseNeverTriggersStall() {
        let verdict = RecoveryPolicy.evaluateHealth(
            isRunning: true,
            isIdle: false,
            isPausedForRecording: true,
            isMidTransition: false,
            isCaptureProven: true,
            lastCallbackCount: 100,
            currentCallbackCount: 100,
            secondsSinceLastProgress: 10.0
        )
        #expect(verdict == .healthy)
    }

    /// An in-flight transition (restart or pending proof) never triggers health stall restarts.
    @Test func midTransitionNeverTriggersStall() {
        let verdict = RecoveryPolicy.evaluateHealth(
            isRunning: true,
            isIdle: false,
            isPausedForRecording: false,
            isMidTransition: true,
            isCaptureProven: true,
            lastCallbackCount: 100,
            currentCallbackCount: 100,
            secondsSinceLastProgress: 10.0
        )
        #expect(verdict == .healthy)
    }

    /// Health monitoring is only active after initial proof; capture proof owns tap verification prior.
    @Test func unprovenTapNeverTriggersStall() {
        let verdict = RecoveryPolicy.evaluateHealth(
            isRunning: true,
            isIdle: false,
            isPausedForRecording: false,
            isMidTransition: false,
            isCaptureProven: false,
            lastCallbackCount: 100,
            currentCallbackCount: 100,
            secondsSinceLastProgress: 10.0
        )
        #expect(verdict == .healthy)
    }
}
