import Foundation

/// The 3D control: mid/side stereo width, applied to the front pair after the
/// filter chain.
///
/// Self-contained on purpose. Everything the widener needs — its smoothed
/// width and the side-channel shelf — lives here, and `EQProcessor` stages,
/// resets, and runs it on the front pair.
///
/// - At 1.0 it returns before touching a sample: bit-for-bit passthrough.
/// - Below 1.0 the side signal is scaled down, reaching mono at 0.
/// - Above 1.0 the side signal passes through a high shelf whose gain is
///   `1 + 2(w-1)`: +9.5 dB of side at 200%, flat to within 0.1 dB from 1 kHz
///   up, and under 1 dB below 80 Hz, so a kick and a bass line stay centred.
///
/// Width transitions are continuous sample-by-sample and partition-invariant:
/// whether callbacks arrive in blocks of 64, 4096, or irregular sizes, every
/// sample follows the exact same trajectory over ~50 ms.
///
/// The mid is never touched. A mono source stays exactly mono at any width,
/// and the left+right sum is always the input.
///
/// A struct stored inline by the processor: fixed-size state, no allocation
/// after construction, no locks. Touched only on the render thread.
struct StereoWidener {
    /// Width at which the widener does nothing at all.
    static let neutral = 1.0
    /// Mono to 200%.
    static let range = 0.0...2.0

    /// How long a width change takes to travel, matching the band gains and the
    /// trim so a preset switch fades rather than steps.
    private static let smoothingSeconds = 0.05
    /// Corner of the side shelf. Low enough that the widening reaches the low
    /// mids, where much of a mix's spatial information lives; high enough that
    /// the side under 80 Hz is barely lifted.
    private static let shelfCornerHz = 150.0

    /// Fixed control interval (in frames) for updating shelf filter coefficients
    /// during widening transitions. Independent of callback block size.
    private static let controlInterval = 32

    private var sampleRate: Double
    private(set) var targetWidth = StereoWidener.neutral
    private(set) var currentWidth = StereoWidener.neutral

    // Sample-accurate trajectory state
    private var transitionStartWidth = StereoWidener.neutral
    private var transitionFrames = 0
    private var transitionProgress = 0

    // Persistent control interval phase for partition-invariant shelf coefficient updates
    private var controlCountdown = 0

    // RBJ high shelf (slope 1) on the side channel, transposed direct form II.
    // `cosW0` and `alpha` depend only on the rate; the rest follows the width.
    private var cosW0 = 1.0
    private var alpha = 0.0
    private var b0 = 1.0
    private var b1 = 0.0
    private var b2 = 0.0
    private var a1 = 0.0
    private var a2 = 0.0
    private var z1 = 0.0
    private var z2 = 0.0

    init(sampleRate: Double = 44_100) {
        self.sampleRate = sampleRate
        updateRateTerms()
        updateShelf(for: currentWidth)
    }

    /// Whether the width is, or is heading, above 100% — activating output
    /// protection in EQProcessor.
    var addsLevel: Bool {
        currentWidth > Self.neutral + 1e-5 || targetWidth > Self.neutral + 1e-5
    }

    private var isSettled: Bool {
        transitionProgress >= transitionFrames
    }

    // MARK: - Configuration (render thread, from staged values)

    mutating func setWidth(_ width: Double) {
        let clamped = max(Self.range.lowerBound, min(width, Self.range.upperBound))
        guard clamped != targetWidth else { return }
        targetWidth = clamped
        transitionStartWidth = currentWidth
        transitionFrames = max(1, Int((sampleRate * Self.smoothingSeconds).rounded()))
        transitionProgress = 0
    }

    /// Rebuilds the shelf for a new rate and drops state that described the
    /// old one.
    mutating func setSampleRate(_ rate: Double) {
        guard rate > 0, rate != sampleRate else { return }
        sampleRate = rate
        updateRateTerms()
        updateShelf(for: currentWidth)
        reset()
    }

    /// Drops all state, for discontinuities the widener cannot see: a pause, a
    /// routing change, coming back from bypass.
    mutating func reset() {
        z1 = 0
        z2 = 0
        controlCountdown = 0
    }

    // MARK: - Running (render thread)

    /// Widens or narrows one stereo pair in place with sample-continuous transitions.
    mutating func process(
        _ left: UnsafeMutablePointer<Float>, leftStride: Int,
        _ right: UnsafeMutablePointer<Float>, rightStride: Int,
        frames: Int
    ) {
        guard frames > 0 else { return }

        // Fast path: fully settled at neutral (bit-exact passthrough)
        if isSettled && currentWidth == Self.neutral {
            z1 = 0
            z2 = 0
            return
        }

        // Fast paths for fully settled states
        if isSettled {
            if currentWidth <= Self.neutral {
                z1 = 0
                z2 = 0
                processSettledNarrowing(
                    left, leftStride: leftStride, right, rightStride: rightStride,
                    frames: frames, width: Float(currentWidth))
            } else {
                processSettledWidening(
                    left, leftStride: leftStride, right, rightStride: rightStride,
                    frames: frames)
            }
            return
        }

        // Dynamic transition path: sample-accurate trajectory
        processTransition(
            left, leftStride: leftStride, right, rightStride: rightStride,
            frames: frames)
    }

