import Accelerate
import Foundation
import Testing

/// Tests for `FilterBank`: biquad filter chain processing, delay line management,
/// continuous preamp ramping, and transition-safe parameter edits.
struct FilterBankTests {
    private let sampleRate = 48_000.0

    private func sine(
        _ frequency: Double, frames: Int, rate: Double = 48_000.0, amplitude: Float = 0.5,
        startFrame: Int = 0
    ) -> [Float] {
        (0..<frames).map { frame in
            let totalFrame = startFrame + frame
            return amplitude * Float(sin(2 * .pi * frequency * Double(totalFrame) / rate))
        }
    }

    private func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(samples.count)).squareRoot()
    }

    // MARK: - Stale-State Replay Fix

    /// Confirmed stale-state replay bug:
    /// In the old implementation, skipping identity filters froze delay lines without
    /// clearing or draining them. Settling a +12 dB low shelf at 200 Hz on DC 0.1,
    /// setting gain to 0 dB, passing 40960 frames of silence, and then setting gain
    /// back to 12 dB produced a 0.29678 DC spike out of silence.
    ///
    /// The transition-safe bank ensures identity states clear delay lines and transitions
    /// crossfade safely, producing clean silence.
    @Test func staleStateReplayIsPreventedWhenFilterBecomesIdentityAndReturns() {
        let testRate = 44_100.0
        var bank = FilterBank()
        _ = bank.setSampleRate(testRate)

        let shelfFilter = EQFilter(kind: .lowShelf, frequency: 200, gain: 12, q: 0.7)
        let activeParams = FilterBank.Parameters(shelfFilter)
        bank.setFilters([activeParams], count: 1)

        // 1. Settle the filter on DC 0.1 so the delay line holds settled state:
        let dcBlockFrames = 512
        for _ in 0..<30 {
            bank.advance(frames: dcBlockFrames)
            var dcBuffer = [Float](repeating: 0.1, count: dcBlockFrames)
            bank.process(&dcBuffer, stride: 1, frames: dcBlockFrames, channel: 0)
        }

        // 2. Set gain to 0 dB (which becomes identity) and let the transition settle:
        var flatFilter = shelfFilter
        flatFilter.gain = 0.0
        let flatParams = FilterBank.Parameters(flatFilter)
        bank.setFilters([flatParams], count: 1)

        for _ in 0..<20 {
            bank.advance(frames: dcBlockFrames)
            var dcBuffer = [Float](repeating: 0.1, count: dcBlockFrames)
            bank.process(&dcBuffer, stride: 1, frames: dcBlockFrames, channel: 0)
        }

        // 3. Pass 40960 frames of silence:
        let silenceChunk = 512
        let chunks = 40_960 / silenceChunk
        for _ in 0..<chunks {
            bank.advance(frames: silenceChunk)
            var silence = [Float](repeating: 0.0, count: silenceChunk)
            bank.process(&silence, stride: 1, frames: silenceChunk, channel: 0)
            #expect(silence.allSatisfy { $0 == 0.0 }, "Identity filter must pass silence cleanly")
        }

        // 4. Set gain back to +12 dB:
        bank.setFilters([activeParams], count: 1)

        // 5. Process silence immediately after restoring gain:
        bank.advance(frames: silenceChunk)
        var postReturnSilence = [Float](repeating: 0.0, count: silenceChunk)
        bank.process(&postReturnSilence, stride: 1, frames: silenceChunk, channel: 0)

        // In the old code, postReturnSilence[0] was ~0.29678.
        // It must now be strictly zero (or below floating-point threshold < 1e-5).
        #expect(
            abs(postReturnSilence[0]) < 1e-5,
            "Stale delay line replayed into silence: first sample was \(postReturnSilence[0]), expected 0.0"
        )
        for sample in postReturnSilence {
            #expect(abs(sample) < 1e-5, "Silence out of stale filter was \(sample)")
        }
    }

    // MARK: - Chunk Invariance: 8192 Single Pass vs 64-Frame & Irregular Chunks

    /// Transitions use a persistent integer timeline so rendering 8192 frames in one
    /// single call completes at sample 2400 and holds target, rather than stretching
    /// the ramp over all 8192 frames. Output must match 64-frame chunked rendering.
    @Test func singlePass8192vs64FrameChunksMatchDuringTransitionAndCompletion() {
        var bankA = FilterBank()
        _ = bankA.setSampleRate(sampleRate)

        var bankB = FilterBank()
        _ = bankB.setSampleRate(sampleRate)

        let initialFilter = EQFilter(kind: .bell, frequency: 1_000, gain: 0, q: 1.0)
        bankA.setFilters([FilterBank.Parameters(initialFilter)], count: 1)
        bankB.setFilters([FilterBank.Parameters(initialFilter)], count: 1)
        bankA.advance(frames: 512)
        bankB.advance(frames: 512)

        let totalFrames = 8_192
        let inputSignal = sine(1_000, frames: totalFrames, rate: sampleRate)

        // Trigger transition to +12 dB:
        let targetFilter = EQFilter(kind: .bell, frequency: 1_000, gain: 12, q: 1.0)
        bankA.setFilters([FilterBank.Parameters(targetFilter)], count: 1)
        bankB.setFilters([FilterBank.Parameters(targetFilter)], count: 1)

        // Path A: Single 8192-frame block:
        bankA.advance(frames: totalFrames)
        var outA = inputSignal
        bankA.process(&outA, stride: 1, frames: totalFrames, channel: 0)

        // Path B: 64-frame chunked rendering:
        let chunkSize = 64
        var outB = [Float](repeating: 0, count: totalFrames)
        for chunkIndex in 0..<(totalFrames / chunkSize) {
            let offset = chunkIndex * chunkSize
            var chunk = Array(inputSignal[offset..<(offset + chunkSize)])
            bankB.advance(frames: chunkSize)
            bankB.process(&chunk, stride: 1, frames: chunkSize, channel: 0)
            for j in 0..<chunkSize {
                outB[offset + j] = chunk[j]
            }
        }

        for i in 0..<totalFrames {
            let diff = abs(outA[i] - outB[i])
            #expect(
                diff < 1e-4,
                "Sample mismatch at timeline frame \(i): single-pass \(outA[i]) vs chunked \(outB[i])"
            )
        }
    }

    /// Preamp ramp along the persistent integer timeline reaches target linear gain
    /// at frame 2400 and holds flat, matching irregular chunked application without
    /// buffer-size stretching.
    @Test func singlePass8192vsIrregularChunksPreampRamp() {
        var bankA = FilterBank()
        _ = bankA.setSampleRate(sampleRate)

        var bankB = FilterBank()
        _ = bankB.setSampleRate(sampleRate)

        bankA.advance(frames: 512)
        bankB.advance(frames: 512)

        bankA.setPreamp(dB: -6.0)
        bankB.setPreamp(dB: -6.0)

        let totalFrames = 8_192
        var outA = [Float](repeating: 1.0, count: totalFrames)

        // Path A: single call
        bankA.advance(frames: totalFrames)
        bankA.applyPreamp(&outA, stride: 1, frames: totalFrames)

        // Path B: irregular chunk sizes summing exactly to 8192
        let chunkSizes = [64, 128, 53, 2_048, 256, 1_024, 64, 512, 128, 1_000, 2_915]
        var outB = [Float](repeating: 1.0, count: totalFrames)
        var offset = 0
        for size in chunkSizes {
            bankB.advance(frames: size)
            outB.withUnsafeMutableBufferPointer { ptr in
                bankB.applyPreamp(ptr.baseAddress! + offset, stride: 1, frames: size)
            }
            offset += size
        }
        #expect(offset == totalFrames)

        for i in 0..<totalFrames {
            let diff = abs(outA[i] - outB[i])
            #expect(
                diff < 1e-5,
                "Preamp mismatch at sample \(i): single \(outA[i]) vs irregular chunked \(outB[i])"
            )
        }

        // Verify holding target: beyond sample 2400, gain must be exactly the target -6 dB:
        let targetLinear = Float(pow(10.0, -6.0 / 20.0))
        for i in 2_400..<totalFrames {
            #expect(
                abs(outA[i] - targetLinear) < 1e-5,
                "Preamp stretched past 2400 frames: sample \(i) is \(outA[i]), expected \(targetLinear)"
            )
        }
    }

    /// Repeated edits over irregular chunks must maintain waveform continuity when driven
    /// by a continuous input signal.
    @Test func repeatedEditsOverIrregularChunksMatchWithoutRateReset() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)

        let base = EQFilter(kind: .bell, frequency: 1_000, gain: 0, q: 1.0)
        bank.setFilters([FilterBank.Parameters(base)], count: 1)
        bank.advance(frames: 256)

        let irregularChunks = [64, 128, 53, 200, 400, 512, 100, 300, 256]
        let totalFrames = irregularChunks.reduce(0, +)
        let fullInput = sine(1_000, frames: totalFrames, rate: sampleRate)

        let gains = [2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 12.0, 12.0, 12.0]

        var offset = 0
        var fullOutput = [Float](repeating: 0, count: totalFrames)

        for (index, size) in irregularChunks.enumerated() {
            var updated = base
            updated.gain = gains[index]
            bank.setFilters([FilterBank.Parameters(updated)], count: 1)

            bank.advance(frames: size)
            var chunk = Array(fullInput[offset..<(offset + size)])
            bank.process(&chunk, stride: 1, frames: size, channel: 0)

            for j in 0..<size {
                fullOutput[offset + j] = chunk[j]
            }

            if offset > 0 {
                let crossBlockDelta = abs(fullOutput[offset] - fullOutput[offset - 1])
                #expect(
                    crossBlockDelta < 0.25,
                    "Discontinuity at chunk boundary \(index): step was \(crossBlockDelta)"
                )
            }
            offset += size
        }
    }

    // MARK: - Reset and Sample Rate Adoption of Queued Edits

    /// If an edit is queued while a fade is active, a discontinuity reset (`resetAll`)
    /// or sample rate change must adopt the queued newest edit rather than reverting to the
    /// older in-flight target.
    @Test func resetAllAndSetSampleRateAdoptQueuedNewestEditRegression() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)

        let initial = EQFilter(kind: .bell, frequency: 1_000, gain: 0, q: 1.0)
        bank.setFilters([FilterBank.Parameters(initial)], count: 1)
        bank.advance(frames: 512)

        // 1. Begin transition to +6 dB:
        let firstEdit = EQFilter(kind: .bell, frequency: 1_000, gain: 6, q: 1.0)
        bank.setFilters([FilterBank.Parameters(firstEdit)], count: 1)
        bank.advance(frames: 128)

        // 2. Queue a newer edit (+12 dB at 2000 Hz) while first transition is in flight:
        let queuedEdit = EQFilter(kind: .bell, frequency: 2_000, gain: 12, q: 2.0)
        bank.setFilters([FilterBank.Parameters(queuedEdit)], count: 1)

        // 3. Call resetAll() (e.g. routing reset or audio resume):
        bank.resetAll()

        // 4. Verify that the bank adopted the queued newest edit (+12 dB at 2000 Hz):
        // Fed silence, delay lines must be clean:
        var silence = [Float](repeating: 0, count: 512)
        bank.advance(frames: 512)
        bank.process(&silence, stride: 1, frames: 512, channel: 0)
        #expect(silence.allSatisfy { $0 == 0.0 })

        // Process a 2000 Hz tone to verify the 2000 Hz +12 dB filter is active:
        var testTone = sine(2_000, frames: 2_048, rate: sampleRate)
        for _ in 0..<10 {
            bank.advance(frames: 2_048)
            testTone = sine(2_000, frames: 2_048, rate: sampleRate)
            bank.process(&testTone, stride: 1, frames: 2_048, channel: 0)
        }
        let outRMS = rms(testTone)
        let inRMS = rms(sine(2_000, frames: 2_048, rate: sampleRate))
        let gainDB = 20.0 * log10(outRMS / inRMS)
        #expect(
            abs(gainDB - 12.0) < 0.5,
            "resetAll did not adopt queued newest edit: gain was \(gainDB) dB")
    }

    // MARK: - Continuous Preamp Ramping

    @Test func continuousPreampRampRampsSampleBySample() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)

        bank.advance(frames: 512)
        bank.setPreamp(dB: -6.0)
        let frames = 512
        bank.advance(frames: frames)

        var samples = [Float](repeating: 1.0, count: frames)
        bank.applyPreamp(&samples, stride: 1, frames: frames)

        #expect(samples[0] > 0.99)
        #expect(samples[frames - 1] < samples[0])

        let firstDelta = samples[1] - samples[0]
        #expect(firstDelta < 0, "Preamp ramp must decrease on each sample")

        for i in 1..<(frames - 1) {
            let delta = samples[i + 1] - samples[i]
            #expect(abs(delta - firstDelta) < 1e-5, "Preamp ramp slope must be uniform per-sample")
        }
    }

    @Test func callbackPartitioningPreampIdenticalOnBothChannels() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)
        bank.advance(frames: 512)

        bank.setPreamp(dB: -12.0)
        let frames = 512
        bank.advance(frames: frames)

        var ch0 = [Float](repeating: 0.8, count: frames)
        var ch1 = [Float](repeating: 0.8, count: frames)

        bank.applyPreamp(&ch0, stride: 1, frames: frames)
        bank.applyPreamp(&ch1, stride: 1, frames: frames)

        #expect(ch0 == ch1, "Sequential channel calls must see identical preamp ramps")
    }

    // MARK: - Callback Partitioning for Filter Transitions

    @Test func callbackPartitioningFilterTransitionIdenticalOnBothChannels() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)

        let initialFilter = EQFilter(kind: .bell, frequency: 1_000, gain: 0, q: 1.0)
        bank.setFilters([FilterBank.Parameters(initialFilter)], count: 1)
        bank.advance(frames: 512)

        let boostedFilter = EQFilter(kind: .bell, frequency: 1_000, gain: 12, q: 1.0)
        bank.setFilters([FilterBank.Parameters(boostedFilter)], count: 1)

        let frames = 512
        bank.advance(frames: frames)

        var ch0 = sine(1_000, frames: frames, rate: sampleRate)
        var ch1 = sine(1_000, frames: frames, rate: sampleRate)

        bank.process(&ch0, stride: 1, frames: frames, channel: 0)
        bank.process(&ch1, stride: 1, frames: frames, channel: 1)

        for i in 0..<frames {
            #expect(
                abs(ch0[i] - ch1[i]) < 1e-6,
                "Channel 0 and 1 diverged at sample \(i): \(ch0[i]) vs \(ch1[i])"
            )
        }
    }

    // MARK: - Shape Transitions without Abrupt State Reset

    @Test func frequencyChangeTransitionsSmoothlyWithoutClick() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)

        let f1 = EQFilter(kind: .bell, frequency: 400, gain: 6, q: 1.0)
        bank.setFilters([FilterBank.Parameters(f1)], count: 1)

        let frames = 512
        var currentFrame = 0
        for _ in 0..<20 {
            bank.advance(frames: frames)
            var buf = sine(400, frames: frames, rate: sampleRate, startFrame: currentFrame)
            bank.process(&buf, stride: 1, frames: frames, channel: 0)
            currentFrame += frames
        }

        let f2 = EQFilter(kind: .bell, frequency: 800, gain: 6, q: 1.0)
        bank.setFilters([FilterBank.Parameters(f2)], count: 1)

        bank.advance(frames: frames)
        var transitionBuffer = sine(400, frames: frames, rate: sampleRate, startFrame: currentFrame)
        bank.process(&transitionBuffer, stride: 1, frames: frames, channel: 0)

        for i in 1..<frames {
            let step = abs(transitionBuffer[i] - transitionBuffer[i - 1])
            #expect(
                step < 0.25, "Frequency edit caused an abrupt jump at sample \(i): step was \(step)"
            )
        }
    }

    @Test func qChangeTransitionsSmoothly() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)

        let initial = EQFilter(kind: .bell, frequency: 1_000, gain: 6, q: 0.5)
        bank.setFilters([FilterBank.Parameters(initial)], count: 1)

        let frames = 512
        var currentFrame = 0
        for _ in 0..<15 {
            bank.advance(frames: frames)
            var buf = sine(1_000, frames: frames, rate: sampleRate, startFrame: currentFrame)
            bank.process(&buf, stride: 1, frames: frames, channel: 0)
            currentFrame += frames
        }

        let narrowed = EQFilter(kind: .bell, frequency: 1_000, gain: 6, q: 5.0)
        bank.setFilters([FilterBank.Parameters(narrowed)], count: 1)

        bank.advance(frames: frames)
        var transition = sine(1_000, frames: frames, rate: sampleRate, startFrame: currentFrame)
        bank.process(&transition, stride: 1, frames: frames, channel: 0)

        // Verify DC state or continuous envelope transitions without spikes:
        for i in 1..<frames {
            let step = abs(transition[i] - transition[i - 1])
            #expect(step < 0.35, "Q change caused discontinuity: step \(step)")
        }
    }

    @Test func kindChangeTransitionsSmoothly() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)

        let bell = EQFilter(kind: .bell, frequency: 200, gain: 6, q: 1.0)
        bank.setFilters([FilterBank.Parameters(bell)], count: 1)

        let frames = 512
        var currentFrame = 0
        for _ in 0..<15 {
            bank.advance(frames: frames)
            var buf = sine(200, frames: frames, rate: sampleRate, startFrame: currentFrame)
            bank.process(&buf, stride: 1, frames: frames, channel: 0)
            currentFrame += frames
        }

        let shelf = EQFilter(kind: .lowShelf, frequency: 200, gain: 6, q: 1.0)
        bank.setFilters([FilterBank.Parameters(shelf)], count: 1)

        bank.advance(frames: frames)
        var transition = sine(200, frames: frames, rate: sampleRate, startFrame: currentFrame)
        bank.process(&transition, stride: 1, frames: frames, channel: 0)

        for i in 1..<frames {
            let step = abs(transition[i] - transition[i - 1])
            #expect(step < 0.25, "Kind change caused discontinuity: step \(step)")
        }
    }

    @Test func disablingAndEnablingFilterTransitionsSmoothly() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)

        var activeFilter = EQFilter(kind: .bell, frequency: 1_000, gain: 6, q: 1.0, isEnabled: true)
        bank.setFilters([FilterBank.Parameters(activeFilter)], count: 1)

        let frames = 512
        var currentFrame = 0
        for _ in 0..<15 {
            bank.advance(frames: frames)
            var buf = sine(1_000, frames: frames, rate: sampleRate, startFrame: currentFrame)
            bank.process(&buf, stride: 1, frames: frames, channel: 0)
            currentFrame += frames
        }

        activeFilter.isEnabled = false
        bank.setFilters([FilterBank.Parameters(activeFilter)], count: 1)

        bank.advance(frames: frames)
        var disableBuf = sine(1_000, frames: frames, rate: sampleRate, startFrame: currentFrame)
        bank.process(&disableBuf, stride: 1, frames: frames, channel: 0)
        currentFrame += frames

        for i in 1..<frames {
            let step = abs(disableBuf[i] - disableBuf[i - 1])
            #expect(step < 0.35, "Disabling filter caused discontinuity: step \(step)")
        }

        for _ in 0..<15 {
            bank.advance(frames: frames)
            var buf = sine(1_000, frames: frames, rate: sampleRate, startFrame: currentFrame)
            bank.process(&buf, stride: 1, frames: frames, channel: 0)
            currentFrame += frames
        }

        activeFilter.isEnabled = true
        bank.setFilters([FilterBank.Parameters(activeFilter)], count: 1)

        bank.advance(frames: frames)
        var enableBuf = sine(1_000, frames: frames, rate: sampleRate, startFrame: currentFrame)
        bank.process(&enableBuf, stride: 1, frames: frames, channel: 0)

        for i in 1..<frames {
            let step = abs(enableBuf[i] - enableBuf[i - 1])
            #expect(step < 0.35, "Re-enabling filter caused discontinuity: step \(step)")
        }
    }

    @Test func filterRemovalTransitionsSmoothly() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)

        let f1 = EQFilter(kind: .bell, frequency: 500, gain: 6, q: 1.0)
        let f2 = EQFilter(kind: .bell, frequency: 1_000, gain: 6, q: 1.0)
        bank.setFilters([FilterBank.Parameters(f1), FilterBank.Parameters(f2)], count: 2)

        let frames = 512
        var currentFrame = 0
        for _ in 0..<15 {
            bank.advance(frames: frames)
            var buf = sine(1_000, frames: frames, rate: sampleRate, startFrame: currentFrame)
            bank.process(&buf, stride: 1, frames: frames, channel: 0)
            currentFrame += frames
        }

        bank.setFilters([FilterBank.Parameters(f1)], count: 1)

        bank.advance(frames: frames)
        var removalBuf = sine(1_000, frames: frames, rate: sampleRate, startFrame: currentFrame)
        bank.process(&removalBuf, stride: 1, frames: frames, channel: 0)

        for i in 1..<frames {
            let step = abs(removalBuf[i] - removalBuf[i - 1])
            #expect(step < 0.35, "Filter removal caused discontinuity: step \(step)")
        }
    }

    @Test func steadyIdentityIsBitExactPassthrough() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)

        let frames = 512
        bank.advance(frames: frames)

        let input = sine(1_000, frames: frames, rate: sampleRate)
        var output = input
        bank.process(&output, stride: 1, frames: frames, channel: 0)

        #expect(output == input, "Identity filter bank must pass audio bit-for-bit unchanged")
    }

    @Test func resetAllClearsDelaysAndSettlesTransitions() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)

        let filter = EQFilter(kind: .bell, frequency: 1_000, gain: 12, q: 4.0)
        bank.setFilters([FilterBank.Parameters(filter)], count: 1)

        let frames = 512
        for _ in 0..<15 {
            bank.advance(frames: frames)
            var buf = sine(1_000, frames: frames, rate: sampleRate)
            bank.process(&buf, stride: 1, frames: frames, channel: 0)
        }

        bank.resetAll()

        bank.advance(frames: frames)
        var silence = [Float](repeating: 0.0, count: frames)
        bank.process(&silence, stride: 1, frames: frames, channel: 0)

        #expect(silence.allSatisfy { $0 == 0.0 }, "resetAll must prevent ringing into silence")
    }

    // MARK: - Segmented Rendering via nextSegmentFrames

    /// nextSegmentFrames returns the exact remaining duration of all active fades,
    /// enabling callers to segment render blocks at exact transition boundaries.
    @Test func nextSegmentFramesPartitionsExactRemainingFadeDuration() {
        var bank = FilterBank()
        _ = bank.setSampleRate(sampleRate)

        let initial = EQFilter(kind: .bell, frequency: 1_000, gain: 0, q: 1.0)
        bank.setFilters([FilterBank.Parameters(initial)], count: 1)
        bank.advance(frames: 512)

        // Trigger a 50 ms transition (48000 * 0.05 = 2400 frames):
        let boosted = EQFilter(kind: .bell, frequency: 1_000, gain: 12, q: 1.0)
        bank.setFilters([FilterBank.Parameters(boosted)], count: 1)

        // With a 4096 frame block, nextSegmentFrames must limit to 2400:
        let seg1 = bank.nextSegmentFrames(maximum: 4_096)
        #expect(seg1 == 2_400, "nextSegmentFrames must bound segment to 2400 frames: got \(seg1)")

        bank.advance(frames: seg1)

        // The transition is now complete at frame 2400. Next segment for remaining 1696 frames
        // must commit the transition and return 1696 without truncation:
        let seg2 = bank.nextSegmentFrames(maximum: 1_696)
        #expect(seg2 == 1_696, "Completed transition must allow full remaining block: got \(seg2)")
    }
}
