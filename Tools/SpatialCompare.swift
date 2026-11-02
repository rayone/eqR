// Renders one music clip three ways for a blind-ish listening comparison:
//
//   1-original.wav       the clip as it is
//   2-eqr-3d-200.wav     eqR's own widener at 200%, the exact file the app runs
//   3-apple-speakers.wav Apple's spatial renderer (AUSpatialMixer, via
//                        AVAudioEnvironmentNode) set to the Mac's built-in
//                        speakers, with left and right placed as two virtual
//                        speakers wider than the real ones
//
// All three are loudness-matched (same RMS) and then scaled by one common gain
// so none clips, so "louder" cannot win the comparison. Nothing here touches
// the app or its settings; it reads a file and writes three files.
//
// Usage: build/spatial-compare <music file> [start seconds] [azimuth degrees]

import AVFoundation
import Foundation

let sampleRate = 48_000.0
let clipSeconds = 30.0

struct Stereo {
    var left: [Float]
    var right: [Float]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

/// Reads `seconds` of `url` from `start`, as 48 kHz stereo float.
func readClip(_ url: URL, start: Double) -> Stereo {
    guard let file = try? AVAudioFile(forReading: url) else { fail("cannot open \(url.path)") }
    let source = file.processingFormat
    let startFrame = AVAudioFramePosition(start * source.sampleRate)
    guard startFrame < file.length else { fail("start is past the end of the file") }
    file.framePosition = startFrame
    let wanted = AVAudioFrameCount(min(Double(file.length - startFrame), clipSeconds * source.sampleRate))
    guard let raw = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: wanted),
        (try? file.read(into: raw, frameCount: wanted)) != nil
    else { fail("cannot read \(url.path)") }

    let target = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    guard let converter = AVAudioConverter(from: source, to: target) else { fail("no converter") }
    let capacity = AVAudioFrameCount(Double(raw.frameLength) * sampleRate / source.sampleRate) + 1_024
    let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)!
    var fed = false
    var error: NSError?
    converter.convert(to: out, error: &error) { _, status in
        if fed { status.pointee = .endOfStream; return nil }
        fed = true
        status.pointee = .haveData
        return raw
    }
    if let error { fail("conversion failed: \(error)") }

    let frames = Int(out.frameLength)
    let channels = out.floatChannelData!
    // A mono file is duplicated so every variant starts from the same pair.
    let right = source.channelCount > 1 ? channels[1] : channels[0]
    return Stereo(
        left: Array(UnsafeBufferPointer(start: channels[0], count: frames)),
        right: Array(UnsafeBufferPointer(start: right, count: frames)))
}

/// eqR's widener at 200%, run block by block the way the render path runs it.
func eqrWiden(_ input: Stereo) -> Stereo {
    var widener = StereoWidener(sampleRate: sampleRate)
    var protection = OutputProtection(sampleRate: sampleRate)
    widener.setWidth(2.0)
    var out = input
    let block = 512
    // Settle the width first so the clip is 200% from its first sample.
    var silenceLeft = [Float](repeating: 0, count: block)
    var silenceRight = silenceLeft
    silenceLeft.withUnsafeMutableBufferPointer { left in
        silenceRight.withUnsafeMutableBufferPointer { right in
            guard let l = left.baseAddress, let r = right.baseAddress else { return }
            for _ in 0..<40 {
                widener.process(l, leftStride: 1, r, rightStride: 1, frames: block)
            }
        }
    }
    widener.reset()
    var start = 0
    out.left.withUnsafeMutableBufferPointer { l in
        out.right.withUnsafeMutableBufferPointer { r in
            while start < l.count {
                let frames = min(block, l.count - start)
                widener.process(
                    l.baseAddress! + start, leftStride: 1,
                    r.baseAddress! + start, rightStride: 1, frames: frames)
                protection.process(
                    l.baseAddress! + start, leftStride: 1,
                    r.baseAddress! + start, rightStride: 1, frames: frames, ceiling: 1)
                start += frames
            }
        }
    }
    // Containment runs before final loudness matching, just as in the app.
    return out
}

