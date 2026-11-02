import Foundation

/// Instantaneous linked peak containment with a 150 ms release. No lookahead,
/// buffering, independent channel clipping, or work on an already-neutral pair.
/// Unexpected peaks necessarily cause immediate gain reduction: this is a
/// zero-added-delay safety stage, not a distortion-free mastering limiter.
struct OutputProtection {
    private var gain = 1.0
    private var release = 0.0

    init(sampleRate: Double = 44_100) {
        setSampleRate(sampleRate)
    }

    mutating func setSampleRate(_ sampleRate: Double) {
        release = exp(-1 / (sampleRate * 0.15))
    }

    mutating func reset() { gain = 1 }

    /// A nil ceiling disables new containment but smoothly releases old gain.
    mutating func process(
        _ left: UnsafeMutablePointer<Float>, leftStride: Int,
        _ right: UnsafeMutablePointer<Float>? = nil, rightStride: Int = 1,
        frames: Int, ceiling: Float?
    ) {
        guard frames > 0, ceiling != nil || gain < 1 else { return }
        var l = 0
        var r = 0
        for _ in 0..<frames {
            let peak = max(abs(left[l]), right.map { abs($0[r]) } ?? 0)
            let recovering = 1 - (1 - gain) * release
            let needed: Double
            if let ceiling, peak.isFinite, peak > ceiling {
                needed = Double(ceiling.nextDown) / Double(peak)
            } else {
                needed = 1
            }
            gain = min(needed, recovering)
            if gain > 0.999999, needed == 1 { gain = 1 }
            if gain < 1 {
                left[l] = Float(Double(left[l]) * gain)
                if let right { right[r] = Float(Double(right[r]) * gain) }
            }
            l += leftStride
            r += rightStride
        }
    }
}
