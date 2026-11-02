import Accelerate
import Foundation

/// The equalizer itself: a flat chain of biquads, run over every routed channel.
///
/// Everything about *where* audio comes from and goes to belongs to
/// `BufferRouter`; everything about what happens to the samples in between is
/// here. Kept apart because they fail differently — a routing mistake sends
/// audio to the wrong place, a filter mistake makes it the wrong shape, and
/// telling those apart in one 500 line type was harder than it needed to be.
///
/// The chain has no notion of bands, sliders, or ladders. It receives whatever
/// the user's editing surfaces produced and runs every entry the same way, which
/// is what makes eqR's two editors two views of one equalizer.
///
/// A struct, stored inline by the processor. Every field here is touched on the
/// audio thread, where a class would add a retain and an indirection per block.
struct FilterBank {

    /// Eleven ladder slots plus `BuiltInProfiles.maxFreeFilters`, with room left
    /// for automatically generated processing later. Each filter is one more
    /// pass over the buffer, so this is a real budget.
    static let maxFilters = 32

    /// How long a filter or preamp edit takes to travel, so a profile switch or
    /// slider drag is a fade rather than a step.
    private static let smoothingSeconds = 0.05

    /// One filter, as the main thread describes it.
    struct Parameters: Equatable {
        var kind = EQFilter.Kind.bell
        var frequency = 1_000.0
        var gain = 0.0
        var q = 1.0
        var isEnabled = true

        init() {}

        init(_ filter: EQFilter) {
            kind = filter.kind
            frequency = filter.frequency
            gain = filter.gain
            q = filter.q
            isEnabled = filter.isEnabled
        }

    }

    /// One filter slot, holding current state, active transition, and queued edits.
    private struct State {
        var parameters = Parameters()
        var filter = Biquad.identity
        var isIdentity = true

        // Active transition along the persistent integer frame timeline:
        var isTransitioning = false
        var targetParameters = Parameters()
        var targetFilter = Biquad.identity
        var targetIsIdentity = true
        var transitionElapsedFrames = 0
        var transitionTotalFrames = 0

        // Queued edit: if an edit arrives during an active fade, it is queued here
        // to avoid needing a 3rd parallel chain.
        var hasQueuedEdit = false
        var queuedParameters = Parameters()

        // Per-block snapshot (prepared in advance, read by process across channels):
        var blockTransitionIsActive = false
        var blockTransitionElapsed = 0
        var blockTransitionTotal = 0
    }

    private(set) var sampleRate = 44_100.0

    private var filters = [State](repeating: State(), count: FilterBank.maxFilters)
    private var count = 0
    private var configuredCount = 0

    /// Delay lines for every filter and channel, flat and allocated once:
    /// filter-major, then channel, then the two states. Two per filter per
    /// channel is what transposed direct form II needs.
    private var delays = [Double](
        repeating: 0, count: FilterBank.maxFilters * EQProcessor.maxChannels * 2)

    /// Parallel transition delay lines, matching `delays` layout. Active only
    /// while crossfading between filter shapes or states, maintaining zero-latency
    /// operation without allocating or reallocating buffers mid-render.
    private var transitionDelays = [Double](
        repeating: 0, count: FilterBank.maxFilters * EQProcessor.maxChannels * 2)

    /// Output trim, smoothed continuously so dragging the preamp slider
    /// produces an uninterrupted sample ramp rather than block-edge steps.
    private var targetPreampLinear = 1.0
    private var currentPreampLinear = 1.0

    private var preampIsRamping = false
    private var preampBaseLinear = 1.0
    private var preampRampTargetLinear = 1.0
    private var preampRampElapsedFrames = 0
    private var preampRampTotalFrames = 0

    // Per-block preamp snapshot:
    private var blockPreampIsRamping = false
    private var blockPreampBase = 1.0
    private var blockPreampTarget = 1.0
    private var blockPreampElapsed = 0
    private var blockPreampTotal = 0

    // MARK: - Configuration (render thread, from staged values)

