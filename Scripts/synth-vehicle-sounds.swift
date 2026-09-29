// Generates the synthesized sounds for the Vehicles pack: one horn /
// siren / engine loop per vehicle plus the two scene accents. Compile
// together with the shared toolkit:
//   swiftc Scripts/SynthKit.swift Scripts/synth-vehicle-sounds.swift -o /tmp/synth-vehicles && /tmp/synth-vehicles
import Foundation

let outDir = "Sources/TappyCore/Resources/Packs/Vehicles.tappypack/sounds"

@main
enum SynthVehicleSounds {
    static func main() {
        run()
    }
}

// MARK: - Pack-specific synthesis helpers

/// Envelope with this pack's clip-flavored defaults (kept as a wrapper
/// so regenerating stays byte-identical with the committed WAVs).
func enveloped(_ samples: [Float], attack: Double = 0.004, decay: Double = 4) -> [Float] {
    var out = samples
    envelope(&out, attack: attack, decay: decay)
    return out
}

/// Smooth fade in/out to avoid clicks on sustained clips.
func faded(_ samples: [Float], fade: Double = 0.02) -> [Float] {
    var out = samples
    let fadeN = max(1, seconds(fade))
    for i in out.indices {
        if i < fadeN { out[i] *= Float(i) / Float(fadeN) }
        if i >= out.count - fadeN { out[i] *= Float(out.count - 1 - i) / Float(fadeN) }
    }
    return out
}

func sine(_ freq: Double, for duration: Double, phase: inout Double) -> [Float] {
    (0..<seconds(duration)).map { _ in
        phase += 2 * .pi * freq / sampleRate
        return Float(sin(phase))
    }
}

/// Sine at a fixed frequency, phase reset per call.
func tone(_ freq: Double, for duration: Double) -> [Float] {
    var phase = 0.0
    return sine(freq, for: duration, phase: &phase)
}

/// Hollow horn color: sine plus a soft 2nd/3rd harmonic.
func horn(_ freq: Double, for duration: Double) -> [Float] {
    var out = tone(freq, for: duration)
    let second = tone(freq * 2, for: duration)
    let third = tone(freq * 3, for: duration)
    for i in out.indices { out[i] += 0.35 * second[i] + 0.15 * third[i] }
    return out
}

/// Rising or falling sweep between two frequencies.
func sweep(from a: Double, to b: Double, for duration: Double) -> [Float] {
    sweep(f0: a, f1: b, duration: duration)
}

var rng: UInt64 = 0x9E3779B97F4A7C15
/// Deterministic pseudo-random noise in [-1, 1].
func noise() -> Float {
    rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
    return Float(Double(rng >> 11) / Double(1 << 53)) * 2 - 1
}

/// Noise passed through a one-pole low-pass for wind/whoosh textures.
func whoosh(for duration: Double, cutoff: Double, swell: Bool) -> [Float] {
    let n = seconds(duration)
    var out = [Float](repeating: 0, count: n)
    var lp: Float = 0
    let alpha = Float(cutoff / sampleRate)
    for i in 0..<n {
        lp += alpha * (noise() - lp)
        let t = Double(i) / Double(n)
        out[i] = lp * (swell ? Float(2 * t) : Float(sin(.pi * t)) + 0.3)
    }
    return out
}

/// Concatenates clips with a short gap (and, unlike concat(), a
/// trailing one — kept so regenerating stays byte-identical).
func joined(_ clips: [[Float]], gap: Double = 0.06) -> [Float] {
    let silence = [Float](repeating: 0, count: seconds(gap))
    return clips.flatMap { $0 + silence }
}
// MARK: - Synthesized sounds

func run() {
    // Car: friendly double beep.
    writeWAV(enveloped(joined([horn(620, for: 0.12), horn(620, for: 0.12)])), to: "car", into: outDir)
    // Taxi: one longer, brighter honk.
    writeWAV(enveloped(horn(780, for: 0.3), decay: 5), to: "taxi", into: outDir)
    // Bus: low double horn.
    writeWAV(enveloped(joined([horn(260, for: 0.2), horn(260, for: 0.3)]), decay: 3), to: "bus", into: outDir)
    // Truck: deep air horn.
    writeWAV(enveloped(horn(150, for: 0.55), decay: 3), to: "truck", into: outDir)
    // Tractor: chugging putt-putt pulses.
    writeWAV(faded(joined((0..<5).map { _ in enveloped(tone(85, for: 0.09), decay: 6) }, gap: 0.05)), to: "tractor", into: outDir)
    // Fire engine: siren sweeping up and back down.
    writeWAV(faded(sweep(from: 400, to: 950, for: 0.5) + sweep(from: 950, to: 400, for: 0.5)), to: "fireEngine", into: outDir)
    // Ambulance: alternating two-tone wail.
    writeWAV(faded(joined([tone(700, for: 0.3), tone(950, for: 0.3), tone(700, for: 0.25)], gap: 0.02)), to: "ambulance", into: outDir)
    // Police car: sharp hi-lo square-ish horn.
    writeWAV(faded(joined([horn(600, for: 0.22), horn(430, for: 0.22), horn(600, for: 0.18)], gap: 0.03)), to: "policeCar", into: outDir)
    // Airplane: swelling engine whoosh with a hum underneath.
    do {
        let dur = 1.0
        var mixed = whoosh(for: dur, cutoff: 900, swell: true)
        let hum = tone(110, for: dur)
        for i in mixed.indices { mixed[i] += 0.3 * hum[i] }
        normalize(&mixed)
        writeWAV(faded(mixed), to: "airplane", into: outDir)
    }
    // Rocket: rumbling liftoff, pitch and noise rising together.
    do {
        let dur = 1.2
        var mixed = whoosh(for: dur, cutoff: 500, swell: true)
        let rumble = sweep(from: 90, to: 320, for: dur)
        for i in mixed.indices { mixed[i] += 0.6 * rumble[i] }
        normalize(&mixed)
        writeWAV(faded(mixed), to: "rocket", into: outDir)
    }
    // Scene accents.
    writeWAV(enveloped(joined([horn(520, for: 0.16), horn(660, for: 0.28)], gap: 0.04), decay: 3), to: "accent-site", into: outDir)
    do {
        // Night launch: soft rising two-note chime.
        let first = tone(660, for: 0.25)
        var second = tone(990, for: 0.45)
        normalize(&second, to: 0.5)
        writeWAV(enveloped(joined([first, second], gap: 0.03), decay: 2.5), to: "accent-night", into: outDir)
    }

}
