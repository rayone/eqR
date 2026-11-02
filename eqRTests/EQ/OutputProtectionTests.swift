import Foundation
import Testing

struct OutputProtectionTests {
    private func process(
        _ left: [Float], _ right: [Float], chunks: [Int], ceiling: Float?
    ) -> (left: [Float], right: [Float]) {
        var stage = OutputProtection(sampleRate: 48_000)
        var l = left
        var r = right
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                guard let lb = lp.baseAddress, let rb = rp.baseAddress else { return }
                var offset = 0
                for frames in chunks {
                    stage.process(
                        lb + offset, leftStride: 1, rb + offset, rightStride: 1,
                        frames: frames, ceiling: ceiling)
                    offset += frames
                }
            }
        }
        return (l, r)
    }

    @Test func firstTransientIsContainedWithoutDelayOrStereoShift() {
        let result = process([2, 0, 0], [1, 0, 0], chunks: [3], ceiling: 1)
        #expect(result.left[0] <= 1 && result.left[0] > 0.99)
        #expect(result.left[0] / result.right[0] == 2)
        #expect(result.left[1...] == [0, 0])
        #expect(result.right[1...] == [0, 0])
    }

    @Test func callbackPartitionDoesNotChangeContainmentOrRelease() {
        let left: [Float] = (0..<8_192).map { index in
            index == 321 ? 3 : Float(0.4 * sin(Double(index) * 0.13))
        }
        let right = left.map { $0 * 0.25 }
        let large = process(left, right, chunks: [8_192], ceiling: 1)
        let small = process(left, right, chunks: [Int](repeating: 128, count: 64), ceiling: 1)
        #expect(large.left == small.left)
        #expect(large.right == small.right)
        #expect(abs(large.left[322]) < abs(left[322]) * 0.34)
        #expect(abs(large.left[8_000]) > abs(left[8_000]) * 0.7)
    }

    @Test func belowCeilingAndDisabledPathsAreBitExact() {
        let input: [Float] = [-0.99, 0, 0.8, -0.5]
        let safe = process(input, input, chunks: [4], ceiling: 1)
        #expect(safe.left == input && safe.right == input)
        let loud: [Float] = [-2, 1.5, 0, 3]
        let disabled = process(loud, loud, chunks: [4], ceiling: nil)
        #expect(disabled.left == loud && disabled.right == loud)
    }

    @Test func disablingProtectionReleasesPreviousReductionWithoutAJump() {
        var stage = OutputProtection(sampleRate: 48_000)
        var peak: Float = 2
        withUnsafeMutablePointer(to: &peak) {
            stage.process($0, leftStride: 1, frames: 1, ceiling: 1)
        }
        var tail = [Float](repeating: 0.5, count: 96_000)
        tail.withUnsafeMutableBufferPointer { pointer in
            if let base = pointer.baseAddress {
                stage.process(base, leftStride: 1, frames: pointer.count, ceiling: nil)
            }
        }
        #expect(tail[0] > 0.25 && tail[0] < 0.251)
        #expect(abs(tail[95_999] - 0.5) < 0.00001)
        #expect(zip(tail, tail.dropFirst()).allSatisfy { $0 <= $1 })
    }
}