    /// Adopts a new rate, returning whether it was one. Rebuilds the newest configured
    /// state (adopting queued edits if present) and drops delay lines.
    mutating func setSampleRate(_ rate: Double) -> Bool {
        guard rate != sampleRate else { return false }
        sampleRate = rate
        for i in 0..<Self.maxFilters {
            if filters[i].hasQueuedEdit {
                filters[i].parameters = filters[i].queuedParameters
            } else if filters[i].isTransitioning {
                filters[i].parameters = filters[i].targetParameters
            }
            filters[i].hasQueuedEdit = false
            filters[i].isTransitioning = false
            filters[i].transitionElapsedFrames = 0
            filters[i].transitionTotalFrames = 0
            filters[i].blockTransitionIsActive = false
            filters[i].blockTransitionElapsed = 0
            filters[i].blockTransitionTotal = 0

            filters[i].filter = makeBiquad(from: filters[i].parameters)
            filters[i].isIdentity = (filters[i].filter == .identity)
            resetDelays(filter: i)
            resetTransitionDelays(filter: i)
        }

        currentPreampLinear = targetPreampLinear
        preampIsRamping = false
        preampRampElapsedFrames = 0
        preampRampTotalFrames = 0
        blockPreampIsRamping = false
        blockPreampBase = targetPreampLinear
        blockPreampTarget = targetPreampLinear
        return true
    }

    /// Updates filter specifications from staged parameters. Active transitions complete
    /// or queue newer edits to maintain continuous sample crossfades along the timeline.
    mutating func setFilters(_ staged: [Parameters], count newCount: Int) {
        let clampedCount = min(newCount, Self.maxFilters)
        configuredCount = clampedCount
        let totalFrames = max(1, Int(sampleRate * Self.smoothingSeconds))

        for i in 0..<clampedCount {
            configureSlot(i, with: staged[i], totalFrames: totalFrames)
        }
        retireRemovedSlots(from: clampedCount, totalFrames: totalFrames)
        updateActiveCount(from: clampedCount)
    }

    private mutating func configureSlot(_ i: Int, with params: Parameters, totalFrames: Int) {
        let desiredFilter = makeBiquad(from: params)

        if filters[i].isTransitioning {
            if filters[i].targetParameters == params && filters[i].targetFilter == desiredFilter {
                filters[i].hasQueuedEdit = false
                return
            }
            filters[i].hasQueuedEdit = true
            filters[i].queuedParameters = params
        } else {
            if filters[i].parameters == params && filters[i].filter == desiredFilter {
                return
            }
            startTransition(
                i, to: params, filter: desiredFilter, isIdentity: (desiredFilter == .identity),
                totalFrames: totalFrames)
        }
    }

    private mutating func retireRemovedSlots(from start: Int, totalFrames: Int) {
        for i in start..<Self.maxFilters {
            guard i < count else {
                filters[i] = State()
                resetDelays(filter: i)
                resetTransitionDelays(filter: i)
                continue
            }

            if filters[i].isTransitioning {
                if filters[i].targetIsIdentity {
                    filters[i].hasQueuedEdit = false
                    continue
                }
                filters[i].hasQueuedEdit = true
                filters[i].queuedParameters = Parameters()
            } else if !filters[i].isIdentity {
                startTransition(
                    i, to: Parameters(), filter: .identity, isIdentity: true,
                    totalFrames: totalFrames)
            } else {
                filters[i] = State()
                resetDelays(filter: i)
                resetTransitionDelays(filter: i)
            }
        }
    }

    private mutating func updateActiveCount(from configured: Int) {
        var highestActive = configured
        for i in configured..<Self.maxFilters {
            if filters[i].isTransitioning || filters[i].hasQueuedEdit || !filters[i].isIdentity {
                highestActive = i + 1
            }
        }
        count = highestActive
    }

    private mutating func startTransition(
        _ i: Int, to params: Parameters, filter: Biquad, isIdentity: Bool, totalFrames: Int
    ) {
        filters[i].isTransitioning = true
        filters[i].targetParameters = params
        filters[i].targetFilter = filter
        filters[i].targetIsIdentity = isIdentity
        filters[i].transitionElapsedFrames = 0
        filters[i].transitionTotalFrames = totalFrames
        filters[i].hasQueuedEdit = false
        filters[i].blockTransitionIsActive = false
        filters[i].blockTransitionElapsed = 0
        filters[i].blockTransitionTotal = 0
        resetTransitionDelays(filter: i)
    }

    private mutating func commitTransition(_ i: Int) {
        filters[i].filter = filters[i].targetFilter
        filters[i].parameters = filters[i].targetParameters
        filters[i].isIdentity = filters[i].targetIsIdentity

        if filters[i].isIdentity {
            resetDelays(filter: i)
            resetTransitionDelays(filter: i)
        } else {
            copyTransitionDelaysToPrimary(filter: i)
            resetTransitionDelays(filter: i)
        }

        if filters[i].hasQueuedEdit {
            let nextParams = filters[i].queuedParameters
            let nextFilter = makeBiquad(from: nextParams)
            filters[i].hasQueuedEdit = false

            if filters[i].parameters == nextParams && filters[i].filter == nextFilter {
                filters[i].isTransitioning = false
                filters[i].transitionElapsedFrames = 0
                filters[i].transitionTotalFrames = 0
            } else {
                startTransition(
                    i, to: nextParams, filter: nextFilter, isIdentity: (nextFilter == .identity),
                    totalFrames: max(1, Int(sampleRate * Self.smoothingSeconds)))
            }
        } else {
            filters[i].isTransitioning = false
            filters[i].transitionElapsedFrames = 0
            filters[i].transitionTotalFrames = 0
        }
    }

