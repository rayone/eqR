import Foundation
import Testing

/// Behavioral test suite for `StereoWidener`.
///
/// Verifies:
/// 1. Sample-continuous width transitions independent of callback partition.
/// 2. Partition invariance with total frames > 2400 (spanning both transition and settled periods).
/// 3. Partition boundaries ending mid-control interval (non-multiples of 32).
/// 4. Neutral bit-exact passthrough.
/// 5. Linear mono-sum preservation and bit-exact mono passthrough at any width and mid-transition.
/// 6. Settled shelf frequency response and side gain (150 Hz corner, +9.5 dB treble shelf at 200%).
/// 7. Settling behavior through processing silence and state reporting for `addsLevel`.
struct StereoWidenerTests {
    private let sampleRate = 48_000.0

    // MARK: - Helpers

    private func makeSine(
        frequency: Double, frames: Int, amplitude: Float = 0.5, rate: Double = 48_000
    ) -> [Float] {
        (0..<frames).map { i in
            amplitude * Float(sin(2.0 * Double.pi * frequency * Double(i) / rate))
        }
    }

    private func makeStereoRamp(frames: Int) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        for i in 0..<frames {
            left[i] = Float(i) / Float(max(1, frames))
            right[i] = 1.0 - left[i]
        }
        return (left, right)
    }

    private func settle(widener: inout StereoWidener, frames: Int = 4_096) {
        var silenceL = [Float](repeating: 0, count: frames)
        var silenceR = [Float](repeating: 0, count: frames)
        silenceL.withUnsafeMutableBufferPointer { l in
            silenceR.withUnsafeMutableBufferPointer { r in
                widener.process(
                    l.baseAddress!, leftStride: 1,
                    r.baseAddress!, rightStride: 1,
                    frames: frames)
            }
        }
        widener.reset()
    }

    private func renderStereo(
        widener: inout StereoWidener,
        leftInput: [Float],
        rightInput: [Float],
        partitionSizes: [Int]? = nil,
        fixedChunkSize: Int? = nil
    ) -> (left: [Float], right: [Float]) {
        var left = leftInput
        var right = rightInput
        let totalFrames = min(left.count, right.count)

        left.withUnsafeMutableBufferPointer { lBuf in
            right.withUnsafeMutableBufferPointer { rBuf in
                var offset = 0
                var partIdx = 0

                while offset < totalFrames {
                    let remaining = totalFrames - offset
                    let count: Int
                    if let partitionSizes, !partitionSizes.isEmpty {
                        count = min(remaining, partitionSizes[partIdx % partitionSizes.count])
                        partIdx += 1
                    } else if let fixedChunkSize {
                        count = min(remaining, fixedChunkSize)
                    } else {
                        count = remaining
                    }

                    widener.process(
                        lBuf.baseAddress! + offset, leftStride: 1,
                        rBuf.baseAddress! + offset, rightStride: 1,
                        frames: count)
                    offset += count
                }
            }
        }
        return (left, right)
    }

    @Test func returningToNeutralIsBitExactAfterTheRampInAnyPartition() {
        let left = makeSine(frequency: 733, frames: 8_192, amplitude: 0.2)
        let right = makeSine(frequency: 997, frames: 8_192, amplitude: 0.1)
        var whole = StereoWidener(sampleRate: sampleRate)
        whole.setWidth(2)
        settle(widener: &whole)
        var split = whole
        whole.setWidth(1)
        split.setWidth(1)
        let a = renderStereo(widener: &whole, leftInput: left, rightInput: right)
        let b = renderStereo(
            widener: &split, leftInput: left, rightInput: right,
            partitionSizes: [17, 33, 71])
        #expect(a.left == b.left && a.right == b.right)
        #expect(Array(a.left[2_400...]) == Array(left[2_400...]))
        #expect(Array(a.right[2_400...]) == Array(right[2_400...]))
    }

    private func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(samples.count)).squareRoot()
    }

    // MARK: - Neutral Bit-Exact Passthrough

    @Test func neutralIsBitExactPassthrough() {
        var widener = StereoWidener(sampleRate: sampleRate)
        for frames in [1, 16, 64, 512, 2_048, 8_192] {
            let (lIn, rIn) = makeStereoRamp(frames: frames)
            let (lOut, rOut) = renderStereo(
                widener: &widener, leftInput: lIn, rightInput: rIn, fixedChunkSize: frames)
            #expect(lOut == lIn, "left channel altered at neutral width with \(frames) frames")
            #expect(rOut == rIn, "right channel altered at neutral width with \(frames) frames")
        }
    }

    // MARK: - Mono Source & Mono Sum Preservation

    @Test func monoSourceStaysBitExactMonoAtAnyWidth() {
        let widths = [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        let frames = 1_024
        let tone = makeSine(frequency: 1_000, frames: frames, amplitude: 0.7)

        for width in widths {
            var widener = StereoWidener(sampleRate: sampleRate)
            widener.setWidth(width)
            settle(widener: &widener)

            let (lOut, rOut) = renderStereo(
                widener: &widener, leftInput: tone, rightInput: tone, fixedChunkSize: 128)
            #expect(lOut == tone, "mono source altered on left at width \(width)")
            #expect(rOut == tone, "mono source altered on right at width \(width)")
        }
    }

    @Test func monoSourceStaysBitExactMonoDuringTransitions() {
        var widener = StereoWidener(sampleRate: sampleRate)
        let frames = 8_192
        let tone = makeSine(frequency: 800, frames: frames, amplitude: 0.6)

        // Trigger transition 1.0 -> 2.0 while mono tone is playing
        widener.setWidth(2.0)
        let (lOut, rOut) = renderStereo(
            widener: &widener, leftInput: tone, rightInput: tone, fixedChunkSize: 64)

        #expect(lOut == tone, "mono source altered on left during transition 1.0 -> 2.0")
        #expect(rOut == tone, "mono source altered on right during transition 1.0 -> 2.0")
    }

    @Test func monoSumIsAlgebraicallyLinearAtAnyWidth() {
        let frames = 2_048
        let leftSine = makeSine(frequency: 440, frames: frames, amplitude: 0.4)
        let rightSine = makeSine(frequency: 1_200, frames: frames, amplitude: 0.4)
        let inputSum = zip(leftSine, rightSine).map { $0 + $1 }

        for width in [0.0, 0.5, 1.0, 1.5, 2.0] {
            var widener = StereoWidener(sampleRate: sampleRate)
            widener.setWidth(width)
            settle(widener: &widener)

            let (lOut, rOut) = renderStereo(
                widener: &widener, leftInput: leftSine, rightInput: rightSine, fixedChunkSize: 128)
            let outputSum = zip(lOut, rOut).map { $0 + $1 }

            for i in 0..<frames {
                #expect(
                    abs(outputSum[i] - inputSum[i]) < 1e-5,
                    "mono sum diverged from input sum at width \(width) at frame \(i)")
            }
        }
    }

    @Test func monoSumIsAlgebraicallyLinearDuringTransitions() {
        let frames = 8_192
        let leftSine = makeSine(frequency: 330, frames: frames, amplitude: 0.4)
        let rightSine = makeSine(frequency: 880, frames: frames, amplitude: 0.4)
        let inputSum = zip(leftSine, rightSine).map { $0 + $1 }

        var widener = StereoWidener(sampleRate: sampleRate)
        widener.setWidth(2.0)
        let (lOut, rOut) = renderStereo(
            widener: &widener, leftInput: leftSine, rightInput: rightSine, fixedChunkSize: 64)
        let outputSum = zip(lOut, rOut).map { $0 + $1 }

        for i in 0..<frames {
            #expect(
                abs(outputSum[i] - inputSum[i]) < 1e-5,
                "mono sum diverged during transition at frame \(i)")
        }
    }

    // MARK: - Settled Frequency Response & Side Gain

    @Test func settledNarrowingAtZeroCollapsesStereoToMono() {
        var widener = StereoWidener(sampleRate: sampleRate)
        widener.setWidth(0.0)
        settle(widener: &widener)

        let frames = 512
        let leftInput = [Float](repeating: 1.0, count: frames)
        let rightInput = [Float](repeating: 3.0, count: frames)
        // Mid = 2.0, Side = -1.0. At 0.0 width, side is eliminated, so left and right should be 2.0.
        let (lOut, rOut) = renderStereo(
            widener: &widener, leftInput: leftInput, rightInput: rightInput, fixedChunkSize: 128)

        for i in 0..<frames {
            #expect(abs(lOut[i] - 2.0) < 1e-5, "left did not collapse to mid 2.0 at frame \(i)")
            #expect(abs(rOut[i] - 2.0) < 1e-5, "right did not collapse to mid 2.0 at frame \(i)")
        }
    }

    @Test func settledWideningAt200TriplesTrebleSideSignal() {
        var widener = StereoWidener(sampleRate: sampleRate)
        widener.setWidth(2.0)
        settle(widener: &widener)

        let frames = 4_096
        // Hard-panned 3 kHz tone: L = tone, R = 0 -> inSide = 0.5 * tone
        let tone = makeSine(frequency: 3_000, frames: frames, amplitude: 0.3)
        let silence = [Float](repeating: 0, count: frames)
        let (lOut, rOut) = renderStereo(
            widener: &widener, leftInput: tone, rightInput: silence, fixedChunkSize: 512)

        let outSide = zip(lOut, rOut).map { 0.5 * ($0 - $1) }
        let inSide = tone.map { 0.5 * $0 }

        let gain = rms(outSide) / rms(inSide)
        // High shelf formula at width 2.0 gives gain = 1 + 2(2 - 1) = 3.0 (+9.54 dB)
        #expect(abs(gain - 3.0) < 0.05, "maximum widening side gain \(gain) is not 3.0 in treble")
    }

    @Test func settledSubBassStaysCenteredWhenWidened() {
        var widener = StereoWidener(sampleRate: sampleRate)
        widener.setWidth(2.0)
        settle(widener: &widener)

        let frames = 4_096
        // 50 Hz sub-bass: shelf corner is 150 Hz, so side boost at 50 Hz must be under 1 dB (< 1.12x)
        let subBass = makeSine(frequency: 50, frames: frames, amplitude: 0.4)
        let silence = [Float](repeating: 0, count: frames)
        let (lOut, rOut) = renderStereo(
            widener: &widener, leftInput: subBass, rightInput: silence, fixedChunkSize: 512)

        let outSide = zip(lOut, rOut).map { 0.5 * ($0 - $1) }
        let inSide = subBass.map { 0.5 * $0 }

        let gain = rms(outSide) / rms(inSide)
        #expect(gain < 1.15, "sub-bass at 50 Hz boosted by factor \(gain), exceeding 1 dB")
    }

    // MARK: - Width Transition Partition Invariance (Total > 2400 frames & Mid-Interval Boundaries)

    @Test func widthTransitionPartitionInvarianceNarrowingLong() {
        // Total 8192 frames > 2400 frames (transition finishes at 2400, then settled for 5792)
        let frames = 8_192
        let (lIn, rIn) = makeStereoRamp(frames: frames)

        // Run A: Single monolithic block of 8192 frames
        var widenerA = StereoWidener(sampleRate: sampleRate)
        widenerA.setWidth(0.0)
        let (lA, rA) = renderStereo(
            widener: &widenerA, leftInput: lIn, rightInput: rIn, fixedChunkSize: frames)

        // Run B: 16 chunks of 512 frames
        var widenerB = StereoWidener(sampleRate: sampleRate)
        widenerB.setWidth(0.0)
        let (lB, rB) = renderStereo(
            widener: &widenerB, leftInput: lIn, rightInput: rIn, fixedChunkSize: 512)

        // Run C: Small chunks of 64 frames (128 blocks)
        var widenerC = StereoWidener(sampleRate: sampleRate)
        widenerC.setWidth(0.0)
        let (lC, rC) = renderStereo(
            widener: &widenerC, leftInput: lIn, rightInput: rIn, fixedChunkSize: 64)

        // Run D: Irregular partition sizes ending mid-control interval (non-multiples of 32: 17, 33, 49, 71, etc.)
        var widenerD = StereoWidener(sampleRate: sampleRate)
        widenerD.setWidth(0.0)
        let (lD, rD) = renderStereo(
            widener: &widenerD, leftInput: lIn, rightInput: rIn,
            partitionSizes: [17, 33, 49, 71, 93, 115, 63, 127, 255])

        for i in 0..<frames {
            #expect(abs(lA[i] - lB[i]) < 1e-5, "Narrowing A vs B left diverged at frame \(i)")
            #expect(abs(rA[i] - rB[i]) < 1e-5, "Narrowing A vs B right diverged at frame \(i)")
            #expect(abs(lA[i] - lC[i]) < 1e-5, "Narrowing A vs C left diverged at frame \(i)")
            #expect(abs(rA[i] - rC[i]) < 1e-5, "Narrowing A vs C right diverged at frame \(i)")
            #expect(abs(lA[i] - lD[i]) < 1e-5, "Narrowing A vs D left diverged at frame \(i)")
            #expect(abs(rA[i] - rD[i]) < 1e-5, "Narrowing A vs D right diverged at frame \(i)")
        }
    }

    @Test func widthTransitionPartitionInvarianceWideningLong() {
        // Total 8192 frames > 2400 frames (transition finishes at 2400, then settled for 5792)
        let frames = 8_192
        let (lIn, rIn) = makeStereoRamp(frames: frames)

        // Run A: Single monolithic block of 8192 frames
        var widenerA = StereoWidener(sampleRate: sampleRate)
        widenerA.setWidth(2.0)
        let (lA, rA) = renderStereo(
            widener: &widenerA, leftInput: lIn, rightInput: rIn, fixedChunkSize: frames)

        // Run B: 16 chunks of 512 frames
        var widenerB = StereoWidener(sampleRate: sampleRate)
        widenerB.setWidth(2.0)
        let (lB, rB) = renderStereo(
            widener: &widenerB, leftInput: lIn, rightInput: rIn, fixedChunkSize: 512)

        // Run C: Blocks of 64 frames (128 blocks)
        var widenerC = StereoWidener(sampleRate: sampleRate)
        widenerC.setWidth(2.0)
        let (lC, rC) = renderStereo(
            widener: &widenerC, leftInput: lIn, rightInput: rIn, fixedChunkSize: 64)

        // Run D: Irregular partition sizes ending mid-control interval (non-multiples of 32)
        var widenerD = StereoWidener(sampleRate: sampleRate)
        widenerD.setWidth(2.0)
        let (lD, rD) = renderStereo(
            widener: &widenerD, leftInput: lIn, rightInput: rIn,
            partitionSizes: [17, 33, 49, 71, 93, 115, 63, 127, 255])

        for i in 0..<frames {
            #expect(abs(lA[i] - lB[i]) < 1e-5, "Widening A vs B left diverged at frame \(i)")
            #expect(abs(rA[i] - rB[i]) < 1e-5, "Widening A vs B right diverged at frame \(i)")
            #expect(abs(lA[i] - lC[i]) < 1e-5, "Widening A vs C left diverged at frame \(i)")
            #expect(abs(rA[i] - rC[i]) < 1e-5, "Widening A vs C right diverged at frame \(i)")
            #expect(abs(lA[i] - lD[i]) < 1e-5, "Widening A vs D left diverged at frame \(i)")
            #expect(abs(rA[i] - rD[i]) < 1e-5, "Widening A vs D right diverged at frame \(i)")
        }
    }

    @Test func widthTransitionPartitionInvarianceCrossingNeutralLong() {
        let frames = 8_192
        let (lIn, rIn) = makeStereoRamp(frames: frames)

        // Transition from 0.2 across 1.0 to 1.8
        var widenerA = StereoWidener(sampleRate: sampleRate)
        widenerA.setWidth(0.2)
        settle(widener: &widenerA)
        widenerA.setWidth(1.8)

        var widenerB = StereoWidener(sampleRate: sampleRate)
        widenerB.setWidth(0.2)
        settle(widener: &widenerB)
        widenerB.setWidth(1.8)

        var widenerC = StereoWidener(sampleRate: sampleRate)
        widenerC.setWidth(0.2)
        settle(widener: &widenerC)
        widenerC.setWidth(1.8)

        var widenerD = StereoWidener(sampleRate: sampleRate)
        widenerD.setWidth(0.2)
        settle(widener: &widenerD)
        widenerD.setWidth(1.8)

        let (lA, rA) = renderStereo(
            widener: &widenerA, leftInput: lIn, rightInput: rIn, fixedChunkSize: frames)
        let (lB, rB) = renderStereo(
            widener: &widenerB, leftInput: lIn, rightInput: rIn, fixedChunkSize: 512)
        let (lC, rC) = renderStereo(
            widener: &widenerC, leftInput: lIn, rightInput: rIn, fixedChunkSize: 64)
        let (lD, rD) = renderStereo(
            widener: &widenerD, leftInput: lIn, rightInput: rIn,
            partitionSizes: [17, 33, 49, 71, 93, 115, 63, 127, 255])

        for i in 0..<frames {
            #expect(
                abs(lA[i] - lB[i]) < 1e-5, "Crossing neutral A vs B left diverged at frame \(i)")
            #expect(
                abs(rA[i] - rB[i]) < 1e-5, "Crossing neutral A vs B right diverged at frame \(i)")
            #expect(
                abs(lA[i] - lC[i]) < 1e-5, "Crossing neutral A vs C left diverged at frame \(i)")
            #expect(
                abs(rA[i] - rC[i]) < 1e-5, "Crossing neutral A vs C right diverged at frame \(i)")
            #expect(
                abs(lA[i] - lD[i]) < 1e-5, "Crossing neutral A vs D left diverged at frame \(i)")
            #expect(
                abs(rA[i] - rD[i]) < 1e-5, "Crossing neutral A vs D right diverged at frame \(i)")
        }
    }

    // MARK: - Settling and addsLevel State

    @Test func settlingThroughProcessAchievesExactTargetWidth() {
        var widener = StereoWidener(sampleRate: sampleRate)
        widener.setWidth(2.0)
        #expect(widener.currentWidth == 1.0)
        #expect(widener.addsLevel == true)

        settle(widener: &widener, frames: 3_000)
        #expect(
            abs(widener.currentWidth - 2.0) < 1e-6,
            "width did not settle to 2.0 after processing silence")
        #expect(widener.addsLevel == true)

        // Subsequent processing should immediately render at 200% from first sample
        let frames = 512
        let tone = makeSine(frequency: 3_000, frames: frames, amplitude: 0.3)
        let silence = [Float](repeating: 0, count: frames)
        let (lOut, rOut) = renderStereo(
            widener: &widener, leftInput: tone, rightInput: silence, fixedChunkSize: frames)
        let outSide = zip(lOut, rOut).map { 0.5 * ($0 - $1) }
        let inSide = tone.map { 0.5 * $0 }
        let gain = rms(outSide) / rms(inSide)
        #expect(abs(gain - 3.0) < 0.05, "settled widener did not produce 3x gain from first sample")
    }

    @Test func addsLevelAccuratelyTracksState() {
        var widener = StereoWidener(sampleRate: sampleRate)
        #expect(widener.addsLevel == false)

        widener.setWidth(0.5)
        #expect(widener.addsLevel == false)
        settle(widener: &widener, frames: 3_000)
        #expect(widener.addsLevel == false)

        widener.setWidth(1.5)
        #expect(widener.addsLevel == true)
        settle(widener: &widener, frames: 3_000)
        #expect(widener.addsLevel == true)

        widener.setWidth(1.0)
        #expect(widener.addsLevel == true)  // still active while moving down
        settle(widener: &widener, frames: 3_000)
        #expect(widener.addsLevel == false)  // settled at 1.0
    }
}
