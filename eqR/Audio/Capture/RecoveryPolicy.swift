import Foundation

/// Pure policy decisions for engine recovery, backoff, and render health monitoring.
///
/// Keeps AudioEngine free of policy math and state machines, making all recovery
/// behavior deterministically testable without requiring CoreAudio hardware or
/// audio devices.
enum RecoveryPolicy {

    // MARK: - Backoff Configuration

    /// Initial retry delay after the first failure.
    static let initialDelay: TimeInterval = 2.0

    /// Maximum cap for sparse exponential backoff.
    ///
    /// Sparse retries keep a recoverable failure from requiring a relaunch.
    static let maxDelay: TimeInterval = 30.0

    /// Exponential backoff multiplier.
    static let backoffMultiplier: Double = 2.0

    /// Stall detection threshold in seconds of missing render progress.
    ///
    /// CoreAudio IO callbacks fire every ~10-12 ms when the device is running.
    /// 4.0 seconds without callback progression while actively running indicates
    /// a stalled pipeline (e.g. frozen coreaudiod or stalled aggregate clock).
    static let stallThreshold: TimeInterval = 4.0

    // MARK: - Event Triggers

    /// External events that trigger an immediate retry or engine rebuild.
    enum TriggerEvent: Equatable {
        /// Default output device changed in system preferences or hardware switch.
        case defaultDeviceChanged
        /// CoreAudio daemon (coreaudiod) crashed or reset.
        case serviceRestarted
        /// Aggregate output stream configuration / channel layout changed.
        case streamConfigurationChanged
        /// Device sample rate renegotiated and settled.
        case sampleRateChanged
        /// System woke from sleep.
        case systemWoke
        /// Excluded apps list modified by user.
        case excludedAppsChanged
        /// Active audio rendering stalled.
        case stalledCallback
    }

    /// The settling delay appropriate for an event before rebuilding the engine.
    static func settleDelay(for event: TriggerEvent) -> TimeInterval {
        switch event {
        case .defaultDeviceChanged:
            // Hardware needs half a second to settle stream configuration.
            return 0.5
        case .serviceRestarted:
            // Give coreaudiod half a second to re-register devices and streams.
            return 0.5
        case .streamConfigurationChanged:
            return 0.3
        case .systemWoke:
            return 1.0
        case .sampleRateChanged, .excludedAppsChanged, .stalledCallback:
            return 0.0
        }
    }

    // MARK: - Retry Delay Decision

    /// Calculates the next retry delay for a given attempt.
    ///
    /// - Parameters:
    ///   - attempt: 1-based attempt number (1 for the first retry).
    ///   - isPermanent: whether the failure is intrinsically permanent (e.g. aggregate nesting).
    /// - Returns: delay in seconds, or `nil` if the failure is permanent.
    static func retryDelay(forAttempt attempt: Int, isPermanent: Bool) -> TimeInterval? {
        guard !isPermanent else { return nil }
        guard attempt > 0 else { return initialDelay }
        let exponent = Double(min(attempt - 1, 5))
        let delay = initialDelay * pow(backoffMultiplier, exponent)
        return min(delay, maxDelay)
    }

    // MARK: - Health Verdict

    enum HealthVerdict: Equatable {
        case healthy
        case stalled(secondsSinceProgress: TimeInterval)
    }

    /// Evaluates ongoing render pipeline health.
    ///
    /// Silence alone does NOT trigger a stall, because CoreAudio continues invoking the IO proc
    /// with zeroed buffers during silence, advancing `callbackCount`.
    /// Idle, awaiting permission, mid-transition, and paused states are explicitly excluded.
    ///
    /// - Parameters:
    ///   - isRunning: whether engine status is currently `.running`.
    ///   - isIdle: whether engine is in idle power-saving state.
    ///   - isPausedForRecording: whether engine has stepped aside for recording.
    ///   - isMidTransition: whether a restart or capture proof is in flight.
    ///   - isCaptureProven: whether initial capture proof has succeeded.
    ///   - lastCallbackCount: previous callback count observed, if any.
    ///   - currentCallbackCount: current callback count observed.
    ///   - secondsSinceLastProgress: elapsed seconds without callback progression.
    ///   - stallThreshold: maximum allowed stall duration before declaring stalled.
    /// - Returns: `.healthy` or `.stalled`.
    static func evaluateHealth(
        isRunning: Bool,
        isIdle: Bool,
        isPausedForRecording: Bool,
        isMidTransition: Bool,
        isCaptureProven: Bool,
        lastCallbackCount: UInt64?,
        currentCallbackCount: UInt64?,
        secondsSinceLastProgress: TimeInterval,
        stallThreshold: TimeInterval = stallThreshold
    ) -> HealthVerdict {
        // Excluded states: when engine is not actively supposed to be rendering.
        guard isRunning, !isIdle, !isPausedForRecording, !isMidTransition else {
            return .healthy
        }
        // Health check only monitors ongoing health after initial capture proof.
        guard isCaptureProven else {
            return .healthy
        }
        // If callbacks are progressing, the pipeline is healthy.
        if let current = currentCallbackCount, let last = lastCallbackCount, current != last {
            return .healthy
        }
        // If callbacks have ceased advancing for the threshold duration, declare stall.
        if secondsSinceLastProgress >= stallThreshold {
            return .stalled(secondsSinceProgress: secondsSinceLastProgress)
        }
        return .healthy
    }
}