    mutating func setPreamp(dB: Double) {
        let newTarget = pow(10.0, dB / 20.0)
        guard newTarget != targetPreampLinear else { return }
        targetPreampLinear = newTarget

        let totalFrames = max(1, Int(sampleRate * Self.smoothingSeconds))
        if preampIsRamping {
            let fraction = min(1.0, Double(preampRampElapsedFrames) / Double(preampRampTotalFrames))
            preampBaseLinear =
                preampBaseLinear + (preampRampTargetLinear - preampBaseLinear) * fraction
        } else {
            preampBaseLinear = currentPreampLinear
        }

        preampRampTargetLinear = newTarget
        preampRampElapsedFrames = 0
        preampRampTotalFrames = totalFrames
        preampIsRamping = true
    }

    /// Drops every delay line and immediately settles transitions to the newest configured state
    /// (adopting queued edits if present), avoiding reverting recent user settings on resume.
    mutating func resetAll() {
        for i in 0..<delays.count { delays[i] = 0 }
        for i in 0..<transitionDelays.count { transitionDelays[i] = 0 }
        currentPreampLinear = targetPreampLinear
        preampIsRamping = false
        preampRampElapsedFrames = 0
        preampRampTotalFrames = 0
        blockPreampIsRamping = false
        blockPreampBase = targetPreampLinear
        blockPreampTarget = targetPreampLinear

        for i in 0..<count {
            if filters[i].hasQueuedEdit {
                filters[i].parameters = filters[i].queuedParameters
                filters[i].filter = makeBiquad(from: filters[i].parameters)
                filters[i].isIdentity = (filters[i].filter == .identity)
            } else if filters[i].isTransitioning {
                filters[i].parameters = filters[i].targetParameters
                filters[i].filter = filters[i].targetFilter
                filters[i].isIdentity = filters[i].targetIsIdentity
            }
            filters[i].hasQueuedEdit = false
            filters[i].isTransitioning = false
            filters[i].transitionElapsedFrames = 0
            filters[i].transitionTotalFrames = 0
            filters[i].blockTransitionIsActive = false
            filters[i].blockTransitionElapsed = 0
            filters[i].blockTransitionTotal = 0
            resetDelays(filter: i)
            resetTransitionDelays(filter: i)
        }
    }

    // MARK: - Running (render thread)

    /// Determines the maximum number of frames that can be rendered in the current segment
    /// before any active transition or preamp ramp completes. Commits completed transitions
    /// and shrinks retired slots before calculating the segment size.
    mutating func nextSegmentFrames(maximum: Int) -> Int {
        guard maximum > 0 else { return 0 }
        commitCompletedTransitions()
        shrinkRetiredCount()

        var limit = maximum

        if preampIsRamping {
            let remaining = preampRampTotalFrames - preampRampElapsedFrames
            if remaining > 0 && remaining < limit {
                limit = remaining
            }
        }

        for i in 0..<count {
            if filters[i].isTransitioning {
                let remaining =
                    filters[i].transitionTotalFrames - filters[i].transitionElapsedFrames
                if remaining > 0 && remaining < limit {
                    limit = remaining
                }
            }
        }

        return max(1, limit)
    }

    /// Prepares ramp trajectories for both the preamp trim and any transitioning
    /// filters for the upcoming block along a persistent integer frame timeline.
    mutating func advance(frames: Int) {
        guard frames > 0 else { return }
        commitCompletedTransitions()
        shrinkRetiredCount()
        advancePreamp(frames: frames)
        advanceTransitions(frames: frames)
    }

    private mutating func commitCompletedTransitions() {
        if preampIsRamping && preampRampElapsedFrames >= preampRampTotalFrames {
            preampIsRamping = false
            currentPreampLinear = preampRampTargetLinear
            preampRampElapsedFrames = 0
            preampRampTotalFrames = 0
        }

        for i in 0..<count {
            if filters[i].isTransitioning
                && filters[i].transitionElapsedFrames >= filters[i].transitionTotalFrames
            {
                commitTransition(i)
            }
        }
    }

