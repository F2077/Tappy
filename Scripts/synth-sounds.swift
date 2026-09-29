// Generates the synthesized entity sounds for the default pack and trims
// the bird ambience. Compile together with the shared toolkit:
//   swiftc Scripts/SynthKit.swift Scripts/synth-sounds.swift -o /tmp/synth && /tmp/synth
import Foundation
import AVFoundation

@main
enum SynthSounds {
    static let outDir = "Sources/TappyCore/Resources/Packs/Default.tappypack/sounds"

    static func main() throws {
        try run()
    }

    // MARK: - Synthesized sounds

    static func run() throws {

    // fish: three rising bubble blips
    do {
        var s = concat([sweep(f0: 500, f1: 900, duration: 0.08),
                        sweep(f0: 600, f1: 1100, duration: 0.08),
                        sweep(f0: 750, f1: 1400, duration: 0.10)])
        envelope(&s, decay: 10); normalize(&s); writeWAV(s, to: "fish", into: outDir)
    }

    // rabbit: springy boing (pitch dips then rises)
    do {
        var s = concat([sweep(f0: 400, f1: 220, duration: 0.12),
                        sweep(f0: 220, f1: 500, duration: 0.16)], gap: 0.0)
        envelope(&s, decay: 5); normalize(&s); writeWAV(s, to: "rabbit", into: outDir)
    }

    // turtle: slow low plop
    do {
        var s = sweep(f0: 240, f1: 160, duration: 0.45)
        envelope(&s, attack: 0.06, decay: 4); normalize(&s, to: 0.6); writeWAV(s, to: "turtle", into: outDir)
    }

    // ant: two tiny high ticks
    do {
        var s = concat([sweep(f0: 2600, f1: 2600, duration: 0.03),
                        sweep(f0: 2800, f1: 2800, duration: 0.03)])
        envelope(&s, decay: 30); normalize(&s, to: 0.5); writeWAV(s, to: "ant", into: outDir)
    }

    // ladybug: three fluttery mid-high chirps
    do {
        var s = concat([sweep(f0: 1800, f1: 2200, duration: 0.05, vibrato: 60),
                        sweep(f0: 1800, f1: 2200, duration: 0.05, vibrato: 60),
                        sweep(f0: 1900, f1: 2400, duration: 0.06, vibrato: 60)])
        envelope(&s, decay: 20); normalize(&s, to: 0.5); writeWAV(s, to: "ladybug", into: outDir)
    }

    // lizard: quick descending chirp
    do {
        var s = sweep(f0: 1900, f1: 800, duration: 0.14, vibrato: 90)
        envelope(&s, decay: 10); normalize(&s, to: 0.6); writeWAV(s, to: "lizard", into: outDir)
    }

    // bear: soft low grunt (fundamental + gentle second harmonic)
    do {
        var base = sweep(f0: 130, f1: 90, duration: 0.35)
        let harm = sweep(f0: 260, f1: 180, duration: 0.35)
        for i in base.indices { base[i] = base[i] * 0.8 + harm[i] * 0.2 }
        envelope(&base, attack: 0.03, decay: 5); normalize(&base, to: 0.65); writeWAV(base, to: "bear", into: outDir)
    }

    // forest accent: two soft woody knocks (mushroom forest events)
    do {
        var s = concat([sweep(f0: 320, f1: 200, duration: 0.09),
                        sweep(f0: 280, f1: 180, duration: 0.11)], gap: 0.08)
        envelope(&s, decay: 8); normalize(&s, to: 0.55); writeWAV(s, to: "accent-forest", into: outDir)
    }

    // meadow accent: soft high bell (misty meadow events)
    do {
        var base = sweep(f0: 880, f1: 860, duration: 0.7)
        let harm = sweep(f0: 1320, f1: 1300, duration: 0.7)
        for i in base.indices { base[i] = base[i] * 0.85 + harm[i] * 0.15 }
        envelope(&base, attack: 0.01, decay: 3); normalize(&base, to: 0.5)
        writeWAV(base, to: "accent-meadow", into: outDir)
    }

    // MARK: - Bird: trim the 30s CC0 ambience to a short clip

    let birdSrc = URL(fileURLWithPath: "/tmp/tappy-sfx/birds.mp3")
    if FileManager.default.fileExists(atPath: birdSrc.path) {
        let file = try AVAudioFile(forReading: birdSrc)
        let frameCount = AVAudioFrameCount(sampleRate * 2.5)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)!
        try file.read(into: buf, frameCount: frameCount)
        // Downmix to mono Float.
        var samples = [Float](repeating: 0, count: Int(buf.frameLength))
        let channels = Int(file.processingFormat.channelCount)
        for c in 0..<channels {
            if let data = buf.floatChannelData?[c] {
                for i in samples.indices { samples[i] += data[i] / Float(channels) }
            }
        }
        // Gentle fade-out on the tail so the cut is not audible.
        let fadeN = Int(sampleRate * 0.4)
        for i in 0..<min(fadeN, samples.count) {
            samples[samples.count - 1 - i] *= Float(i) / Float(fadeN)
        }
        normalize(&samples, to: 0.6)
        writeWAV(samples, to: "bird", into: outDir)
    } else {
        print("skip bird: /tmp/tappy-sfx/birds.mp3 not found")
    }

    print("done")
    }
}
