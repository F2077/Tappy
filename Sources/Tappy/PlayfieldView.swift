import SwiftUI
import TappyCore
import AppKit

/// The full-screen playfield: scene background, entities, and the input
/// catcher at the back. Once enough entities are on screen they line up
/// and march across the bottom ("parade mode").
struct PlayfieldView: View {
    let state: GameState
    let settings = SettingsStore.shared

    /// Fixed for the process lifetime (kiosk), so look it up once
    /// instead of on every timeline tick.
    private static let hint = L10n.hintControls

    /// Flips on the first spawn; the empty-state line is a launch-time
    /// framing (and interaction hint), not a permanent caption.
    @State private var interacted = false

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !state.paradeActive)) { timeline in
                content(size: geo.size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            syncSettings()
        }
        .onChange(of: settings.scene) { _, _ in syncSettings() }
        .onChange(of: settings.activePackID) { _, _ in syncSettings() }
        .onChange(of: settings.soundEnabled) { _, _ in syncSettings() }
        .onChange(of: settings.speechEnabled) { _, _ in syncSettings() }
        // Smoke harness observability (no-op outside TAPPY_SMOKE): the
        // script asserts on settings open/close and scene cycling.
        .onChange(of: state.showSettings) { _, open in
            SmokeMode.log("settings \(open ? "open" : "closed")")
        }
        .onChange(of: state.scene) { _, scene in
            SmokeMode.log("scene \(scene.id)")
        }
    }

    /// Settings store → runtime components.
    private func syncSettings() {
        state.scene = settings.scene
        state.activePackID = settings.activePackID
        SoundPlayer.isEnabled = settings.soundEnabled && !SmokeMode.isActive
        Speaker.shared.isEnabled = settings.speechEnabled && !SmokeMode.isActive
    }

    /// Window coordinates (bottom-left origin) → SwiftUI normalized
    /// (top-left). The contract counterpart of InputCatcherView.isFlipped.
    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x / size.width, y: 1 - point.y / size.height)
    }

    private func content(size: CGSize, time: TimeInterval) -> some View {
        // Computed once per frame: parade membership drives every entity's
        // position, and recomputing the participant list per entity would
        // reallocate it 40x per frame at the cap.
        let marchingIDs = Set(state.paradeParticipants.map(\.id))
        return ZStack {
            SceneView(scene: state.scene)

            // Sits at the back: receives all keyboard input and scroll.
            // Mouse clicks go through SwiftUI gestures instead (the tap
            // layer below spawns on the background; entity views claim
            // their own taps). Always in the hierarchy (never removed —
            // see InputCatcherView); deactivated while the settings
            // panel is open.
            InputCatcher(
                active: !state.showSettings,
                onScroll: { point, boost in
                    state.spawn(at: normalized(point, in: size), sizeBoost: 1 + boost, source: "scroll")
                },
                onKey: { state.spawn(source: "key") },
                onSceneCycle: {
                    // Nonisolated by design: captures only state, never
                    // the MainActor view, so the event monitor can call
                    // it without an executor check. Routing through the
                    // settings store persists the choice and keeps the
                    // settings picker in sync after a relaunch.
                    let all = settings.activeScenes.isEmpty
                        ? PackCatalog.shared.scenes
                        : settings.activeScenes
                    if let index = all.firstIndex(of: state.scene) {
                        settings.scene = all[(index + 1) % all.count]
                        SoundPlayer.playAccent(for: settings.scene)
                    }
                },
                onSettings: { state.showSettings = true },
                // ObjC performSelector: no Swift executor checks involved.
                onExit: { NSApp.perform(#selector(NSApplication.terminate), with: nil, afterDelay: 0) }
            )

            // Background tap target: spawns where the toddler clicked.
            // Sits above the input catcher and below the entity views, so
            // SwiftUI hit-testing lets entity taps claim their own clicks.
            Color.clear
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    // Gesture coordinates are already top-left normalized
                    // space — no flip needed (the event-monitor path had
                    // to flip window coordinates; gestures do not).
                    state.spawn(at: CGPoint(
                        x: value.location.x / size.width,
                        y: value.location.y / size.height
                    ), source: "tap")
                })

            ForEach(state.entities) { entity in
                EntityView(entity: entity, action: state.scene.idleAction,
                           // Smoke asserts on badges, so a local
                           // showNames preference must not silence them
                           // in the harness — force the default there.
                           showName: SmokeMode.isActive || settings.showNames,
                           isParading: { marchingIDs.contains(entity.id) }) {
                    state.remove(entity.id)
                }
                .scaleEffect(state.paradeActive ? 0.9 : 1)
                .position(position(for: entity, in: size, time: time, marchingIDs: marchingIDs))
            }

            // Empty-state line: frames the app as learning (and hints
            // the core interaction) until the first entity appears —
            // after that the screen belongs to the child, no captions.
            if !interacted {
                VStack {
                    Spacer()
                    Text(L10n.hintExplore)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.bottom, 60)
                        .padding(.horizontal, 40)
                        .multilineTextAlignment(.center)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // Parent hint, faint enough not to distract the child.
            VStack {
                Spacer()
                Text(Self.hint)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 12)
            }
            .allowsHitTesting(false)
            .onChange(of: state.entities.count) { _, count in
                guard count > 0, !interacted else { return }
                withAnimation(.easeOut(duration: 0.4)) { interacted = true }
            }

            if state.showSettings {
                SettingsView(
                    settings: settings,
                    onClose: { state.showSettings = false },
                    onQuit: { NSApp.terminate(nil) }
                )
            }
        }
        .animation(.easeInOut(duration: 0.8), value: state.paradeActive)
        .animation(.easeInOut(duration: 0.6), value: state.scene)
    }

    /// Where an entity sits right now: its stored spot normally, or its
    /// parade slot while it is marching. The slot derives from
    /// `paradePhase`, fixed at spawn — other entities joining or leaving
    /// never shift it. Parade choreography is pack-defined
    /// (`ParadeSpec`): lanes hop energetically, graze bobs gently along
    /// a single line; odd lanes march in the opposite direction.
    private func position(for entity: EntityInstance, in size: CGSize, time: TimeInterval,
                          marchingIDs: Set<EntityInstance.ID>) -> CGPoint {
        guard marchingIDs.contains(entity.id) else {
            return CGPoint(
                x: entity.position.x * size.width,
                y: entity.position.y * size.height
            )
        }
        let parade = state.scene.parade
        let lanes = parade.laneY.isEmpty ? [0.8] : parade.laneY
        let lane = min(Int(entity.paradePhase * Double(lanes.count)), lanes.count - 1)
        let span = size.width + 240 // include off-screen margin on both sides
        var progress = (entity.paradePhase + time * parade.speed)
            .truncatingRemainder(dividingBy: 1)
        if lane % 2 == 1 { progress = 1 - progress } // opposite direction
        let x = progress * span - 120
        let baseY = size.height * lanes[lane]
        let wave = parade.waveLength > 0 ? parade.waveLength : 50
        switch parade.style {
        case .lanes:
            let hop = abs(sin(x / wave + entity.paradePhase * .pi * 2)) * parade.amplitude
            return CGPoint(x: x, y: baseY - hop)
        case .graze:
            let bob = sin(x / wave + entity.paradePhase * .pi * 2) * parade.amplitude
            return CGPoint(x: x, y: baseY + bob)
        }
    }
}
