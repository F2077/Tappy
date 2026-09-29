import SwiftUI
import TappyCore

/// Scene background. Two bespoke hand-coded looks ship as built-in
/// renderers; packs without a `renderer` get the data-driven
/// `GenericScene` (gradient + ground + SVG decorations + particles),
/// so new scenes never need new code. No Canvas anywhere — its per-frame
/// render closures proved unstable under the AttributeGraph on this
/// toolchain; motion comes from repeat-forever view animations.
struct SceneView: View, Equatable {
    let scene: SceneDefinition
    // SceneDefinition's == is id-based, and every visual input
    // (renderer, packURL) is a function of the id's entry in the merged
    // catalog — so an unchanged id really means an unchanged backdrop.

    var body: some View {
        GeometryReader { geo in
            switch scene.renderer {
            case .mushroomForest: MushroomForest(size: geo.size)
            case .mistyMeadow: MistyMeadow(size: geo.size)
            case .generic(let spec):
                GenericScene(spec: spec, packURL: scene.packURL, size: geo.size)
            }
        }
    }
}

// MARK: - Generic pack-defined scene

/// Renders a `GenericSceneSpec`: gradient sky, optional ground band,
/// placed SVG decorations with a motion each, ambient particles.
private struct GenericScene: View {
    let spec: GenericSceneSpec
    let packURL: URL
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: spec.gradient.map { Color(hex: $0) ?? .blue.opacity(0.4) },
                startPoint: .top, endPoint: .bottom
            )

            if let ground = spec.ground {
                Rectangle()
                    .fill(Color(hex: ground.color) ?? .green)
                    .frame(width: size.width,
                           height: size.height * ground.height)
                    .position(x: size.width / 2,
                              y: size.height * (1 - ground.height / 2))
            }

            ForEach(Array(spec.decorations.enumerated()), id: \.offset) { index, d in
                if let image = EntityArt.image(at: packURL.appending(path: d.art)) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110 * d.scale, height: 110 * d.scale)
                        .modifier(DecorationMotion(kind: d.motion,
                                                   phase: Double(index) * 1.3))
                        .position(x: d.x * size.width, y: d.y * size.height)
                }
            }

            if let particles = spec.particles {
                switch particles.kind {
                case .fireflies:
                    Fireflies(count: max(particles.count, 0), size: size)
                case .mist:
                    ForEach(0..<max(particles.count, 0), id: \.self) { i in
                        MistBand(width: size.width * (0.7 + 0.2 * CGFloat(i % 3)),
                                 travel: size.width, phase: Double(i))
                            .position(x: 0, y: size.height * (0.45 + 0.5 * pseudoRandom(i, 2)))
                    }
                }
            }
        }
    }

}
private struct DecorationMotion: ViewModifier {
    let kind: GenericSceneSpec.Motion
    let phase: Double
    @State private var on = false

    func body(content: Content) -> some View {
        switch kind {
        case .none:
            content
        case .sway:
            content
                .rotationEffect(.degrees(on ? 2.5 : -2.5))
                .onAppear { animate(duration: 1.6) }
        case .drift:
            content
                .offset(x: on ? 16 : -16, y: on ? -8 : 8)
                .onAppear { animate(duration: 3.2) }
        case .pulse:
            content
                .scaleEffect(on ? 1.08 : 0.94)
                .onAppear { animate(duration: 1.2) }
        }
    }

    private func animate(duration: Double) {
        withAnimation(.easeInOut(duration: duration)
            .repeatForever(autoreverses: true)
            .delay(phase * 0.3)) {
            on = true
        }
    }
}

// MARK: - Mushroom forest (蘑菇丛林)

private struct MushroomForest: View {
    let size: CGSize

    private let mushrooms: [(x: CGFloat, y: CGFloat, scale: CGFloat, cap: Color)] = [
        (0.12, 0.82, 1.1, Color(red: 0.90, green: 0.30, blue: 0.25)),
        (0.28, 0.87, 0.7, Color(red: 0.95, green: 0.60, blue: 0.30)),
        (0.55, 0.84, 1.3, Color(red: 0.90, green: 0.30, blue: 0.25)),
        (0.72, 0.88, 0.8, Color(red: 0.65, green: 0.45, blue: 0.80)),
        (0.90, 0.83, 1.0, Color(red: 0.95, green: 0.60, blue: 0.30)),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.16, green: 0.38, blue: 0.36),
                Color(red: 0.10, green: 0.30, blue: 0.22),
            ], startPoint: .top, endPoint: .bottom)

            // Back hills.
            Ellipse()
                .fill(Color(red: 0.13, green: 0.42, blue: 0.28))
                .frame(width: size.width * 1.4, height: size.height * 0.6)
                .position(x: size.width * 0.5, y: size.height * 0.92)
            Ellipse()
                .fill(Color(red: 0.17, green: 0.50, blue: 0.32))
                .frame(width: size.width * 1.5, height: size.height * 0.55)
                .position(x: size.width * 0.4, y: size.height * 1.02)

            // Ground.
            Rectangle()
                .fill(Color(red: 0.22, green: 0.56, blue: 0.34))
                .frame(width: size.width, height: size.height * 0.18)
                .position(x: size.width / 2, y: size.height * 0.91)

            ForEach(Array(mushrooms.enumerated()), id: \.offset) { index, m in
                Mushroom(cap: m.cap)
                    .frame(width: 110 * m.scale, height: 110 * m.scale)
                    .modifier(DecorationMotion(kind: .sway, phase: Double(index) * 1.3))
                    .position(x: m.x * size.width, y: m.y * size.height)
            }

            Fireflies(count: 10, size: size)
        }
    }
}

