import Accelerate
import CoreAudio
import Foundation

/// What the render thread noticed, for whoever asks later.
///
/// None of this changes a sample. It exists because the render thread is the
/// only place several questions can be answered at all — whether the tap is
/// delivering anything, whether the chain is producing more than fits, how long
/// the room has been quiet — and every one of them turned out to be the fact
/// that settled a real defect. Kept together because they share a rule that
/// nothing else in the processor shares: written on the audio thread, read from
/// the main one, and deliberately unsynchronised.
///
/// That rule is safe for exactly these fields and would not be for the audio
/// state. Each is a single word, written by one thread and read by another that
/// only ever draws a report with it; a reader that catches a stale value asks
/// again a moment later and gets the new one. A lock on every block would cost
/// more than the facts are worth, and a lock on the audio thread is the thing
/// the whole design is arranged to avoid.
struct RenderObservations {

    /// Progress, including silent callbacks. Published under the processor's
    /// observation lock so the recovery timer never reads render state directly.
    var callbackCount: UInt64 = 0

    /// Whether the tap has ever delivered anything but digital silence.
    ///
    /// It exists because a tap can be created without permission. It reports a
    /// plausible format, the aggregate runs, the IO proc fires — and every
    /// sample is zero, while `muteBehavior` silences every other process at the
    /// hardware. Nothing in the Core Audio API tells that apart from a Mac that
    /// happens to be quiet, so the engine watches for it instead.
    var hasReceivedAudio = false

    /// How long the tap has delivered nothing but digital zero.
    ///
    /// Reset by the first non-zero sample, so it measures the *current* run of
    /// silence rather than a total. `IdlePolicy` uses it to decide when the
    /// audio path can be released — which is why it counts exact zeros and not
    /// "quiet": a passage at -60 dB is still someone listening, and stopping
    /// under them is the failure that matters here.
    var silentSeconds: Double = 0

    /// The loudest sample the EQ has produced since the engine started, and how
    /// many left the representable range.
    ///
    /// A boosted preset can ask for more headroom than the signal has, and the
    /// result is distortion the user hears as noise rather than as loudness.
    /// Nothing else can settle it: the mix level arriving at a tap is unknowable
    /// from inside it, so the only way to know whether eqR is clipping is to
    /// look at what eqR produced.
    var peakLevel: Float = 0
    var clippedSamples = 0

    /// Loudest sample the chain was *handed*, this block and this session.
    ///
    /// Without it the output peak cannot be attributed. The system mix is
    /// Float32 and is not clamped before a tap sees it, so audio can arrive
    /// above full scale on its own — and at Flat, where every band is identity
    /// and the trim is unity, eqR passes it through bit for bit. Counting
    /// that as clipping blamed the app for the material, and told the user to
    /// lower a preamp that Auto had disabled.
    var blockSourcePeak: Float = 0
    var sourcePeakLevel: Float = 0

    /// Forgets everything. Called when the engine starts, because every one of
    /// these is a claim about the audio path that is now being rebuilt.
    mutating func reset() {
        callbackCount = 0
        hasReceivedAudio = false
        silentSeconds = 0
        peakLevel = 0
        clippedSamples = 0
        blockSourcePeak = 0
        sourcePeakLevel = 0
    }

    /// The level this block was handed, from `BufferRouter.place`.
    mutating func note(sourcePeak: Float) {
        blockSourcePeak = sourcePeak
        if sourcePeak > sourcePeakLevel { sourcePeakLevel = sourcePeak }
    }

    /// Notes a block of input: whether the tap carried anything, and how much
    /// time passed if it did not.
    ///
    /// Only the tap's buffers count. On a duplex device the input list also
    /// carries the device's own microphone, and room noise there would prove a
    /// tap that delivers nothing and keep an idle Mac awake.
    mutating func observe(signal: Bool, seconds: Double) {
        if signal {
            hasReceivedAudio = true
            silentSeconds = 0
        } else {
            silentSeconds += seconds
        }
    }

    /// Notes what the chain produced on one channel.
    ///
    /// The peak is kept for the life of the engine rather than per block — the
    /// question is whether this ever happened, and a value that decays answers
    /// it only for whoever is watching at the time.
    mutating func observe(output samples: UnsafePointer<Float>, stride: Int, frames: Int) {
        guard frames > 0 else { return }
        var maxSample: Float = 0
        vDSP_maxmgv(samples, stride, &maxSample, vDSP_Length(frames))
        if maxSample > peakLevel { peakLevel = maxSample }

        // What counts as ours. Above full scale, and above what arrived: a
        // sample the chain did not lift past the ceiling is the material's to
        // answer for, not the app's, and saying otherwise sends the user after
        // a control that will not help.
        let ceiling = max(1.0, blockSourcePeak)
        if maxSample > ceiling {
            var clipped = 0
            var index = 0
            for _ in 0..<frames {
                let magnitude = abs(samples[index])
                if magnitude > ceiling { clipped &+= 1 }
                index += stride
            }
            clippedSamples &+= clipped
        }
    }
}