    private mutating func shrinkRetiredCount() {
        while count > configuredCount && !filters[count - 1].isTransitioning
            && !filters[count - 1].hasQueuedEdit && filters[count - 1].isIdentity
        {
            count -= 1
        }
    }

    private mutating func advancePreamp(frames: Int) {
        blockPreampIsRamping = preampIsRamping
        blockPreampBase = preampBaseLinear
        blockPreampTarget = preampRampTargetLinear
        blockPreampElapsed = preampRampElapsedFrames
        blockPreampTotal = preampRampTotalFrames

        if preampIsRamping {
            preampRampElapsedFrames += frames
        }
    }

    private mutating func advanceTransitions(frames: Int) {
        for i in 0..<count {
            if filters[i].isTransitioning {
                filters[i].blockTransitionIsActive = true
                filters[i].blockTransitionElapsed = filters[i].transitionElapsedFrames
                filters[i].blockTransitionTotal = filters[i].transitionTotalFrames
                filters[i].transitionElapsedFrames += frames
            } else {
                filters[i].blockTransitionIsActive = false
                filters[i].blockTransitionElapsed = 0
                filters[i].blockTransitionTotal = 0
            }
        }
    }

    /// Runs the whole chain over one channel, in place. Steady identity filters are
    /// skipped completely. Transitioning filters crossfade between parallel biquad states.
    mutating func process(
        _ samples: UnsafeMutablePointer<Float>, stride: Int, frames: Int, channel: Int
    ) {
        guard frames > 0, channel < EQProcessor.maxChannels else { return }

        for i in 0..<count {
            let slot = delayIndex(filter: i, channel: channel)
            if !filters[i].blockTransitionIsActive {
                guard !filters[i].isIdentity else { continue }
                var z1 = delays[slot]
                var z2 = delays[slot + 1]
                Self.processBiquad(
                    filters[i].filter,
                    samples: samples,
                    stride: stride,
                    frames: frames,
                    z1: &z1,
                    z2: &z2
                )
                delays[slot] = z1
                delays[slot + 1] = z2
            } else {
                processTransition(
                    i,
                    slot: slot,
                    samples: samples,
                    stride: stride,
                    frames: frames
                )
            }
        }
    }

    @inline(__always)
    private static func processBiquad(
        _ filter: Biquad,
        samples: UnsafeMutablePointer<Float>,
        stride: Int,
        frames: Int,
        z1: inout Double,
        z2: inout Double
    ) {
        let b0 = filter.b0
        let b1 = filter.b1
        let b2 = filter.b2
        let a1 = filter.a1
        let a2 = filter.a2
        var localZ1 = z1
        var localZ2 = z2

        if stride == 1 {
            for index in 0..<frames {
                let x = Double(samples[index])
                let y = b0 * x + localZ1
                localZ1 = b1 * x - a1 * y + localZ2
                localZ2 = b2 * x - a2 * y
                samples[index] = Float(y)
            }
        } else {
            var ptr = samples
            for _ in 0..<frames {
                let x = Double(ptr.pointee)
                let y = b0 * x + localZ1
                localZ1 = b1 * x - a1 * y + localZ2
                localZ2 = b2 * x - a2 * y
                ptr.pointee = Float(y)
                ptr += stride
            }
        }

        if !localZ1.isFinite || abs(localZ1) < 1e-15 { localZ1 = 0 }
        if !localZ2.isFinite || abs(localZ2) < 1e-15 { localZ2 = 0 }
        z1 = localZ1
        z2 = localZ2
    }