/// Cartoon mushroom: dotted half-ellipse cap on a cream stem.
private struct Mushroom: View {
    let cap: Color

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Top half of an ellipse, clipped to cap height.
                Ellipse()
                    .fill(cap)
                    .frame(width: 110, height: 84)
                    .offset(y: 21)
                // Dots.
                Circle().fill(.white.opacity(0.9)).frame(width: 14).offset(x: -26, y: -6)
                Circle().fill(.white.opacity(0.9)).frame(width: 16).offset(x: 8, y: -16)
                Circle().fill(.white.opacity(0.9)).frame(width: 11).offset(x: 30, y: 2)
            }
            .frame(width: 110, height: 42)
            .clipped()
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.97, green: 0.93, blue: 0.82))
                .frame(width: 36, height: 55)
                .offset(y: -4)
        }
    }
}

/// The firefly ambient layer shared by the generic renderer and the
/// bespoke mushroom forest: a deterministic pseudo-random layout of
/// drifting dots.
private struct Fireflies: View {
    let count: Int
    let size: CGSize

    var body: some View {
        ForEach(0..<count, id: \.self) { i in
            Firefly(phase: Double(i) * 0.7)
                .position(x: (0.08 + 0.84 * pseudoRandom(i, 0)) * size.width,
                          y: (0.12 + 0.45 * pseudoRandom(i, 1)) * size.height)
        }
    }
}

/// Deterministic pseudo-random in 0...1 from an index — stable layouts
/// without storing state.
private func pseudoRandom(_ i: Int, _ salt: Int) -> CGFloat {
    let v = sin(Double(i * 37 + salt * 91) * 12.9898) * 43758.5453
    return CGFloat(v - v.rounded(.down))
}

/// A drifting, pulsing firefly dot.
private struct Firefly: View {
    let phase: Double
    @State private var glowing = false
    @State private var drifting = false

    var body: some View {
        Circle()
            .fill(.yellow.opacity(glowing ? 0.65 : 0.15))
            .frame(width: 8, height: 8)
            .offset(x: drifting ? 14 : -14, y: drifting ? -10 : 10)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4)
                    .repeatForever(autoreverses: true).delay(phase * 0.4)) {
                    glowing = true
                }
                withAnimation(.easeInOut(duration: 3.2)
                    .repeatForever(autoreverses: true).delay(phase * 0.7)) {
                    drifting = true
                }
            }
    }
}

// MARK: - Misty meadow (朝雾草原)

private struct MistyMeadow: View {
    let size: CGSize

    private let flowers: [(x: CGFloat, y: CGFloat, color: Color)] = [
        (0.15, 0.90, .pink), (0.30, 0.85, .orange), (0.45, 0.92, .purple),
        (0.62, 0.87, .pink), (0.78, 0.91, .orange), (0.90, 0.86, .purple),
    ]

    var body: some View {
        ZStack {
            // Morning sky.
            LinearGradient(colors: [
                Color(red: 0.72, green: 0.86, blue: 0.93),
                Color(red: 0.96, green: 0.93, blue: 0.82),
            ], startPoint: .top, endPoint: .bottom)

            // Sun with glow.
            Circle()
                .fill(Color(red: 1.0, green: 0.9, blue: 0.5).opacity(0.25))
                .frame(width: size.height * 0.28)
                .position(x: size.width * 0.78, y: size.height * 0.18)
            Circle()
                .fill(Color(red: 1.0, green: 0.88, blue: 0.45))
                .frame(width: size.height * 0.18)
                .position(x: size.width * 0.78, y: size.height * 0.18)

            // Rolling hills.
            Ellipse()
                .fill(Color(red: 0.62, green: 0.80, blue: 0.55))
                .frame(width: size.width * 1.4, height: size.height * 0.68)
                .position(x: size.width * 0.5, y: size.height * 1.0)
            Ellipse()
                .fill(Color(red: 0.52, green: 0.74, blue: 0.46))
                .frame(width: size.width * 1.5, height: size.height * 0.6)
                .position(x: size.width * 0.35, y: size.height * 1.08)

            // Flowers.
            ForEach(Array(flowers.enumerated()), id: \.offset) { _, f in
                Flower(color: f.color)
                    .position(x: f.x * size.width, y: f.y * size.height)
            }

            // Drifting mist bands — the signature of this scene.
            ForEach(0..<3, id: \.self) { i in
                MistBand(width: size.width * (0.7 + 0.2 * CGFloat(i)),
                         travel: size.width, phase: Double(i))
                    .position(x: 0, y: size.height * (0.55 + 0.12 * CGFloat(i)))
            }
        }
    }
}

private struct Flower: View {
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Circle().fill(color).frame(width: 12, height: 12)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.35, green: 0.6, blue: 0.35))
                .frame(width: 3, height: 16)
        }
        .offset(y: -8)
    }
}

/// A translucent mist band endlessly drifting left to right.
private struct MistBand: View {
    let width: CGFloat
    let travel: CGFloat
    let phase: Double
    @State private var x: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 26)
            .fill(.white.opacity(0.30 - 0.05 * phase))
            .frame(width: width, height: 52)
            .position(x: x, y: 0)
            .onAppear {
                x = -width
                withAnimation(.linear(duration: 40 + phase * 12)
                    .repeatForever(autoreverses: false)
                    .delay(phase * 5)) {
                    x = travel + width
                }
            }
    }
}