    // MARK: - Processing Helpers

    private func processSettledNarrowing(
        _ left: UnsafeMutablePointer<Float>, leftStride: Int,
        _ right: UnsafeMutablePointer<Float>, rightStride: Int,
        frames: Int, width: Float
    ) {
        var lIdx = 0
        var rIdx = 0
        for _ in 0..<frames {
            let l = left[lIdx]
            let r = right[rIdx]
            let mid = 0.5 * (l + r)
            let side = 0.5 * (l - r) * width
            left[lIdx] = mid + side
            right[rIdx] = mid - side
            lIdx += leftStride
            rIdx += rightStride
        }
    }

    private mutating func processSettledWidening(
        _ left: UnsafeMutablePointer<Float>, leftStride: Int,
        _ right: UnsafeMutablePointer<Float>, rightStride: Int,
        frames: Int
    ) {
        var lIdx = 0
        var rIdx = 0
        var s1 = z1
        var s2 = z2
        for _ in 0..<frames {
            let l = left[lIdx]
            let r = right[rIdx]
            let mid = 0.5 * (l + r)
            let side = Double(0.5 * (l - r))

            let wide = b0 * side + s1
            s1 = b1 * side - a1 * wide + s2
            s2 = b2 * side - a2 * wide
            let wideSide = Float(wide)

            left[lIdx] = mid + wideSide
            right[rIdx] = mid - wideSide
            lIdx += leftStride
            rIdx += rightStride
        }
        z1 = sanitize(s1)
        z2 = sanitize(s2)
    }

    private mutating func processTransition(
        _ left: UnsafeMutablePointer<Float>, leftStride: Int,
        _ right: UnsafeMutablePointer<Float>, rightStride: Int,
        frames: Int
    ) {
        var lIdx = 0
        var rIdx = 0
        var s1 = z1
        var s2 = z2

        for _ in 0..<frames {
            let w = stepWidth()
            let l = left[lIdx]
            let r = right[rIdx]
            if w == Self.neutral {
                s1 = 0
                s2 = 0
                lIdx += leftStride
                rIdx += rightStride
                continue
            }
            let mid = 0.5 * (l + r)
            let side = Double(0.5 * (l - r))

            let sideOut: Float
            if w <= Self.neutral {
                sideOut = Float(side) * Float(w)
                s1 = 0
                s2 = 0
            } else {
                if controlCountdown == 0 {
                    updateShelf(for: w)
                    controlCountdown = Self.controlInterval
                }
                controlCountdown -= 1

                let wide = b0 * side + s1
                s1 = b1 * side - a1 * wide + s2
                s2 = b2 * side - a2 * wide
                sideOut = Float(wide)
            }

            left[lIdx] = mid + sideOut
            right[rIdx] = mid - sideOut
            lIdx += leftStride
            rIdx += rightStride
        }

        z1 = sanitize(s1)
        z2 = sanitize(s2)
    }

    private mutating func stepWidth() -> Double {
        guard transitionProgress < transitionFrames else { return currentWidth }
        transitionProgress += 1
        if transitionProgress >= transitionFrames {
            currentWidth = targetWidth
            updateShelf(for: currentWidth)
        } else {
            let fraction = Double(transitionProgress) / Double(transitionFrames)
            currentWidth = transitionStartWidth + (targetWidth - transitionStartWidth) * fraction
        }
        return currentWidth
    }

    private func sanitize(_ v: Double) -> Double {
        !v.isFinite || abs(v) < 1e-15 ? 0 : v
    }

    private mutating func updateRateTerms() {
        let w0 = 2.0 * Double.pi * Self.shelfCornerHz / sampleRate
        cosW0 = cos(w0)
        alpha = sin(w0) / 2.0.squareRoot()
    }

    /// The shelf for a given width: linear gain `1 + 2(w-1)` above the
    /// corner, unity below it, identity at 100% and under.
    private mutating func updateShelf(for width: Double) {
        let gain = 1.0 + 2.0 * max(0.0, width - Self.neutral)
        let amplitude = gain.squareRoot()  // RBJ's A: 10^(dB / 40)
        let rootA = amplitude.squareRoot()
        let plus = amplitude + 1
        let minus = amplitude - 1
        let a0 = plus - minus * cosW0 + 2 * rootA * alpha
        b0 = amplitude * (plus + minus * cosW0 + 2 * rootA * alpha) / a0
        b1 = -2 * amplitude * (minus + plus * cosW0) / a0
        b2 = amplitude * (plus + minus * cosW0 - 2 * rootA * alpha) / a0
        a1 = 2 * (minus - plus * cosW0) / a0
        a2 = (plus - minus * cosW0 - 2 * rootA * alpha) / a0
    }
}
