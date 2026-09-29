import SwiftUI
import TappyCore

/// One entity on screen: pops in with a spring, wiggles gently, then fades
/// out and reports back so the state can drop it. Tapping the entity makes
/// it bounce, spin, and replay its sound and name.
struct EntityView: View {
    let entity: EntityInstance
    /// Seconds the entity stays visible before fading out.
    var lifetime: TimeInterval = 4.0
    /// Scene-specific idle motion (hop in the forest, sway in the meadow).
    var action: IdleAction = .hop
    /// Show the localized name badge — the flashcard cue. Parents can
    /// turn it off in settings.
    var showName: Bool = true
    /// Live check for parade mode; while it returns true the lifetime
    /// countdown is frozen so the marching row does not dissolve.
    var isParading: () -> Bool = { false }
    var onExpire: () -> Void

    @State private var appeared = false
    @State private var fading = false
    @State private var wiggle = false
    @State private var bounced = false
    @State private var spin = 0.0
    @State private var nameVisible = false
    /// Bumped on every showLabel() so `.task(id:)` restarts the hide
    /// countdown, cancelling any pending fade from an earlier show.
    @State private var nameGeneration = 0

    var body: some View {
        // The badge sits OUTSIDE IdleMotion on purpose: the text must
        // not hop/rock/spin with the artwork, only the bounce scale
        // (applied below) may carry it.
        VStack(spacing: 2) {
            artwork
                .shadow(color: .black.opacity(0.15), radius: 6, y: 4)
                .modifier(IdleMotion(action: action, wiggle: wiggle,
                                     baseRotation: entity.baseRotation, spin: spin))
            if showName {
                nameBadge
            }
        }
        .scaleEffect(appeared ? (bounced ? 1.3 : 1) : 0.01)
        .offset(y: appeared ? -16 : 30)
        .opacity(fading ? 0 : (appeared ? 1 : 0))
        .accessibilityLabel(Text(entity.definition.name(for: .current)))
        // Generous hit area: toddlers do not tap precisely.
        .padding(24)
        .contentShape(Rectangle())
        .onTapGesture(perform: react)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                appeared = true
            }
            let cycle: Double = action == .hop ? 0.5 : 1.4
            startWiggle(cycle: cycle)
            showLabel()
        }
        // Lifetime countdown as a .task so SwiftUI cancels it the
        // moment the view leaves the hierarchy (cap eviction, theme
        // switch) — a bare Task would keep polling for a dead view.
        .task {
            // Count down the lifetime, but only while the parade is
            // not running — marching entities stay until it ends.
            var waited: Double = 0
            while waited < lifetime, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                if !isParading() { waited += 0.25 }
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { fading = true }
            try? await Task.sleep(for: .seconds(0.5))
            onExpire()
        }
        // Name badge countdown: restarting on every showLabel() keeps
        // the label up through quick re-taps.
        .task(id: nameGeneration) {
            guard nameGeneration > 0 else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { nameVisible = false }
            SmokeMode.log("badge hide")
        }
        // A scene switch swaps the idle action; restart the idle
        // animation so its rhythm (and the modifier's amplitudes,
        // which are just values now) follow the new scene.
        .onChange(of: action) { _, newAction in
            startWiggle(cycle: newAction == .hop ? 0.5 : 1.4)
        }
    }

    /// (Re)starts the endless idle animation. `wiggle` toggles so an
    /// already-running animation is replaced with one for the new cycle.
    private func startWiggle(cycle: Double) {
        withAnimation(.easeInOut(duration: cycle).repeatForever(autoreverses: true)) {
            wiggle.toggle()
        }
    }

    /// Twemoji artwork (rasterized once) when available, SF Symbol
    /// otherwise.
    @ViewBuilder
    private var artwork: some View {
        if let image = EntityArt.image(for: entity.definition) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: entity.size, height: entity.size)
        } else {
            Image(systemName: entity.definition.symbol)
                .font(.system(size: entity.size))
                .foregroundStyle((Color(hex: entity.definition.colorHex) ?? .orange).gradient)
        }
    }

    /// The localized name in a quiet capsule under the artwork. Always
    /// in the hierarchy (no layout jump on show/hide); visibility is
    /// pure opacity.
    private var nameBadge: some View {
        Text(entity.definition.name(for: .current))
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.45), in: Capsule())
            .opacity(nameVisible ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// Shows the name badge and restarts its hide countdown.
    private func showLabel() {
        guard showName else { return }
        withAnimation(.easeIn(duration: 0.25)) { nameVisible = true }
        nameGeneration += 1
        SmokeMode.log("badge show")
    }

    /// Tap reaction: springy bounce, one full spin, replay the entity's
    /// sound and speak its name again.
    private func react() {
        withAnimation(.bouncy(duration: 0.35)) { bounced = true }
        withAnimation(.easeInOut(duration: 0.6)) { spin += 360 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.bouncy(duration: 0.35)) { bounced = false }
        }
        showLabel()
        SoundPlayer.announce(entity.definition)
    }
}

/// Scene-specific idle motion: hopping in the forest, swaying (with a
/// slow drift) in the meadow.
///
/// Deliberately ONE fixed view shape: the scene's action only picks the
/// amplitudes. A `switch` here would emit different view branches, so a
/// scene switch would swap view identity and kill the repeatForever
/// wiggle animation — entities froze mid-pose after switching scenes.
private struct IdleMotion: ViewModifier {
    let action: IdleAction
    let wiggle: Bool
    let baseRotation: Double
    let spin: Double

    /// Tilt amplitude: a hop bounces subtly, a sway rocks visibly.
    private var tilt: Double { action == .hop ? 4 : 10 }
    /// Horizontal drift belongs to the sway; the hop moves vertically.
    private var driftX: CGFloat { action == .sway ? (wiggle ? 8 : -8) : 0 }
    private var liftY: CGFloat { action == .hop ? (wiggle ? -18 : 0) : 0 }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(baseRotation + spin + (wiggle ? tilt : -tilt)))
            .offset(x: driftX, y: liftY)
    }
}
