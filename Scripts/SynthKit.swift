// Shared synthesis toolkit for the Scripts/synth-*.swift generators.
// Plain 16-bit PCM WAV written by hand, so no external tools are needed.
// An entry point is compiled together with this file:
//   swiftc Scripts/SynthKit.swift Scripts/synth-sounds.swift -o /tmp/synth && /tmp/synth
import Foundation

let sampleRate = 44100.0

func seconds(_ s: Double) -> Int { Int(s * sampleRate) }

/// Writes mono Float32 samples as a 16-bit PCM WAV file.
func writeWAV(_ samples: [Float], to name: String, into outDir: String) {
    var data = Data()
    let dataSize = UInt32(samples.count * 2)

    func u32(_ v: UInt32) { var v = v.littleEndian; data.append(Data(bytes: &v, count: 4)) }
    func u16(_ v: UInt16) { var v = v.littleEndian; data.append(Data(bytes: &v, count: 2)) }

    data.append("RIFF".data(using: .ascii)!); u32(36 + dataSize); data.append("WAVE".data(using: .ascii)!)
    data.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
    u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
    data.append("data".data(using: .ascii)!); u32(dataSize)
    for s in samples {
        let clamped = max(-1, min(1, s))
        u16(UInt16(bitPattern: Int16(clamped * 32767)))
    }
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).wav"))
    print("wrote \(name).wav (\(samples.count) samples)")
}

/// Applies a percussive envelope: fast attack, exponential decay.
func envelope(_ samples: inout [Float], attack: Double = 0.005, decay: Double = 6) {
    let attackN = max(1, Int(attack * sampleRate))
    for i in samples.indices {
        let env: Float
        if i < attackN {
            env = Float(i) / Float(attackN)
        } else {
            env = exp(-Float(decay) * Float(i - attackN) / Float(samples.count))
        }
        samples[i] *= env
    }
}

func normalize(_ samples: inout [Float], to peak: Float = 0.7) {
    let maxAmp = samples.map(abs).max() ?? 1
    guard maxAmp > 0 else { return }
    let gain = peak / maxAmp
    for i in samples.indices { samples[i] *= gain }
}

/// Sine tone with a pitch sweep from f0 to f1 over the whole duration,
/// with optional FM vibrato.
func sweep(f0: Double, f1: Double, duration: Double, vibrato: Double = 0) -> [Float] {
    let n = Int(duration * sampleRate)
    var phase = 0.0
    return (0..<n).map { i in
        let t = Double(i) / sampleRate
        let f = f0 + (f1 - f0) * t / duration
        let vib = vibrato * sin(2 * .pi * 30 * t)
        phase += 2 * .pi * (f + vib) / sampleRate
        return Float(sin(phase))
    }
}

/// Concatenates clips with a short gap between them (no trailing gap).
func concat(_ parts: [[Float]], gap: Double = 0.04) -> [Float] {
    let gapN = Int(gap * sampleRate)
    var out: [Float] = []
    for (i, part) in parts.enumerated() {
        out += part
        if i < parts.count - 1 { out += [Float](repeating: 0, count: gapN) }
    }
    return out
}