/// Apple's spatial renderer: left and right as two point sources at ±azimuth,
/// one metre away, rendered for the Mac's built-in speakers. Offline, so it is
/// deterministic and runs faster than real time.
func appleSpatial(_ input: Stereo, azimuth: Double) -> Stereo {
    let engine = AVAudioEngine()
    let environment = AVAudioEnvironmentNode()
    let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    let frames = input.left.count

    engine.attach(environment)
    environment.outputType = .builtInSpeakers
    environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
    // Sources sit at the reference distance, so distance attenuation is 0 dB.
    environment.distanceAttenuationParameters.referenceDistance = 1
    environment.reverbParameters.enable = false

    var players: [AVAudioPlayerNode] = []
    for (samples, sign) in [(input.left, -1.0), (input.right, 1.0)] {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: environment, format: mono)
        let radians = azimuth * .pi / 180
        // Listener faces -z; negative x is to the left.
        player.position = AVAudio3DPoint(
            x: Float(sign * sin(radians)), y: 0, z: Float(-cos(radians)))
        player.renderingAlgorithm = .auto  // follows outputType
        player.sourceMode = .pointSource
        player.pointSourceInHeadMode = .bypass
        let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: frames)
        }
        player.scheduleBuffer(buffer, at: nil)
        players.append(player)
    }
    engine.connect(environment, to: engine.mainMixerNode, format: stereo)

    let block: AVAudioFrameCount = 4_096
    do {
        try engine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: block)
        try engine.start()
    } catch { fail("could not start the offline engine: \(error)") }
    players.forEach { $0.play() }

    let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: block)!
    var result = Stereo(left: [], right: [])
    result.left.reserveCapacity(frames)
    result.right.reserveCapacity(frames)
    while result.left.count < frames {
        let wanted = min(block, AVAudioFrameCount(frames - result.left.count))
        guard (try? engine.renderOffline(wanted, to: out)) == .success else {
            fail("offline render stopped early")
        }
        let n = Int(out.frameLength)
        let channels = out.floatChannelData!
        result.left += UnsafeBufferPointer(start: channels[0], count: n)
        result.right += UnsafeBufferPointer(start: channels[1], count: n)
    }
    engine.stop()
    return result
}

func rms(_ s: Stereo) -> Double {
    let sum = zip(s.left, s.right).reduce(0.0) { $0 + Double($1.0 * $1.0 + $1.1 * $1.1) }
    return (sum / Double(2 * max(1, s.left.count))).squareRoot()
}

func peak(_ s: Stereo) -> Float {
    max(s.left.map(abs).max() ?? 0, s.right.map(abs).max() ?? 0)
}

func scaled(_ s: Stereo, _ gain: Float) -> Stereo {
    Stereo(left: s.left.map { $0 * gain }, right: s.right.map { $0 * gain })
}

func write(_ s: Stereo, to url: URL) {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(s.left.count))!
    buffer.frameLength = AVAudioFrameCount(s.left.count)
    buffer.floatChannelData![0].update(from: s.left, count: s.left.count)
    buffer.floatChannelData![1].update(from: s.right, count: s.right.count)
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 24,
        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
    ]
    do {
        let file = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    } catch { fail("cannot write \(url.path): \(error)") }
}

/// How much of the signal is in the difference between the channels, in dB
/// relative to the sum: a rough number for how wide a file is.
func sideToMidDB(_ s: Stereo) -> Double {
    var mid = 0.0
    var side = 0.0
    for (l, r) in zip(s.left, s.right) {
        mid += Double((l + r) * (l + r))
        side += Double((l - r) * (l - r))
    }
    return 10 * log10(max(side, 1e-12) / max(mid, 1e-12))
}

@main
enum SpatialCompare {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2, !arguments[1].isEmpty else {
            fail("usage: spatial-compare <music file> [start seconds] [azimuth degrees]")
        }
        let input = URL(fileURLWithPath: arguments[1])
        let start = arguments.count > 2 ? Double(arguments[2]) ?? 30 : 30
        let azimuth = arguments.count > 3 ? Double(arguments[3]) ?? 60 : 60

        let original = readClip(input, start: start)
        var variants: [(name: String, audio: Stereo)] = [
            ("1-original", original),
            ("2-eqr-3d-200", eqrWiden(original)),
            ("3-apple-speakers", appleSpatial(original, azimuth: azimuth)),
        ]

        // Same loudness for all three, then one shared gain so the loudest peak
        // sits at -1 dBFS: no file is louder, and none clips.
        let reference = rms(original)
        variants = variants.map {
            ($0.name, scaled($0.audio, Float(reference / max(rms($0.audio), 1e-12))))
        }
        let common = Float(0.891) / (variants.map { peak($0.audio) }.max() ?? 1)
        variants = variants.map { ($0.name, scaled($0.audio, min(1, common))) }

        let outDir = URL(fileURLWithPath: "build/spatial-compare-out", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        print(
            "clip: \(input.lastPathComponent), \(Int(clipSeconds)) s from \(Int(start)) s;"
                + " Apple azimuth ±\(Int(azimuth))°")
        for variant in variants {
            let url = outDir.appendingPathComponent("\(variant.name).wav")
            write(variant.audio, to: url)
            let line = String(
                format: "%-18@ side/mid %+6.1f dB   peak %5.1f dBFS   %@",
                variant.name as NSString, sideToMidDB(variant.audio),
                20 * log10(Double(peak(variant.audio))), url.path as NSString)
            print(line)
        }
    }
}
