import AppKit
import Foundation
import SwiftDraw
import TappyCore

// Micro-benchmarks for the hot paths, runnable without Xcode:
//   swift run -c release TappyBench

Log.bootstrap()

@MainActor
func bench(_ name: String, iterations: Int, body: () -> Void) {
    // Warmup.
    body()
    let clock = ContinuousClock()
    let start = clock.now
    for _ in 0..<iterations { body() }
    let elapsed = clock.now - start
    func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
    let padded = name.padding(toLength: 38, withPad: " ", startingAt: 0)
    // Note: %f takes Double safely; %s would need a C string, not a
    // Swift String (passing one segfaults in NSString formatting).
    print(String(format: "%@%7d ops  total %9.2f ms  per-op %8.4f ms",
                 padded, iterations, ms(elapsed), ms(elapsed / iterations)))
}

@MainActor
func run() {
    SoundPlayer.isEnabled = false
    Speaker.shared.isEnabled = false

    // Spawn throughput (state churn drives every SwiftUI update).
    do {
        let state = GameState()
        state.minSpawnInterval = 0
        state.maxEntities = 40
        bench("GameState.spawn (cap 40)", iterations: 10_000) {
            state.spawn()
        }
    }

    // Parade participant lookup (runs per entity per frame in parade).
    do {
        let state = GameState()
        state.minSpawnInterval = 0
        for _ in 0..<40 { state.spawn() }
        let id = state.entities.last!.id
        bench("GameState.isParadeParticipant", iterations: 100_000) {
            _ = state.isParadeParticipant(id)
        }
    }

    // SVG parse + rasterize (paid once per entity at runtime).
    do {
        let url = PackCatalog.shared.entity("cat")!.artURL!
        let data = try! Data(contentsOf: url)
        // Parse from Data: SVG(fileURL:) answers from a shared URL cache,
        // which would turn this benchmark into a dictionary lookup.
        bench("SVG parse from Data (cat)", iterations: 200) {
            _ = SVG(data: data)
        }
        let svg = SVG(data: data)!
        // rasterize(with:) returns a *lazy* NSImage (drawing handler), so
        // measure pngData() — it allocates a bitmap and draws for real.
        bench("SVG rasterize 512px → PNG (cat)", iterations: 20) {
            _ = try? svg.pngData()
        }
    }

    // Pack catalog cold load: manifest parsing for all built-in packs.
    do {
        bench("PackCatalog init (all packs)", iterations: 50) {
            _ = PackCatalog(userPacksDirectory: nil)
        }
    }
}

run()