    private mutating func processTransition(
        _ i: Int,
        slot: Int,
        samples: UnsafeMutablePointer<Float>,
        stride: Int,
        frames: Int
    ) {
        let currentIsIdentity = filters[i].isIdentity
        let targetIsIdentity = filters[i].targetIsIdentity
        guard !currentIsIdentity || !targetIsIdentity else { return }

        let currFilter = filters[i].filter
        let targFilter = filters[i].targetFilter
        let elapsed = filters[i].blockTransitionElapsed
        let totalFrames = filters[i].blockTransitionTotal
        let total = Double(totalFrames)

        var currentZ1 = delays[slot]
        var currentZ2 = delays[slot + 1]
        var targetZ1 = transitionDelays[slot]
        var targetZ2 = transitionDelays[slot + 1]

        var ptr = samples
        for k in 0..<frames {
            let frameIndex = elapsed + k
            let alpha =
                frameIndex >= totalFrames
                ? 1.0 : (frameIndex <= 0 ? 0.0 : Double(frameIndex) / total)
            let x = Double(ptr.pointee)

            let currentOutput =
                currentIsIdentity
                ? x
                : Self.transitionSample(
                    x, filter: currFilter, z1: &currentZ1, z2: &currentZ2)
            let targetOutput =
                targetIsIdentity
                ? x
                : Self.transitionSample(
                    x, filter: targFilter, z1: &targetZ1, z2: &targetZ2)

            ptr.pointee = Float(currentOutput + alpha * (targetOutput - currentOutput))
            ptr += stride
        }

        if !currentIsIdentity {
            if !currentZ1.isFinite || abs(currentZ1) < 1e-15 { currentZ1 = 0 }
            if !currentZ2.isFinite || abs(currentZ2) < 1e-15 { currentZ2 = 0 }
            delays[slot] = currentZ1
            delays[slot + 1] = currentZ2
        }
        if !targetIsIdentity {
            if !targetZ1.isFinite || abs(targetZ1) < 1e-15 { targetZ1 = 0 }
            if !targetZ2.isFinite || abs(targetZ2) < 1e-15 { targetZ2 = 0 }
            transitionDelays[slot] = targetZ1
            transitionDelays[slot + 1] = targetZ2
        }
    }

    @inline(__always)
    private static func transitionSample(
        _ input: Double, filter: Biquad, z1: inout Double, z2: inout Double
    ) -> Double {
        let output = filter.b0 * input + z1
        z1 = filter.b1 * input - filter.a1 * output + z2
        z2 = filter.b2 * input - filter.a2 * output
        return output
    }

    /// Applies the output trim in place along the persistent integer frame timeline.
    func applyPreamp(_ samples: UnsafeMutablePointer<Float>, stride: Int, frames: Int) {
        guard frames > 0 else { return }

        if !blockPreampIsRamping {
            guard blockPreampTarget != 1.0 else { return }
            var gain = Float(blockPreampTarget)
            vDSP_vsmul(samples, stride, &gain, samples, stride, vDSP_Length(frames))
            return
        }

        let elapsed = blockPreampElapsed
        let total = blockPreampTotal
        let base = blockPreampBase
        let target = blockPreampTarget
        let delta = target - base

        if elapsed >= total {
            guard target != 1.0 else { return }
            var gain = Float(target)
            vDSP_vsmul(samples, stride, &gain, samples, stride, vDSP_Length(frames))
            return
        }

        let rampFrames = min(frames, total - elapsed)
        let initialGain = base + delta * (Double(elapsed) / Double(total))
        let gainStep = delta / Double(total)

        var start = Float(initialGain)
        var step = Float(gainStep)
        vDSP_vrampmul(samples, stride, &start, &step, samples, stride, vDSP_Length(rampFrames))

        if rampFrames < frames {
            let remainderFrames = frames - rampFrames
            let remainderPointer = samples.advanced(by: rampFrames * stride)
            if target != 1.0 {
                var gain = Float(target)
                vDSP_vsmul(
                    remainderPointer, stride, &gain, remainderPointer, stride,
                    vDSP_Length(remainderFrames))
            }
        }
    }

    // MARK: - Delay lines and filter construction

    private func makeBiquad(from params: Parameters) -> Biquad {
        guard params.isEnabled else { return .identity }
        guard
            Biquad.isActive(
                kind: params.kind,
                frequency: params.frequency,
                gain: params.gain,
                sampleRate: sampleRate
            )
        else {
            return .identity
        }
        return Biquad(
            kind: params.kind,
            frequency: params.frequency,
            gain: params.gain,
            q: params.q,
            sampleRate: sampleRate
        )
    }

    private func delayIndex(filter: Int, channel: Int) -> Int {
        (filter * EQProcessor.maxChannels + channel) * 2
    }

    private mutating func resetDelays(filter: Int) {
        let base = delayIndex(filter: filter, channel: 0)
        for offset in 0..<(EQProcessor.maxChannels * 2) {
            delays[base + offset] = 0
        }
    }

    private mutating func resetTransitionDelays(filter: Int) {
        let base = delayIndex(filter: filter, channel: 0)
        for offset in 0..<(EQProcessor.maxChannels * 2) {
            transitionDelays[base + offset] = 0
        }
    }

    private mutating func copyTransitionDelaysToPrimary(filter: Int) {
        let base = delayIndex(filter: filter, channel: 0)
        for offset in 0..<(EQProcessor.maxChannels * 2) {
            delays[base + offset] = transitionDelays[base + offset]
        }
    }
}
